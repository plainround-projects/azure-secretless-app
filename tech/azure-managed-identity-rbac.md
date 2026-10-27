# Managed identity and Azure RBAC

*How the app proves who it is and what it may do. Pinned here: Azure RBAC built-in roles; user-assigned managed identity.*

## What it is

A **managed identity** is an identity that Azure creates and manages for a resource, so the resource can prove who it is to other Azure services without any stored password. **Azure RBAC** (role-based access control) decides what an identity may do: a **role assignment** gives a **principal** (an identity) a **role** (a named set of permissions) at a **scope** (the resource it applies to).

## Why this repository uses it

This is the lesson's subject: the app holds no secret and exactly two roles, each on one resource.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/modules/user_assigned_identity/` | Creates an identity. |
| `infra/modules/role_assignments/` | Creates role assignments and refuses wide scopes. |
| `infra/environments/dev/main.tf` | Decides who gets which role at which scope. |
| `src/secretless_app/infrastructure/azure_adapters.py` | Uses the identity through `DefaultAzureCredential`. |
| `scripts/break-and-measure.sh` | Removes and restores a role. |

## How it works underneath

There are two kinds. A *system-assigned* identity belongs to one resource and is deleted with it. A *user-assigned* identity is its own resource that you can attach to several resources and keep when you replace one. Each identity has a **client id** (the app's name, safe to put in configuration) and a **principal id** or *object id* (what role assignments use).

Inside an Azure resource, code asks the **instance metadata service** at a local address for a token for the identity; Azure signs one and the resource sends it to the service it wants to call. The service looks at the token's principal and at the role assignments that apply to the resource being touched. A role assigned at a larger scope (a resource group) also applies to everything inside it, which is why the narrowest scope is chosen.

Role assignments take minutes to spread, so a call made right after a grant can fail with 403.

## Walkthrough of this repository's use

### Two identities

```hcl
module "app_identity" {
  source = "../../modules/user_assigned_identity"

  name                = local.names.app_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

module "pull_identity" {
  source = "../../modules/user_assigned_identity"

  name                = local.names.pull_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

module "key_vault" {
  source = "../../modules/key_vault"

  name                       = local.names.key_vault
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = var.tenant_id
  log_analytics_workspace_id = module.log_analytics.id
  purge_protection_enabled   = var.purge_protection_enabled
  tags                       = local.tags
}
```

`id-secretless-app` is the identity the code uses. A second identity, `id-secretless-pull`, only pulls the image from the registry. Keeping them apart means the app identity holds exactly two roles, as the lesson's Done when requires.

### The role list

```hcl
  app_assignments = {
    app_reads_secrets = {
      principal_id = module.app_identity.principal_id
      role         = "Key Vault Secrets User"
      scope        = module.key_vault.id
    }
    app_writes_uploads = {
      principal_id = module.app_identity.principal_id
      role         = "Storage Blob Data Contributor"
      scope        = module.storage.container_resource_manager_id
    }
  }

  pull_assignments = {
    pull_reads_registry = {
      principal_id = module.pull_identity.principal_id
      role         = "AcrPull"
      scope        = module.registry.id
    }
  }
```

`Key Vault Secrets User` can read secret values and nothing else. `Storage Blob Data Contributor` can read and write blobs. Each `scope` is a single resource: the vault, and the `uploads` container (not the storage account).

### The module that creates them

```hcl
resource "azurerm_role_assignment" "this" {
  for_each = var.assignments

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role
  scope                = each.value.scope

  # A service principal created seconds ago may not have replicated yet; the principal type avoids the lookup.
  skip_service_principal_aad_check = each.value.principal_type == "ServicePrincipal"
}
```

`for_each` creates one assignment per map entry. `principal_id` is the identity's object id. `skip_service_principal_aad_check` avoids the directory lookup that can fail seconds after an identity is created. The module's variable validations refuse a subscription or resource group scope and the roles Owner, Contributor and User Access Administrator.

### How the app uses the identity

The container app gets both identities attached; `AZURE_CLIENT_ID` is set to the app identity's client id, so `DefaultAzureCredential(managed_identity_client_id=...)` picks the right one (see `azure-identity.md`).

## Try it yourself

Run the module's tests, which include the refused scopes.

```bash
cd infra/modules/role_assignments && terraform init -backend=false -input=false >/dev/null && terraform test 2>&1 | tail -4
```

You should see something like this:

```text
tests/role_assignments.tftest.hcl... tearing down
tests/role_assignments.tftest.hcl... pass

Success! 5 passed, 0 failed.
```

Find the three roles in the composition.

```bash
grep -n 'Key Vault Secrets User\|Storage Blob Data Contributor\|AcrPull' infra/environments/dev/main.tf
```

You should see something like this:

```text
37:      role         = "Key Vault Secrets User"
42:      role         = "Storage Blob Data Contributor"
50:      role         = "AcrPull"
```

## Mistakes people make

- Using the client id where the principal id is needed (`principal does not exist`).
- Assigning a role at the resource group or subscription when one resource is enough. The role module here refuses those scopes.
- Granting Owner or Contributor to an app. Data roles such as `Key Vault Secrets User` are narrower.
- Expecting Owner to read data. Management roles do not include data permissions.
- Reading a missing role as instant: wait a few minutes before deciding it is broken.

## Check yourself

1. **What is the difference between client id and principal id?**
   Answer: The client id names the application; the principal (object) id is what role assignments use.

2. **What are the three parts of a role assignment?**
   Answer: A principal, a role and a scope.

3. **Why choose the narrowest scope?**
   Answer: A role at a larger scope also applies to everything inside it.

4. **User-assigned or system-assigned: which survives replacing the app?**
   Answer: User-assigned, because it is its own resource.

5. **Why can a call fail right after a role is granted?**
   Answer: Role assignments take time to propagate.

## Further reading

- Managed identities: https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview
- Azure RBAC: https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
- Built-in roles: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
