# Terraform

*Defines every Azure resource of the lesson as code. Pinned here: Terraform 1.17.0 (CI pins it); needs 1.9 or newer.*

## What it is

Terraform is a tool that creates and changes cloud resources from text files. You describe the resources you want in the **HashiCorp Configuration Language (HCL)**; Terraform works out what exists, what must change, and makes the changes. The files are the record of your infrastructure, and they live in Git like code.

## Why this repository uses it

Cloud projects must hold their infrastructure as code that can be validated without a subscription. The `infra/` folder is the lesson's resource list: group, workspace, identities, vault, storage, registry, roles, app and budget.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/modules/` | Eight reusable modules, each with variables, outputs, a README and tests. |
| `infra/environments/dev/` | The composition: which modules, with which inputs. |
| `infra/environments/dev/tests/dev.tftest.hcl` | Applies the composition against a mocked provider. |
| `Makefile` | `make validate`, `make tf-test`. |

## How it works underneath

A **resource** block says "this thing should exist" (`resource "azurerm_key_vault" "this" { ... }`). A **variable** is an input, an **output** a result, a **local** a named expression. A **module** is a folder of Terraform files used like a function: `module "x" { source = "../modules/y" ... }`.

`terraform init` downloads the **providers** (plugins that talk to a cloud) named in `required_providers` and records their exact versions and hashes in `.terraform.lock.hcl`. `terraform validate` checks the syntax and that every argument exists and has the right type. `terraform plan` compares the files with the **state** (a record of what Terraform made) and the real cloud and prints what would change. `terraform apply` makes the changes. `terraform destroy` removes everything in the state.

`terraform test` runs files ending in `.tftest.hcl`. Each `run` block plans or applies the configuration and checks `assert` conditions. A `mock_provider` replaces a real provider with a fake that invents values, so tests need no cloud account. `expect_failures` says a variable validation or a precondition is meant to fail.

Terraform decides the order of work from references: if one resource uses another's attribute, the other is created first. `depends_on` adds an order that references do not show. `count` and `for_each` make several copies of a resource or module.

## Walkthrough of this repository's use

### A resource

```hcl
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}
```

`resource "type" "name" { ... }` declares one thing to create. The type (`random_string`) says what kind; the name (`suffix`) is how other code refers to it (`random_string.suffix`). The arguments make five lowercase letters and digits, with no capitals or symbols. Azure needs some names (vault, storage account, registry) to be unique in the whole world, and a random suffix does that.

### Locals: named values

```hcl
  suffix = coalesce(var.suffix, random_string.suffix.result)

  names = {
    resource_group = "rg-${var.name_prefix}"
    workspace      = "law-${var.name_prefix}"
    app_identity   = "id-${var.name_prefix}-app"
    pull_identity  = "id-${var.name_prefix}-pull"
    key_vault      = "kv-${var.name_prefix}-${local.suffix}"
    storage        = "st${var.name_prefix}${local.suffix}"
    registry       = "acr${var.name_prefix}${local.suffix}"
    environment    = "cae-${var.name_prefix}"
    app            = "ca-${var.name_prefix}"
    budget         = "budget-${var.name_prefix}"
  }
```

`locals { ... }` defines values used several times. `coalesce(var.suffix, random_string.suffix.result)` returns the first argument that is not null: the suffix you passed in, or else the generated one. `names` is a map from a short key to the real resource name, so every name is built in one place and follows the lesson (`rg-secretless`, `kv-secretless-<suffix>`). `${var.name_prefix}` puts a variable into text.

```hcl
  tags = merge(
    {
      project     = "azure-secretless-app"
      environment = var.environment
      managed_by  = "terraform"
      owner       = "sumit-srivastava"
    },
    var.tags,
  )
```

`merge(a, b)` combines two maps; the second wins on a clash. Every resource gets the same standard tags, plus any extra ones from `var.tags`.

### The role list as data

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

Each role assignment is a small map with a principal, a role and a scope. This is the one place that decides who may do what. The app identity gets exactly the two roles of the lesson; the third map is the pull identity's.

```hcl
  deployer_assignments = {
    for key, assignment in {
      deployer_sets_secret = {
        principal_id   = var.deployer_object_id
        principal_type = "User"
        role           = "Key Vault Secrets Officer"
        scope          = module.key_vault.id
      }
      deployer_lists_uploads = {
        principal_id   = var.deployer_object_id
        principal_type = "User"
        role           = "Storage Blob Data Reader"
        scope          = module.storage.container_resource_manager_id
      }
    } : key => assignment if var.deployer_object_id != null
  }
```

A `for` expression with `if` builds a map from another map and keeps only the entries whose condition is true. Here the operator's two roles exist only when `deployer_object_id` is given; when it is null the result is an empty map and nothing is granted.

### Modules as functions

```hcl
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

`module "key_vault" { source = "../../modules/key_vault" ... }` calls the module in that folder. The left side of each line is the module's variable; the right side is an expression: `module.log_analytics.id` is an output of another module, which also tells Terraform to create the workspace first.

### Conditional creation

```hcl
module "container_app" {
  source = "../../modules/container_app"
  count  = var.deploy_app ? 1 : 0

  name                       = local.names.app
  environment_name           = local.names.environment
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = module.log_analytics.id
  image                      = coalesce(var.image, "unused.azurecr.io/unused:0")
  app_identity_id            = module.app_identity.id
  pull_identity_id           = module.pull_identity.id
  registry_server            = module.registry.login_server
  tags                       = local.tags

  # Addresses and the client id of the identity. Nothing here is a secret.
  env = {
    AZURE_CLIENT_ID  = module.app_identity.client_id
    VAULT_URL        = module.key_vault.vault_uri
    STORAGE_URL      = module.storage.blob_endpoint
    UPLOAD_CONTAINER = module.storage.container_name
  }

  # The identities must hold their roles before the app starts, or its first request is a denial.
  depends_on = [module.role_assignments]
}
```

`count = var.deploy_app ? 1 : 0` creates the module once or not at all. That is how the container app waits for the second phase: the image must exist before the app can. `depends_on = [module.role_assignments]` orders the app after its roles even though no value flows between them. Outputs use `one(module.container_app[*].url)`, which gives `null` when there is no app.

### Variables with checks

```hcl
variable "image" {
  description = "Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Required when deploy_app is true."
  type        = string
  default     = null

  validation {
    condition     = !var.deploy_app || var.image != null
    error_message = "Set image when deploy_app is true."
  }
}
```

A `validation` block states a condition and an error message. Here the image is required only when `deploy_app` is true; Terraform 1.9 and newer let a validation refer to another variable.

### A module that enforces a rule

```hcl
  validation {
    condition = alltrue([
      for assignment in var.assignments :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/.+/.+", assignment.scope))
    ])
    error_message = "Every scope must be a resource (/subscriptions/.../resourceGroups/.../providers/...), never a subscription or a resource group."
  }

  validation {
    condition = alltrue([
      for assignment in var.assignments :
      contains(["ServicePrincipal", "User", "Group"], assignment.principal_type)
    ])
    error_message = "principal_type must be ServicePrincipal, User or Group."
  }
```

Every scope must look like `/subscriptions/.../resourceGroups/.../providers/...`, so a role cannot be assigned at a resource group or subscription. `can(regex(...))` is true when the pattern matches. `alltrue([for ... : ...])` checks every entry. This turns the lesson's "narrowest scope" rule into a plan-time failure.

### Outputs

```hcl
output "app_role_assignments" {
  description = "The app identity's role assignments. The lesson's Done when: exactly two, each on a single resource."
  value = [
    for assignment in module.role_assignments.assignments :
    { role = assignment.role, scope = assignment.scope }
    if assignment.principal_id == module.app_identity.principal_id
  ]
}
```

A `for` expression with `if` builds a list of the roles that belong to the app identity. The lesson's Done when ("exactly two entries, each scoped to a single resource") is a test on this output.

### The tests

```hcl
run "the_app_identity_holds_exactly_two_roles_each_on_a_single_resource" {
  command = apply

  assert {
    condition     = length(output.app_role_assignments) == 2
    error_message = "the lesson asks for exactly two role assignments for the app identity"
  }

  assert {
    condition     = toset([for assignment in output.app_role_assignments : assignment.role]) == toset(["Key Vault Secrets User", "Storage Blob Data Contributor"])
    error_message = "the two roles are Key Vault Secrets User and Storage Blob Data Contributor"
  }

  assert {
    condition     = alltrue([for assignment in output.app_role_assignments : !endswith(assignment.scope, "/resourceGroups/rg-secretless") && length(split("/", assignment.scope)) > 8])
    error_message = "no role may be assigned at a resource group or wider"
  }

  assert {
    condition     = one([for assignment in output.app_role_assignments : assignment.scope if assignment.role == "Storage Blob Data Contributor"]) == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Storage/storageAccounts/stsecretlessabcde/blobServices/default/containers/uploads"
    error_message = "the blob role must be scoped to the uploads container"
  }
}
```

A `run` block applies the configuration (against the mocked provider declared at the top of the file) and checks each `assert`. `command = apply` gives computed values such as ids a value; `command = plan` is faster and enough for checks on inputs. `override_resource` fixes the values of the two identities so the assertions can compare principal ids.

## Try it yourself

Check the syntax and every argument.

```bash
cd infra/environments/dev && terraform init -backend=false -input=false >/dev/null && terraform validate
```

You should see something like this:

```text
Success! The configuration is valid.
```

Plan and apply the whole composition against the mock.

```bash
cd infra/environments/dev && terraform test 2>&1 | tail -5
```

You should see something like this:

```text
run "every_resource_name_is_built_from_the_prefix_and_suffix"... pass
tests/dev.tftest.hcl... tearing down
tests/dev.tftest.hcl... pass

Success! 10 passed, 0 failed.
```

Check formatting.

```bash
terraform fmt -check -recursive infra && echo formatted
```

You should see something like this:

```text
formatted
```

Check the version.

```bash
terraform version | head -1
```

You should see something like this:

```text
Terraform v1.17.0
```

## Mistakes people make

- Committing state or `.tfvars` files that hold ids or secrets. Here they are git-ignored; only the examples and the phase files (no ids) are committed.
- Putting a secret into a resource: it is written to the state in clear text. The secret in these repositories is set with the CLI and never enters Terraform.
- Running `apply` without reading the plan.
- Editing resources in the portal and not in the files, causing drift. The next plan shows the difference.
- Using wide scopes or owner roles in role assignments. The role module here refuses them.

## Check yourself

1. **What does `terraform init` do?**
   Answer: Downloads the providers and writes the lock file.

2. **What is the state?**
   Answer: Terraform's record of the resources it created.

3. **What is a module?**
   Answer: A folder of Terraform files used like a function with inputs and outputs.

4. **How does `terraform test` work without a cloud account?**
   Answer: A `mock_provider` supplies invented values for every resource.

5. **What does `expect_failures` check?**
   Answer: That a validation or precondition fails, as intended.

## Further reading

- Terraform language: https://developer.hashicorp.com/terraform/language
- Tests: https://developer.hashicorp.com/terraform/language/tests
- CLI (1.17 is pinned in CI): https://developer.hashicorp.com/terraform/cli
