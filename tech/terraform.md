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

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `infra/environments/dev/backend.hcl.example`

7 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 3**

```text
# Remote state in a storage account you create once, outside this project, with Entra authentication:
#   terraform init -backend-config=backend.hcl
resource_group_name  = "rg-terraform-state"
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** **Microsoft Entra ID** (formerly Azure Active Directory) is the identity service of Azure. A **tenant** is one organization's directory in it. Every identity in the directory (a person, a group, an application, a managed identity) has an *object id*, and the party that receives permissions is called the *principal*.

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** Terraform's **state** is a file in which it records the real resources it created and their ids. Each run compares the code, the state and reality to decide what to change. It may contain sensitive values, so it is never committed; a *backend* is the place where the state is stored.

**New idea.** An Azure **resource group** is a folder-like container for the resources of one project. Resources in a group share a life cycle: deleting the group deletes everything in it.

- `# Remote state in a storage account you create once, outside this project, with Entra authentication:`: Comment. By default each environment keeps its Terraform state in a local file, which is fine for practice. For shared work the state belongs in a storage account, so everyone sees the same record of what exists. The next line shows the command that uses this file.
- `#   terraform init -backend-config=backend.hcl`: Comment showing the command: `terraform init -backend-config=backend.hcl` initializes Terraform and fills the (empty) `backend "azurerm" {}` block in `versions.tf` with the settings from this file.
- `resource_group_name  = "rg-terraform-state"`: The resource group that holds the state storage account. This account is created once, by hand, outside this project, so destroying the project can never destroy its own state.

**Lines 4 to 7**

```text
storage_account_name = "stterraformstate00000"
container_name       = "tfstate"
key                  = "azure-secretless-app/dev.tfstate"
use_azuread_auth     = true
```

- `storage_account_name = "stterraformstate00000"`: The name of the storage account that holds the state. The value is a placeholder; replace it with the real name.
- `container_name       = "tfstate"`: The blob container inside that account that holds the state files.
- `key                  = "azure-secretless-app/dev.tfstate"`: The name of the blob (file) for this environment's state; the project and environment name make it unique within the container.
- `use_azuread_auth     = true`: `true` makes Terraform sign in to the storage account with the Entra ID login of the person running it, instead of the account's access key, which fits the project's no-shared-keys rule.

#### `infra/environments/dev/main.tf`

152 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 5**

```hcl
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}
```

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** A **container registry** is a server that stores container images under names and version tags. **Azure Container Registry (ACR)** is Azure's; a service pulls an image from it using an identity that holds the `AcrPull` role.

- `resource "random_string" "suffix" {`: A `resource` block declares one real thing Terraform must create and keep in step with this file. It has two labels: the **type** (such as `azurerm_key_vault`, which names the provider and the kind of thing) and a **local name** (such as `this`) used only to refer to it from other places as `azurerm_key_vault.this`. The lines inside are the thing's settings, called **arguments**. Declares the resource `random_string.suffix`. Creates a random text once and keeps it in the state, so the same value is reused on every later run. It supplies the short suffix that makes globally unique Azure names (Key Vault, storage account, container registry).
- `length  = 5`: `length`: How many characters long the random text is. Here: the number `5`.
- `upper   = false`: `upper`: Whether the random text may contain uppercase letters. Here: `false`.
- `special = false`: `special`: Whether the random text may contain punctuation characters. Here: `false`.
- Closing line: `}` ends the block opened above.

**Lines 7 to 33**

```hcl
locals {
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

  tags = merge(
    {
      project     = "azure-secretless-app"
      environment = var.environment
      managed_by  = "terraform"
      owner       = "sumit-srivastava"
    },
    var.tags,
  )

  # The one place that decides who may do what. Every scope is a single resource.
```

**New idea.** An Azure **budget** watches the spending of a subscription and e-mails people when it passes a threshold such as 80 or 100 percent. It alerts; it does not stop anything from running.

**New idea.** **Tags** are name/value labels attached to Azure resources. They change no behavior; they record the owner, project and environment and make cost reports and clean-up possible.

- `locals {`: A `locals` block defines named values that exist only inside this folder. Each is read as `local.<name>`. They avoid repeating an expression and give a calculation a name. Starts a group of named local values.
- `suffix = coalesce(var.suffix, random_string.suffix.result)`: Defines the local value `suffix` as the input variable `suffix` (Five lowercase characters that make the vault, storage and registry names globally unique. Leave null to generate one), the `result` of the resource `random_string.suffix`. `coalesce(a, b, ...)` returns the first argument that is not `null` or empty.
- `names = {`: Defines the local value `names` as a group of named values that follows.
- `resource_group = "rg-${var.name_prefix}"`: Entry `resource_group`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else). `${...}` inside a quoted string is **interpolation**: Terraform evaluates what is inside and puts its text into the string.
- `workspace      = "law-${var.name_prefix}"`: Entry `workspace`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else).
- `app_identity   = "id-${var.name_prefix}-app"`: Entry `app_identity`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else).
- `pull_identity  = "id-${var.name_prefix}-pull"`: Entry `pull_identity`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else).
- `key_vault      = "kv-${var.name_prefix}-${local.suffix}"`: Entry `key_vault`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else), the local value `suffix`.
- `storage        = "st${var.name_prefix}${local.suffix}"`: Entry `storage`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else), the local value `suffix`.
- `registry       = "acr${var.name_prefix}${local.suffix}"`: Entry `registry`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else), the local value `suffix`.
- `environment    = "cae-${var.name_prefix}"`: Entry `environment`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else).
- `app            = "ca-${var.name_prefix}"`: Entry `app`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else).
- `budget         = "budget-${var.name_prefix}"`: Entry `budget`: text built from the pieces the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else).
- `tags = merge(`: Defines the local value `tags` as `merge(`. `merge(a, b, ...)` combines maps into one; for a key present in several, the later map wins.
- `{`: Opens a nested value.
- `project     = "azure-secretless-app"`: Entry `project`: the text `"azure-secretless-app"`.
- `environment = var.environment`: Entry `environment`: the input variable `environment` (Environment name, used in tags).
- `managed_by  = "terraform"`: Entry `managed_by`: the text `"terraform"`.
- `owner       = "sumit-srivastava"`: Entry `owner`: the text `"sumit-srivastava"`.
- `var.tags,`: Item: the input variable `tags` (Extra tags merged into the standard ones).
- `# The one place that decides who may do what. Every scope is a single resource.`: Comment for the reader: The one place that decides who may do what. Every scope is a single resource.
- Closing lines: `}`, `},`, `)` end the blocks opened above.

**Lines 34 to 53**

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

**New idea.** A **managed identity** is an identity that Azure creates and looks after for a workload, with no password to store or rotate. When the workload runs, it asks a local Azure endpoint for a token for that identity. A *user-assigned* identity exists on its own and can be attached to several resources; its *client id* names it when a program asks for a token and its *principal id* names it when roles are granted.

**New idea.** **Azure role-based access control (RBAC)** decides who may do what. A *role* is a named bundle of permissions (for example "Key Vault Secrets User" may read secrets), a *scope* is where the grant applies (one resource, a resource group, a whole subscription), and a *role assignment* connects an identity, a role and a scope. The smaller the scope, the less a leaked identity can do.

- `app_assignments = {`: Defines the local value `app_assignments` as a group of named values that follows.
- `app_reads_secrets = {`: Entry `app_reads_secrets`: a group of named values that follows.
- `principal_id = module.app_identity.principal_id`: Entry `principal_id`: the output `principal_id` of the module `app_identity`.
- `role         = "Key Vault Secrets User"`: Entry `role`: the text `"Key Vault Secrets User"`.
- `scope        = module.key_vault.id`: Entry `scope`: the output `id` of the module `key_vault`.
- `app_writes_uploads = {`: Entry `app_writes_uploads`: a group of named values that follows.
- `principal_id = module.app_identity.principal_id`: Entry `principal_id`: the output `principal_id` of the module `app_identity`.
- `role         = "Storage Blob Data Contributor"`: Entry `role`: the text `"Storage Blob Data Contributor"`.
- `scope        = module.storage.container_resource_manager_id`: Entry `scope`: the output `container_resource_manager_id` of the module `storage`.
- `pull_assignments = {`: Defines the local value `pull_assignments` as a group of named values that follows.
- `pull_reads_registry = {`: Entry `pull_reads_registry`: a group of named values that follows.
- `principal_id = module.pull_identity.principal_id`: Entry `principal_id`: the output `principal_id` of the module `pull_identity`.
- `role         = "AcrPull"`: Entry `role`: the text `"AcrPull"`.
- `scope        = module.registry.id`: Entry `scope`: the output `id` of the module `registry`.
- Closing lines: `}` end the blocks opened above.

**Lines 55 to 71**

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
}
```

- `deployer_assignments = {`: Defines the local value `deployer_assignments` as a group of named values that follows.
- `for key, assignment in {`: A `for` expression builds a map or list from another collection: `{ for key, value in things : key => f(value) if condition }` means "for every entry that passes the `if`, make this new entry". Part of a `for` expression: `for key, assignment in {`.
- `deployer_sets_secret = {`: Entry `deployer_sets_secret`: a group of named values that follows.
- `principal_id   = var.deployer_object_id`: Entry `principal_id`: the input variable `deployer_object_id` (Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing).
- `principal_type = "User"`: Entry `principal_type`: the text `"User"`.
- `role           = "Key Vault Secrets Officer"`: Entry `role`: the text `"Key Vault Secrets Officer"`.
- `scope          = module.key_vault.id`: Entry `scope`: the output `id` of the module `key_vault`.
- `deployer_lists_uploads = {`: Entry `deployer_lists_uploads`: a group of named values that follows.
- `principal_id   = var.deployer_object_id`: Entry `principal_id`: the input variable `deployer_object_id` (Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing).
- `principal_type = "User"`: Entry `principal_type`: the text `"User"`.
- `role           = "Storage Blob Data Reader"`: Entry `role`: the text `"Storage Blob Data Reader"`.
- `scope          = module.storage.container_resource_manager_id`: Entry `scope`: the output `container_resource_manager_id` of the module `storage`.
- `} : key => assignment if var.deployer_object_id != null`: Part of a `for` expression: `} : key => assignment if var.deployer_object_id != null`.
- Closing lines: `}` end the blocks opened above.

**Lines 73 to 77**

```hcl
resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}
```

**New idea.** An Azure **region** (such as `westeurope`) is a group of data centers in one geographic area. Where a resource is created decides its latency, its price and which legal rules apply.

- `resource "azurerm_resource_group" "this" {`: Declares the resource `azurerm_resource_group.this`. A **resource group** is the folder-like container every other Azure resource of this project lives in. Deleting the group deletes everything in it, which is how the project is torn down in one step.
- `name     = local.names.resource_group`: `name`: The name of this thing in Azure. Here: the local value `names` field `resource_group`.
- `location = var.location`: `location`: The Azure region (data center area) where the thing is created. Here: the input variable `location` (Azure region).
- `tags     = local.tags`: `tags`: Tags are name/value labels attached to the thing. They do not change behavior; they identify the owner, project and environment and make cost reports readable. Here: the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 79 to 86**

```hcl
module "log_analytics" {
  source = "../../modules/log_analytics"

  name                = local.names.workspace
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}
```

- `module "log_analytics" {`: A `module` block calls another folder of Terraform files as a reusable unit. `source` is the folder; the other lines pass values into the module's input variables. The module's outputs come back as `module.<name>.<output>`. Calls a module and names this use of it `log_analytics`; its outputs are read as `module.log_analytics.<output>`.
- `source = "../../modules/log_analytics"`: `source` is the folder holding the module's code: the text `"../../modules/log_analytics"`.
- `name                = local.names.workspace`: Passes `name` (Workspace name, for example law-secretless): the local value `names` field `workspace`.
- `resource_group_name = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds the workspace): the `name` of the resource `azurerm_resource_group.this`.
- `location            = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `tags                = local.tags`: Passes `tags` (Tags applied to the workspace): the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 88 to 95**

```hcl
module "app_identity" {
  source = "../../modules/user_assigned_identity"

  name                = local.names.app_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}
```

- `module "app_identity" {`: Calls a module and names this use of it `app_identity`; its outputs are read as `module.app_identity.<output>`.
- `source = "../../modules/user_assigned_identity"`: `source` is the folder holding the module's code: the text `"../../modules/user_assigned_identity"`.
- `name                = local.names.app_identity`: Passes `name` (Identity name, for example id-secretless-app): the local value `names` field `app_identity`.
- `resource_group_name = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds the identity): the `name` of the resource `azurerm_resource_group.this`.
- `location            = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `tags                = local.tags`: Passes `tags` (Tags applied to the identity): the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 97 to 104**

```hcl
module "pull_identity" {
  source = "../../modules/user_assigned_identity"

  name                = local.names.pull_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}
```

- `module "pull_identity" {`: Calls a module and names this use of it `pull_identity`; its outputs are read as `module.pull_identity.<output>`.
- `source = "../../modules/user_assigned_identity"`: `source` is the folder holding the module's code: the text `"../../modules/user_assigned_identity"`.
- `name                = local.names.pull_identity`: Passes `name` (Identity name, for example id-secretless-app): the local value `names` field `pull_identity`.
- `resource_group_name = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds the identity): the `name` of the resource `azurerm_resource_group.this`.
- `location            = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `tags                = local.tags`: Passes `tags` (Tags applied to the identity): the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 106 to 116**

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

**New idea.** A **GUID** (or UUID) is a 128-bit identifier written as 32 hexadecimal digits in groups, such as `00000000-0000-0000-0000-000000000000`. Azure uses them for subscriptions, tenants and identities. The all-zero value in examples is a placeholder, not a real id.

- `module "key_vault" {`: Calls a module and names this use of it `key_vault`; its outputs are read as `module.key_vault.<output>`.
- `source = "../../modules/key_vault"`: `source` is the folder holding the module's code: the text `"../../modules/key_vault"`.
- `name                       = local.names.key_vault`: Passes `name` (Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique): the local value `names` field `key_vault`.
- `resource_group_name        = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds the vault): the `name` of the resource `azurerm_resource_group.this`.
- `location                   = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `tenant_id                  = var.tenant_id`: Passes `tenant_id` (Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)): the input variable `tenant_id` (Entra tenant GUID (`az account show --query tenantId`)).
- `log_analytics_workspace_id = module.log_analytics.id`: Passes `log_analytics_workspace_id` (Workspace that receives the AuditEvent log): the output `id` of the module `log_analytics`.
- `purge_protection_enabled   = var.purge_protection_enabled`: Passes `purge_protection_enabled` (When true, a deleted vault cannot be purged until the retention ends. Turn it on in production; leave it off for practice so the name can be reused): the input variable `purge_protection_enabled` (Vault purge protection. False for practice (the name can be purged and reused); true in production).
- `tags                       = local.tags`: Passes `tags` (Tags applied to the vault): the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 118 to 126**

```hcl
module "storage" {
  source = "../../modules/storage_uploads"

  name                       = local.names.storage
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.tags
}
```

- `module "storage" {`: Calls a module and names this use of it `storage`; its outputs are read as `module.storage.<output>`.
- `source = "../../modules/storage_uploads"`: `source` is the folder holding the module's code: the text `"../../modules/storage_uploads"`.
- `name                       = local.names.storage`: Passes `name` (Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique): the local value `names` field `storage`.
- `resource_group_name        = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds the account): the `name` of the resource `azurerm_resource_group.this`.
- `location                   = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `log_analytics_workspace_id = module.log_analytics.id`: Passes `log_analytics_workspace_id` (Workspace that receives the blob logs): the output `id` of the module `log_analytics`.
- `tags                       = local.tags`: Passes `tags` (Tags applied to the account): the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 128 to 135**

```hcl
module "registry" {
  source = "../../modules/container_registry"

  name                = local.names.registry
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}
```

- `module "registry" {`: Calls a module and names this use of it `registry`; its outputs are read as `module.registry.<output>`.
- `source = "../../modules/container_registry"`: `source` is the folder holding the module's code: the text `"../../modules/container_registry"`.
- `name                = local.names.registry`: Passes `name` (Registry name: 5 to 50 letters and digits, globally unique): the local value `names` field `registry`.
- `resource_group_name = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds the registry): the `name` of the resource `azurerm_resource_group.this`.
- `location            = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `tags                = local.tags`: Passes `tags` (Tags applied to the registry): the local value `tags`.
- Closing line: `}` ends the block opened above.

**Lines 137 to 141**

```hcl
module "role_assignments" {
  source = "../../modules/role_assignments"

  assignments = merge(local.app_assignments, local.pull_assignments, local.deployer_assignments)
}
```

- `module "role_assignments" {`: Calls a module and names this use of it `role_assignments`; its outputs are read as `module.role_assignments.<output>`.
- `source = "../../modules/role_assignments"`: `source` is the folder holding the module's code: the text `"../../modules/role_assignments"`.
- `assignments = merge(local.app_assignments, local.pull_assignments, local.deployer_assignments)`: Passes `assignments` into the module: the local value `app_assignments`, the local value `pull_assignments`, the local value `deployer_assignments`.
- Closing line: `}` ends the block opened above.

**Lines 143 to 168**

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

**New idea.** A **hash** (or *digest*) is a fixed-length fingerprint calculated from some data. The same data always gives the same hash and any change gives a different one, so comparing hashes shows whether a file or an image is exactly the one that was reviewed.

**New idea.** A **container** is a packaged program together with everything it needs, run in isolation from the rest of the machine. An **image** is the read-only package a container starts from, built with a *Dockerfile*. A **registry** stores images so that other machines can pull them.

**New idea.** A **version number** such as `4.81.0` is read as major.minor.patch. A constraint such as `>=4.81` means "4.81 or newer", and Terraform's `~> 4.81` means "4.81 or newer but below 5.0".

- `module "container_app" {`: Calls a module and names this use of it `container_app`; its outputs are read as `module.container_app.<output>`.
- `source = "../../modules/container_app"`: `source` is the folder holding the module's code: the text `"../../modules/container_app"`.
- `count  = var.deploy_app ? 1 : 0`: `count`: How many copies to create. Here the input variable `deploy_app` (False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)).
- `name                       = local.names.app`: Passes `name` (Container app name): the local value `names` field `app`.
- `environment_name           = local.names.environment`: Passes `environment_name` (Container Apps environment name): the local value `names` field `environment`.
- `resource_group_name        = azurerm_resource_group.this.name`: Passes `resource_group_name` (Resource group that holds both): the `name` of the resource `azurerm_resource_group.this`.
- `location                   = azurerm_resource_group.this.location`: Passes `location` (Azure region): the `location` of the resource `azurerm_resource_group.this`.
- `log_analytics_workspace_id = module.log_analytics.id`: Passes `log_analytics_workspace_id` (Workspace that receives the console logs): the output `id` of the module `log_analytics`.
- `image                      = coalesce(var.image, "unused.azurecr.io/unused:0")`: Passes `image` (Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest): the input variable `image` (Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Required when deploy_app is true).
- `app_identity_id            = module.app_identity.id`: Passes `app_identity_id` (Resource id of the identity the app runs as (it holds the two data roles)): the output `id` of the module `app_identity`.
- `pull_identity_id           = module.pull_identity.id`: Passes `pull_identity_id` (Resource id of the identity that only pulls the image (AcrPull on the registry)): the output `id` of the module `pull_identity`.
- `registry_server            = module.registry.login_server`: Passes `registry_server` (Registry host, for example myregistry.azurecr.io): the output `login_server` of the module `registry`.
- `tags                       = local.tags`: Passes `tags` (Tags applied to both resources): the local value `tags`.
- `# Addresses and the client id of the identity. Nothing here is a secret.`: Comment for the reader: Addresses and the client id of the identity. Nothing here is a secret.
- `env = {`: Passes `env` (Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value): a group of named values that follows.
- `AZURE_CLIENT_ID  = module.app_identity.client_id`: Entry `AZURE_CLIENT_ID`: the output `client_id` of the module `app_identity`.
- `VAULT_URL        = module.key_vault.vault_uri`: Entry `VAULT_URL`: the output `vault_uri` of the module `key_vault`.
- `STORAGE_URL      = module.storage.blob_endpoint`: Entry `STORAGE_URL`: the output `blob_endpoint` of the module `storage`.
- `UPLOAD_CONTAINER = module.storage.container_name`: Entry `UPLOAD_CONTAINER`: the output `container_name` of the module `storage`.
- `# The identities must hold their roles before the app starts, or its first request is a denial.`: Comment for the reader: The identities must hold their roles before the app starts, or its first request is a denial.
- `depends_on = [module.role_assignments]`: `depends_on`: Things that must exist first even though nothing is referenced from them. Here the module `role_assignments`.
- Closing lines: `}` end the blocks opened above.

**Lines 170 to 179**

```hcl
module "budget" {
  source = "../../modules/budget"
  count  = length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = local.names.budget
  subscription_id = var.subscription_id
  amount          = var.budget_amount
  start_date      = coalesce(var.budget_start_date, "2026-01-01T00:00:00Z")
  contact_emails  = var.budget_contact_emails
}
```

**New idea.** An Azure **subscription** is the billing container for resources: everything created in it is charged to it, and its settings and access control apply to it. A *tenant* (the organization's identity directory) can hold several subscriptions.

- `module "budget" {`: Calls a module and names this use of it `budget`; its outputs are read as `module.budget.<output>`.
- `source = "../../modules/budget"`: `source` is the folder holding the module's code: the text `"../../modules/budget"`.
- `count  = length(var.budget_contact_emails) > 0 ? 1 : 0`: `count`: How many copies to create. Here the input variable `budget_contact_emails` (Recipients of the budget alerts. An empty list creates no budget). `length(x)` counts the items of a list, map or characters of text.
- `name            = local.names.budget`: Passes `name` (Budget name): the local value `names` field `budget`.
- `subscription_id = var.subscription_id`: Passes `subscription_id` (Subscription GUID the budget watches): the input variable `subscription_id` (Subscription GUID (`az account show --query id`)).
- `amount          = var.budget_amount`: Passes `amount` (Monthly amount in the billing currency): the input variable `budget_amount` (Monthly budget in the billing currency).
- `start_date      = coalesce(var.budget_start_date, "2026-01-01T00:00:00Z")`: Passes `start_date` (First day of the budget's first month, as 2026-11-01T00:00:00Z. Azure requires the first of a month): the input variable `budget_start_date` (First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contact_emails is set).
- `contact_emails  = var.budget_contact_emails`: Passes `contact_emails` (Addresses that receive the alerts): the input variable `budget_contact_emails` (Recipients of the budget alerts. An empty list creates no budget).
- Closing line: `}` ends the block opened above.

#### `infra/environments/dev/outputs.tf`

68 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "resource_group_name" {
  description = "The one resource group; deleting it is the clean-up plan."
  value       = azurerm_resource_group.this.name
}
```

- `output "resource_group_name" {`: An `output` block exposes a value so that whoever uses this folder (another module, or a person running `terraform output`) can read it. Declares the output `resource_group_name`.
- `description = "The one resource group; deleting it is the clean-up plan."`: `description` documents it: "The one resource group; deleting it is the clean-up plan."
- `value       = azurerm_resource_group.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_resource_group.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "key_vault_name" {
  description = "Vault name (for `az keyvault secret set --vault-name`)."
  value       = module.key_vault.name
}
```

- `output "key_vault_name" {`: Declares the output `key_vault_name`.
- `description = "Vault name (for `az keyvault secret set --vault-name`)."`: `description` documents it: "Vault name (for `az keyvault secret set --vault-name`)."
- `value       = module.key_vault.name`: `value` is what is exposed: the output `name` of the module `key_vault`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "vault_url" {
  description = "The app's VAULT_URL."
  value       = module.key_vault.vault_uri
}
```

- `output "vault_url" {`: Declares the output `vault_url`.
- `description = "The app's VAULT_URL."`: `description` documents it: "The app's VAULT_URL."
- `value       = module.key_vault.vault_uri`: `value` is what is exposed: the output `vault_uri` of the module `key_vault`.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
output "storage_account_name" {
  description = "Account name (for `az storage blob list --account-name`)."
  value       = module.storage.name
}
```

- `output "storage_account_name" {`: Declares the output `storage_account_name`.
- `description = "Account name (for `az storage blob list --account-name`)."`: `description` documents it: "Account name (for `az storage blob list --account-name`)."
- `value       = module.storage.name`: `value` is what is exposed: the output `name` of the module `storage`.
- Closing line: `}` ends the block opened above.

**Lines 21 to 24**

```hcl
output "storage_url" {
  description = "The app's STORAGE_URL."
  value       = module.storage.blob_endpoint
}
```

- `output "storage_url" {`: Declares the output `storage_url`.
- `description = "The app's STORAGE_URL."`: `description` documents it: "The app's STORAGE_URL."
- `value       = module.storage.blob_endpoint`: `value` is what is exposed: the output `blob_endpoint` of the module `storage`.
- Closing line: `}` ends the block opened above.

**Lines 26 to 29**

```hcl
output "container_name" {
  description = "The uploads container."
  value       = module.storage.container_name
}
```

- `output "container_name" {`: Declares the output `container_name`.
- `description = "The uploads container."`: `description` documents it: "The uploads container."
- `value       = module.storage.container_name`: `value` is what is exposed: the output `container_name` of the module `storage`.
- Closing line: `}` ends the block opened above.

**Lines 31 to 34**

```hcl
output "registry_name" {
  description = "Registry name for `az acr build`."
  value       = module.registry.name
}
```

- `output "registry_name" {`: Declares the output `registry_name`.
- `description = "Registry name for `az acr build`."`: `description` documents it: "Registry name for `az acr build`."
- `value       = module.registry.name`: `value` is what is exposed: the output `name` of the module `registry`.
- Closing line: `}` ends the block opened above.

**Lines 36 to 39**

```hcl
output "registry_login_server" {
  description = "Registry host, the prefix of the image name."
  value       = module.registry.login_server
}
```

- `output "registry_login_server" {`: Declares the output `registry_login_server`.
- `description = "Registry host, the prefix of the image name."`: `description` documents it: "Registry host, the prefix of the image name."
- `value       = module.registry.login_server`: `value` is what is exposed: the output `login_server` of the module `registry`.
- Closing line: `}` ends the block opened above.

**Lines 41 to 44**

```hcl
output "app_identity_name" {
  description = "Name of the identity the app runs as."
  value       = module.app_identity.name
}
```

- `output "app_identity_name" {`: Declares the output `app_identity_name`.
- `description = "Name of the identity the app runs as."`: `description` documents it: "Name of the identity the app runs as."
- `value       = module.app_identity.name`: `value` is what is exposed: the output `name` of the module `app_identity`.
- Closing line: `}` ends the block opened above.

**Lines 46 to 49**

```hcl
output "app_identity_client_id" {
  description = "The app's AZURE_CLIENT_ID. It names the identity and is not a secret."
  value       = module.app_identity.client_id
}
```

- `output "app_identity_client_id" {`: Declares the output `app_identity_client_id`.
- `description = "The app's AZURE_CLIENT_ID. It names the identity and is not a secret."`: `description` documents it: "The app's AZURE_CLIENT_ID. It names the identity and is not a secret."
- `value       = module.app_identity.client_id`: `value` is what is exposed: the output `client_id` of the module `app_identity`.
- Closing line: `}` ends the block opened above.

**Lines 51 to 54**

```hcl
output "app_identity_principal_id" {
  description = "Object id of the app identity; the 403 messages in the logs show this value."
  value       = module.app_identity.principal_id
}
```

- `output "app_identity_principal_id" {`: Declares the output `app_identity_principal_id`.
- `description = "Object id of the app identity; the 403 messages in the logs show this value."`: `description` documents it: "Object id of the app identity; the 403 messages in the logs show this value."
- `value       = module.app_identity.principal_id`: `value` is what is exposed: the output `principal_id` of the module `app_identity`.
- Closing line: `}` ends the block opened above.

**Lines 56 to 59**

```hcl
output "log_analytics_workspace_name" {
  description = "Workspace name."
  value       = module.log_analytics.name
}
```

- `output "log_analytics_workspace_name" {`: Declares the output `log_analytics_workspace_name`.
- `description = "Workspace name."`: `description` documents it: "Workspace name."
- `value       = module.log_analytics.name`: `value` is what is exposed: the output `name` of the module `log_analytics`.
- Closing line: `}` ends the block opened above.

**Lines 61 to 64**

```hcl
output "log_analytics_customer_id" {
  description = "Workspace customer id for `az monitor log-analytics query --workspace`."
  value       = module.log_analytics.workspace_id
}
```

- `output "log_analytics_customer_id" {`: Declares the output `log_analytics_customer_id`.
- `description = "Workspace customer id for `az monitor log-analytics query --workspace`."`: `description` documents it: "Workspace customer id for `az monitor log-analytics query --workspace`."
- `value       = module.log_analytics.workspace_id`: `value` is what is exposed: the output `workspace_id` of the module `log_analytics`.
- Closing line: `}` ends the block opened above.

**Lines 66 to 69**

```hcl
output "app_name" {
  description = "Container app name, or null until deploy_app is true."
  value       = one(module.container_app[*].name)
}
```

- `output "app_name" {`: Declares the output `app_name`.
- `description = "Container app name, or null until deploy_app is true."`: `description` documents it: "Container app name, or null until deploy_app is true."
- `value       = one(module.container_app[*].name)`: `value` is what is exposed: the module `container_app`. `one(list)` returns the single item of a list of zero or one items (or `null` when empty).
- Closing line: `}` ends the block opened above.

**Lines 71 to 74**

```hcl
output "app_url" {
  description = "HTTPS address of the app, or null until deploy_app is true."
  value       = one(module.container_app[*].url)
}
```

**New idea.** **TLS** is the protocol that encrypts a network connection and proves who is on the other end, which is what the `s` in `https` stands for. The server proves its identity with a **certificate**, a signed document that names the server and carries its public key; a client refuses a certificate it cannot trust.

- `output "app_url" {`: Declares the output `app_url`.
- `description = "HTTPS address of the app, or null until deploy_app is true."`: `description` documents it: "HTTPS address of the app, or null until deploy_app is true."
- `value       = one(module.container_app[*].url)`: `value` is what is exposed: the module `container_app`.
- Closing line: `}` ends the block opened above.

**Lines 76 to 83**

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

- `output "app_role_assignments" {`: Declares the output `app_role_assignments`.
- `description = "The app identity's role assignments. The lesson's Done when: exactly two, each on a single reso`…: `description` documents it: "The app identity's role assignments. The lesson's Done when: exactly two, each on a single resource."
- `value = [`: `value` is what is exposed: a list that follows.
- `for assignment in module.role_assignments.assignments :`: Part of a `for` expression: `for assignment in module.role_assignments.assignments :`.
- `{ role = assignment.role, scope = assignment.scope }`: Item: `{ role = assignment.role, scope = assignment.scope }`.
- `if assignment.principal_id == module.app_identity.principal_id`: Part of a `for` expression: `if assignment.principal_id == module.app_identity.principal_id`.
- Closing lines: `]`, `}` end the blocks opened above.

#### `infra/environments/dev/terraform.tfvars.example`

15 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 2**

```text
# Copy to terraform.tfvars (git-ignored) or let scripts/provision.sh write it from `az account show`.
# None of these values is a secret; the subscription and tenant ids are still personal, so the real file stays out of git.
```

**New idea.** **git** is the version-control system that records every change to the project's files as a numbered commit, so any earlier state can be recovered and changes can be reviewed. Files listed in `.gitignore` are never recorded.

- `# Copy to terraform.tfvars (git-ignored) or let scripts/provision.sh write it from `az account show`.`: Comment for the reader: Copy to terraform.tfvars (git-ignored) or let scripts/provision.sh write it from `az account show`.
- `# None of these values is a secret; the subscription and tenant ids are still personal, so the real file stays`…: Comment for the reader: None of these values is a secret; the subscription and tenant ids are still personal, so the real file stays out of git.

**Lines 4 to 5**

```text
subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
```

- `subscription_id = "00000000-0000-0000-0000-000000000000"`: A `.tfvars` file assigns values to input variables (`name = value`), one per line. Terraform reads `terraform.tfvars` automatically; other files are passed with `-var-file=`. Sets the input variable `subscription_id` (Subscription GUID (`az account show --query id`)) to the text `"00000000-0000-0000-0000-000000000000"`.
- `tenant_id       = "00000000-0000-0000-0000-000000000000"`: Sets the input variable `tenant_id` (Entra tenant GUID (`az account show --query tenantId`)) to the text `"00000000-0000-0000-0000-000000000000"`.

**Lines 7 to 8**

```text
location    = "westeurope"
name_prefix = "secretless"
```

- `location    = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- `name_prefix = "secretless"`: Sets the input variable `name_prefix` (Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else) to the text `"secretless"`.

**Lines 10 to 11**

```text
# az ad signed-in-user show --query id --output tsv
deployer_object_id = null
```

- `# az ad signed-in-user show --query id --output tsv`: Comment for the reader: az ad signed-in-user show --query id --output tsv
- `deployer_object_id = null`: Sets the input variable `deployer_object_id` (Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing) to `null` (not set).

**Lines 13 to 14**

```text
# Step 1 of the lesson: a budget with an alert at 80 and 100 percent.
budget_contact_emails = ["you@example.com"]
```

- `# Step 1 of the lesson: a budget with an alert at 80 and 100 percent.`: Comment for the reader: Step 1 of the lesson: a budget with an alert at 80 and 100 percent.
- `budget_contact_emails = ["you@example.com"]`: Sets the input variable `budget_contact_emails` (Recipients of the budget alerts. An empty list creates no budget) to `["you@example.com"]`.

**Lines 15 to 16**

```text
budget_amount         = 20
budget_start_date     = "2026-11-01T00:00:00Z"
```

- `budget_amount         = 20`: Sets the input variable `budget_amount` (Monthly budget in the billing currency) to the number `20`.
- `budget_start_date     = "2026-11-01T00:00:00Z"`: Sets the input variable `budget_start_date` (First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contact_emails is set) to the text `"2026-11-01T00:00:00Z"`.

**Lines 18 to 19**

```text
# Phase 1 leaves these off. Phase 2 (scripts/build-and-deploy.sh) sets them.
deploy_app = false
```

- `# Phase 1 leaves these off. Phase 2 (scripts/build-and-deploy.sh) sets them.`: Comment for the reader: Phase 1 leaves these off. Phase 2 (scripts/build-and-deploy.sh) sets them.
- `deploy_app = false`: Sets the input variable `deploy_app` (False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)) to `false`.

**Line 20**

```text
image      = null
```

- `image      = null`: Sets the input variable `image` (Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Required when deploy_app is true) to `null` (not set).

#### `infra/environments/dev/tests/dev.tftest.hcl`

168 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 2**

```hcl
# Plans and applies the whole environment against a mocked azurerm provider: no credentials, no network.
# It proves the composition (who holds which role, what the app is told) and the guards, not Azure's behavior.
```

- `# Plans and applies the whole environment against a mocked azurerm provider: no credentials, no network.`: Comment for the reader: Plans and applies the whole environment against a mocked azurerm provider: no credentials, no network.
- `# It proves the composition (who holds which role, what the app is told) and the guards, not Azure's behavior.`: Comment for the reader: It proves the composition (who holds which role, what the app is told) and the guards, not Azure's behavior.

**Lines 4 to 32**

```hcl
mock_provider "azurerm" {
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.KeyVault/vaults/kv-secretless-abcde"
      vault_uri = "https://kv-secretless-abcde.vault.azure.net/"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Storage/storageAccounts/stsecretlessabcde"
      primary_blob_endpoint = "https://stsecretlessabcde.blob.core.windows.net/"
    }
  }
  mock_resource "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Storage/storageAccounts/stsecretlessabcde/blobServices/default/containers/uploads"
    }
  }
  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ContainerRegistry/registries/acrsecretlessabcde"
      login_server = "acrsecretlessabcde.azurecr.io"
    }
  }
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.OperationalInsights/workspaces/law-secretless"
    }
  }
```

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

**New idea.** A **fake** (or *test double*) is a simple stand-in object used in tests in place of a real service. It behaves like the real one in the ways the test needs, with no network, no account and no cost.

- `mock_provider "azurerm" {`: `mock_provider "azurerm" { ... }` replaces the real `azurerm` provider with a fake for this test file. Instead of calling Azure, the fake invents a value for every setting Terraform asks for. That is how the tests plan and apply the configuration with no Azure account and no network. Starts a `mock_provider` block for `azurerm`.
- `mock_resource "azurerm_key_vault" {`: `mock_resource "type" { defaults = { ... } }` sets the values the fake provider returns for that resource type (here: ids shaped like real Azure ids, so checks that read an id can run). Starts a `mock_resource` block for `azurerm_key_vault`.
- `defaults = {`: `defaults = { ... }` lists the fake values returned for that resource type. The fake values follow.
- `id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Micros`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.KeyVault/vaults/kv-secretless-abcde"`.
- `vault_uri = "https://kv-secretless-abcde.vault.azure.net/"`: Entry `vault_uri`: the text `"https://kv-secretless-abcde.vault.azure.net/"`.
- `mock_resource "azurerm_storage_account" {`: Starts a `mock_resource` block for `azurerm_storage_account`.
- `defaults = {`: The fake values follow.
- `id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/prov`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Storage/storageAccounts/stsecretlessabcde"`.
- `primary_blob_endpoint = "https://stsecretlessabcde.blob.core.windows.net/"`: Entry `primary_blob_endpoint`: the text `"https://stsecretlessabcde.blob.core.windows.net/"`.
- `mock_resource "azurerm_storage_container" {`: Starts a `mock_resource` block for `azurerm_storage_container`.
- `defaults = {`: The fake values follow.
- `id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Sto`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Storage/storageAccounts/stsecretlessabcde/blobServices/default/containers/uploads"`.
- `mock_resource "azurerm_container_registry" {`: Starts a `mock_resource` block for `azurerm_container_registry`.
- `defaults = {`: The fake values follow.
- `id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Mic`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ContainerRegistry/registries/acrsecretlessabcde"`.
- `login_server = "acrsecretlessabcde.azurecr.io"`: Entry `login_server`: the text `"acrsecretlessabcde.azurecr.io"`.
- `mock_resource "azurerm_log_analytics_workspace" {`: Starts a `mock_resource` block for `azurerm_log_analytics_workspace`.
- `defaults = {`: The fake values follow.
- `id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Ope`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.OperationalInsights/workspaces/law-secretless"`.
- Closing lines: `}` end the blocks opened above.

**Lines 33 to 43**

```hcl
  mock_resource "azurerm_container_app_environment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.App/managedEnvironments/cae-secretless"
    }
  }
  mock_resource "azurerm_container_app" {
    defaults = {
      ingress = { fqdn = "ca-secretless.example.westeurope.azurecontainerapps.io" }
    }
  }
}
```

- `mock_resource "azurerm_container_app_environment" {`: Starts a `mock_resource` block for `azurerm_container_app_environment`.
- `defaults = {`: The fake values follow.
- `id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.App`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.App/managedEnvironments/cae-secretless"`.
- `mock_resource "azurerm_container_app" {`: Starts a `mock_resource` block for `azurerm_container_app`.
- `defaults = {`: The fake values follow.
- `ingress = { fqdn = "ca-secretless.example.westeurope.azurecontainerapps.io" }`: Entry `ingress`: `{ fqdn = "ca-secretless.example.westeurope.azurecontainerapps.io" }`.
- Closing lines: `}` end the blocks opened above.

**Lines 45 to 52**

```hcl
override_resource {
  target = module.app_identity.azurerm_user_assigned_identity.this
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-secretless-app"
    principal_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    client_id    = "cccccccc-cccc-cccc-cccc-cccccccccccc"
  }
}
```

- `override_resource {`: `override_resource { target = ...  values = { ... } }` fixes the settings of one specific resource instance (named by its address) instead of letting the mock invent them; the tests use it to give an identity a known principal id so that assertions can compare it. Starts an `override_resource` block.
- `target = module.app_identity.azurerm_user_assigned_identity.this`: `target` names the resource instance by address, such as `azurerm_user_assigned_identity.this`. `target` is the output `azurerm_user_assigned_identity` of the module `app_identity`.
- `values = {`: `values = { ... }` lists the settings to force. The settings follow.
- `id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Mic`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-secretless-app"`.
- `principal_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"`: Entry `principal_id`: the text `"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"`.
- `client_id    = "cccccccc-cccc-cccc-cccc-cccccccccccc"`: Entry `client_id`: the text `"cccccccc-cccc-cccc-cccc-cccccccccccc"`.
- Closing lines: `}` end the blocks opened above.

**Lines 54 to 61**

```hcl
override_resource {
  target = module.pull_identity.azurerm_user_assigned_identity.this
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-secretless-pull"
    principal_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    client_id    = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  }
}
```

- `override_resource {`: Starts an `override_resource` block.
- `target = module.pull_identity.azurerm_user_assigned_identity.this`: `target` is the output `azurerm_user_assigned_identity` of the module `pull_identity`.
- `values = {`: The settings follow.
- `id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Mic`…: Entry `id`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-secretless-pull"`.
- `principal_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"`: Entry `principal_id`: the text `"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"`.
- `client_id    = "dddddddd-dddd-dddd-dddd-dddddddddddd"`: Entry `client_id`: the text `"dddddddd-dddd-dddd-dddd-dddddddddddd"`.
- Closing lines: `}` end the blocks opened above.

**Lines 63 to 67**

```hcl
variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "11111111-1111-1111-1111-111111111111"
  suffix          = "abcde"
}
```

- `variables {`: A `variables { ... }` block gives values to the input variables: at the top of the file for every step, or inside a `run` block for that step only. Starts a `variables` block.
- `subscription_id = "00000000-0000-0000-0000-000000000000"`: Sets the input variable `subscription_id` (Subscription GUID (`az account show --query id`)) to the text `"00000000-0000-0000-0000-000000000000"`.
- `tenant_id       = "11111111-1111-1111-1111-111111111111"`: Sets the input variable `tenant_id` (Entra tenant GUID (`az account show --query tenantId`)) to the text `"11111111-1111-1111-1111-111111111111"`.
- `suffix          = "abcde"`: Sets the input variable `suffix` (Five lowercase characters that make the vault, storage and registry names globally unique. Leave null to generate one) to the text `"abcde"`.
- Closing line: `}` ends the block opened above.

**Lines 69 to 91**

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

- `run "the_app_identity_holds_exactly_two_roles_each_on_a_single_resource" {`: A `run "name" { ... }` block is one test step. Terraform plans (or plans and applies) the configuration against the mock provider, then evaluates the `assert` blocks. Steps run in file order and a failed `assert` fails the test. Starts the test step `the app identity holds exactly two roles each on a single resource`.
- `command = apply`: `command = apply` runs a full apply against the mock, so values computed on creation are available to the assertions. It is the default when `command` is left out. `command = apply`.
- `assert {`: An `assert { condition = ...  error_message = ... }` block states something that must be true. If the condition is false, the step fails and prints the message. Starts an `assert` block.
- `condition     = length(output.app_role_assignments) == 2`: `condition` is the rule: `length(output.app_role_assignments) == 2` must be true.
- `error_message = "the lesson asks for exactly two role assignments for the app identity"`: `error_message` is shown when the rule fails: "the lesson asks for exactly two role assignments for the app identity"
- `assert {`: Starts an `assert` block.
- `condition     = toset([for assignment in output.app_role_assignments : assignment.role]) == toset(["Key Vault `…: `condition` is the rule: `toset([for assignment in output.app_role_assignments : assignment.role]) == toset(["Key Vault Secrets User", "Storage Blob Data Contributor"])` must be true. `toset(list)` converts a list to a set (no duplicates, no order).
- `error_message = "the two roles are Key Vault Secrets User and Storage Blob Data Contributor"`: `error_message` is shown when the rule fails: "the two roles are Key Vault Secrets User and Storage Blob Data Contributor"
- `assert {`: Starts an `assert` block.
- `condition     = alltrue([for assignment in output.app_role_assignments : !endswith(assignment.scope, "/resourc`…: `condition` is the rule: `alltrue([for assignment in output.app_role_assignments : !endswith(assignment.scope, "/resourceGroups/rg-secretless") && length(split("/", assignment.scope)) > 8])` must be true. `alltrue(list)` is true when every item is true. `endswith(text, suffix)` is true when the text ends with the suffix. `split(separator, text)` cuts text into a list.
- `error_message = "no role may be assigned at a resource group or wider"`: `error_message` is shown when the rule fails: "no role may be assigned at a resource group or wider"
- `assert {`: Starts an `assert` block.
- `condition     = one([for assignment in output.app_role_assignments : assignment.scope if assignment.role == "S`…: `condition` is the rule: `one([for assignment in output.app_role_assignments : assignment.scope if assignment.role == "Storage Blob Data Contributor"]) == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.Storage/storageAccounts/stsecretlessabcde/blobServices/default/containers/uploads"` must be true.
- `error_message = "the blob role must be scoped to the uploads container"`: `error_message` is shown when the rule fails: "the blob role must be scoped to the uploads container"
- Closing lines: `}` end the blocks opened above.

**Lines 93 to 105**

```hcl
run "the_pull_identity_reads_the_registry_and_nothing_else" {
  command = apply

  assert {
    condition     = length([for assignment in module.role_assignments.assignments : assignment if assignment.principal_id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]) == 1
    error_message = "the pull identity holds one role"
  }

  assert {
    condition     = one([for assignment in module.role_assignments.assignments : assignment.role if assignment.principal_id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]) == "AcrPull"
    error_message = "the pull identity's role is AcrPull"
  }
}
```

- `run "the_pull_identity_reads_the_registry_and_nothing_else" {`: Starts the test step `the pull identity reads the registry and nothing else`.
- `command = apply`: `command = apply`.
- `assert {`: Starts an `assert` block.
- `condition     = length([for assignment in module.role_assignments.assignments : assignment if assignment.princ`…: `condition` is the rule: `length([for assignment in module.role_assignments.assignments : assignment if assignment.principal_id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]) == 1` must be true.
- `error_message = "the pull identity holds one role"`: `error_message` is shown when the rule fails: "the pull identity holds one role"
- `assert {`: Starts an `assert` block.
- `condition     = one([for assignment in module.role_assignments.assignments : assignment.role if assignment.pri`…: `condition` is the rule: `one([for assignment in module.role_assignments.assignments : assignment.role if assignment.principal_id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]) == "AcrPull"` must be true.
- `error_message = "the pull identity's role is AcrPull"`: `error_message` is shown when the rule fails: "the pull identity's role is AcrPull"
- Closing lines: `}` end the blocks opened above.

**Lines 107 to 114**

```hcl
run "no_deployer_roles_unless_asked" {
  command = apply

  assert {
    condition     = length(module.role_assignments.assignments) == 3
    error_message = "two for the app and one for the pull identity, and nothing for a deployer that was not named"
  }
}
```

- `run "no_deployer_roles_unless_asked" {`: Starts the test step `no deployer roles unless asked`.
- `command = apply`: `command = apply`.
- `assert {`: Starts an `assert` block.
- `condition     = length(module.role_assignments.assignments) == 3`: `condition` is the rule: `length(module.role_assignments.assignments) == 3` must be true.
- `error_message = "two for the app and one for the pull identity, and nothing for a deployer that was not named"`: `error_message` is shown when the rule fails: "two for the app and one for the pull identity, and nothing for a deployer that was not named"
- Closing lines: `}` end the blocks opened above.

**Lines 116 to 127**

```hcl
run "a_named_deployer_gets_two_data_roles_and_no_management_role" {
  command = apply

  variables {
    deployer_object_id = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
  }

  assert {
    condition     = toset([for assignment in module.role_assignments.assignments : assignment.role if assignment.principal_id == "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"]) == toset(["Key Vault Secrets Officer", "Storage Blob Data Reader"])
    error_message = "the deployer sets the secret and lists blobs, nothing more"
  }
}
```

- `run "a_named_deployer_gets_two_data_roles_and_no_management_role" {`: Starts the test step `a named deployer gets two data roles and no management role`.
- `command = apply`: `command = apply`.
- `variables {`: Starts a `variables` block.
- `deployer_object_id = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"`: Sets the input variable `deployer_object_id` (Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing) to the text `"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"`.
- `assert {`: Starts an `assert` block.
- `condition     = toset([for assignment in module.role_assignments.assignments : assignment.role if assignment.p`…: `condition` is the rule: `toset([for assignment in module.role_assignments.assignments : assignment.role if assignment.principal_id == "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"]) == toset(["Key Vault Secrets Officer", "Storage Blob Data Reader"])` must be true.
- `error_message = "the deployer sets the secret and lists blobs, nothing more"`: `error_message` is shown when the rule fails: "the deployer sets the secret and lists blobs, nothing more"
- Closing lines: `}` end the blocks opened above.

**Lines 129 to 141**

```hcl
run "the_first_phase_builds_everything_except_the_app" {
  command = apply

  assert {
    condition     = output.app_url == null && output.app_name == null
    error_message = "with deploy_app false there is no container app"
  }

  assert {
    condition     = output.registry_login_server == "acrsecretlessabcde.azurecr.io"
    error_message = "the registry must exist so the image can be built before the app"
  }
}
```

- `run "the_first_phase_builds_everything_except_the_app" {`: Starts the test step `the first phase builds everything except the app`.
- `command = apply`: `command = apply`.
- `assert {`: Starts an `assert` block.
- `condition     = output.app_url == null && output.app_name == null`: `condition` is the rule: `output.app_url == null && output.app_name == null` must be true.
- `error_message = "with deploy_app false there is no container app"`: `error_message` is shown when the rule fails: "with deploy_app false there is no container app"
- `assert {`: Starts an `assert` block.
- `condition     = output.registry_login_server == "acrsecretlessabcde.azurecr.io"`: `condition` is the rule: `output.registry_login_server == "acrsecretlessabcde.azurecr.io"` must be true.
- `error_message = "the registry must exist so the image can be built before the app"`: `error_message` is shown when the rule fails: "the registry must exist so the image can be built before the app"
- Closing lines: `}` end the blocks opened above.

**Lines 143 to 155**

```hcl
run "the_second_phase_adds_the_app_behind_an_https_address" {
  command = apply

  variables {
    deploy_app = true
    image      = "acrsecretlessabcde.azurecr.io/azure-secretless-app:0.1.0"
  }

  assert {
    condition     = output.app_url == "https://ca-secretless.example.westeurope.azurecontainerapps.io"
    error_message = "the app must be reachable over HTTPS"
  }
}
```

- `run "the_second_phase_adds_the_app_behind_an_https_address" {`: Starts the test step `the second phase adds the app behind an https address`.
- `command = apply`: `command = apply`.
- `variables {`: Starts a `variables` block.
- `deploy_app = true`: Sets the input variable `deploy_app` (False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)) to `true`.
- `image      = "acrsecretlessabcde.azurecr.io/azure-secretless-app:0.1.0"`: Sets the input variable `image` (Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Required when deploy_app is true) to the text `"acrsecretlessabcde.azurecr.io/azure-secretless-app:0.1.0"`.
- `assert {`: Starts an `assert` block.
- `condition     = output.app_url == "https://ca-secretless.example.westeurope.azurecontainerapps.io"`: `condition` is the rule: `output.app_url == "https://ca-secretless.example.westeurope.azurecontainerapps.io"` must be true.
- `error_message = "the app must be reachable over HTTPS"`: `error_message` is shown when the rule fails: "the app must be reachable over HTTPS"
- Closing lines: `}` end the blocks opened above.

**Lines 157 to 165**

```hcl
run "an_app_without_an_image_is_refused" {
  command = plan

  variables {
    deploy_app = true
  }

  expect_failures = [var.image]
}
```

- `run "an_app_without_an_image_is_refused" {`: Starts the test step `an app without an image is refused`.
- `command = plan`: `command = plan` only computes what would be created. Values that exist only after creation (ids) are unknown, so this suits checks on inputs and fixed settings. `command = plan`.
- `variables {`: Starts a `variables` block.
- `deploy_app = true`: Sets the input variable `deploy_app` (False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)) to `true`.
- `expect_failures = [var.image]`: `expect_failures = [var.x]` says this step is *meant* to fail on that variable's validation (or a precondition). The step passes only if that failure happens, which is how rules that refuse bad input are tested. Expects the failure of [var.image].
- Closing lines: `}` end the blocks opened above.

**Lines 167 to 175**

```hcl
run "a_budget_needs_a_start_date" {
  command = plan

  variables {
    budget_contact_emails = ["owner@example.com"]
  }

  expect_failures = [var.budget_start_date]
}
```

- `run "a_budget_needs_a_start_date" {`: Starts the test step `a budget needs a start date`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `budget_contact_emails = ["owner@example.com"]`: Sets the input variable `budget_contact_emails` (Recipients of the budget alerts. An empty list creates no budget) to `["owner@example.com"]`.
- `expect_failures = [var.budget_start_date]`: Expects the failure of [var.budget_start_date].
- Closing lines: `}` end the blocks opened above.

**Lines 177 to 189**

```hcl
run "a_budget_is_created_when_recipients_and_a_start_date_are_given" {
  command = plan

  variables {
    budget_contact_emails = ["owner@example.com"]
    budget_start_date     = "2026-11-01T00:00:00Z"
  }

  assert {
    condition     = length(module.budget) == 1
    error_message = "the budget module must be created"
  }
}
```

- `run "a_budget_is_created_when_recipients_and_a_start_date_are_given" {`: Starts the test step `a budget is created when recipients and a start date are given`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `budget_contact_emails = ["owner@example.com"]`: Sets the input variable `budget_contact_emails` (Recipients of the budget alerts. An empty list creates no budget) to `["owner@example.com"]`.
- `budget_start_date     = "2026-11-01T00:00:00Z"`: Sets the input variable `budget_start_date` (First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contact_emails is set) to the text `"2026-11-01T00:00:00Z"`.
- `assert {`: Starts an `assert` block.
- `condition     = length(module.budget) == 1`: `condition` is the rule: `length(module.budget) == 1` must be true.
- `error_message = "the budget module must be created"`: `error_message` is shown when the rule fails: "the budget module must be created"
- Closing lines: `}` end the blocks opened above.

**Lines 191 to 203**

```hcl
run "every_resource_name_is_built_from_the_prefix_and_suffix" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-secretless" && module.key_vault.name == "kv-secretless-abcde" && module.storage.name == "stsecretlessabcde"
    error_message = "names must follow the lesson's rg-secretless, kv-secretless-<suffix>, stsecretless<suffix>"
  }

  assert {
    condition     = azurerm_resource_group.this.tags["managed_by"] == "terraform" && azurerm_resource_group.this.tags["project"] == "azure-secretless-app"
    error_message = "the standard tags must be present"
  }
}
```

- `run "every_resource_name_is_built_from_the_prefix_and_suffix" {`: Starts the test step `every resource name is built from the prefix and suffix`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_resource_group.this.name == "rg-secretless" && module.key_vault.name == "kv-secretless`…: `condition` is the rule: `azurerm_resource_group.this.name == "rg-secretless" && module.key_vault.name == "kv-secretless-abcde" && module.storage.name == "stsecretlessabcde"` must be true.
- `error_message = "names must follow the lesson's rg-secretless, kv-secretless-<suffix>, stsecretless<suffix>"`: `error_message` is shown when the rule fails: "names must follow the lesson's rg-secretless, kv-secretless-<suffix>, stsecretless<suffix>"
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_resource_group.this.tags["managed_by"] == "terraform" && azurerm_resource_group.this.t`…: `condition` is the rule: `azurerm_resource_group.this.tags["managed_by"] == "terraform" && azurerm_resource_group.this.tags["project"] == "azure-secretless-app"` must be true.
- `error_message = "the standard tags must be present"`: `error_message` is shown when the rule fails: "the standard tags must be present"
- Closing lines: `}` end the blocks opened above.

#### `infra/environments/dev/variables.tf`

92 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 9**

```hcl
variable "subscription_id" {
  description = "Subscription GUID (`az account show --query id`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}
```

**New idea.** A **regular expression** is a compact pattern for matching text: `[a-z]` is one lowercase letter, `+` means one or more, `^` and `$` mark the start and end, `{1,127}` means one to 127 repeats.

- `variable "subscription_id" {`: A `variable` block declares an **input**: a value the caller supplies when using this configuration or module. Inside the folder it is read as `var.<name>`. Terraform checks the value against `type` and any `validation` rules before doing anything. Declares the input variable `subscription_id`.
- `description = "Subscription GUID (`az account show --query id`)."`: `description` documents it: "Subscription GUID (`az account show --query id`)."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: A `validation` block makes Terraform refuse a bad input value early. The `condition` is an expression that must be true; if it is false Terraform stops and prints `error_message`. Starts a rule the input value must satisfy.
- `condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))`: `condition` is the rule: `can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))` must be true. `can(expr)` is true when the expression evaluates without an error. `regex(pattern, text)` returns the part of the text that matches a regular expression, and fails if there is no match.
- `error_message = "subscription_id must be a GUID."`: `error_message` is shown when the rule fails: "subscription_id must be a GUID."
- Closing lines: `}` end the blocks opened above.

**Lines 11 to 19**

```hcl
variable "tenant_id" {
  description = "Entra tenant GUID (`az account show --query tenantId`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}
```

- `variable "tenant_id" {`: Declares the input variable `tenant_id`.
- `description = "Entra tenant GUID (`az account show --query tenantId`)."`: `description` documents it: "Entra tenant GUID (`az account show --query tenantId`)."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))`: `condition` is the rule: `can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))` must be true.
- `error_message = "tenant_id must be a GUID."`: `error_message` is shown when the rule fails: "tenant_id must be a GUID."
- Closing lines: `}` end the blocks opened above.

**Lines 21 to 25**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "westeurope"`: `default` is used when the caller passes nothing: the text `"westeurope"`.
- Closing line: `}` ends the block opened above.

**Lines 27 to 31**

```hcl
variable "environment" {
  description = "Environment name, used in tags."
  type        = string
  default     = "dev"
}
```

- `variable "environment" {`: Declares the input variable `environment`.
- `description = "Environment name, used in tags."`: `description` documents it: "Environment name, used in tags."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "dev"`: `default` is used when the caller passes nothing: the text `"dev"`.
- Closing line: `}` ends the block opened above.

**Lines 33 to 42**

```hcl
variable "name_prefix" {
  description = "Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else."
  type        = string
  default     = "secretless"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 12 lowercase letters or digits."
  }
}
```

- `variable "name_prefix" {`: Declares the input variable `name_prefix`.
- `description = "Short lowercase word in every resource name. Letters and digits only, because storage account n`…: `description` documents it: "Short lowercase word in every resource name. Letters and digits only, because storage account names allow nothing else."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "secretless"`: `default` is used when the caller passes nothing: the text `"secretless"`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[a-z0-9]{3,12}$", var.name_prefix))`: `condition` is the rule: `can(regex("^[a-z0-9]{3,12}$", var.name_prefix))` must be true.
- `error_message = "name_prefix must be 3 to 12 lowercase letters or digits."`: `error_message` is shown when the rule fails: "name_prefix must be 3 to 12 lowercase letters or digits."
- Closing lines: `}` end the blocks opened above.

**Lines 44 to 53**

```hcl
variable "suffix" {
  description = "Five lowercase characters that make the vault, storage and registry names globally unique. Leave null to generate one."
  type        = string
  default     = null

  validation {
    condition     = var.suffix == null || can(regex("^[a-z0-9]{3,6}$", var.suffix))
    error_message = "suffix must be 3 to 6 lowercase letters or digits."
  }
}
```

- `variable "suffix" {`: Declares the input variable `suffix`.
- `description = "Five lowercase characters that make the vault, storage and registry names globally unique. Leav`…: `description` documents it: "Five lowercase characters that make the vault, storage and registry names globally unique. Leave null to generate one."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = null`: `default` is used when the caller passes nothing: `null` (not set).
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = var.suffix == null || can(regex("^[a-z0-9]{3,6}$", var.suffix))`: `condition` is the rule: `var.suffix == null || can(regex("^[a-z0-9]{3,6}$", var.suffix))` must be true.
- `error_message = "suffix must be 3 to 6 lowercase letters or digits."`: `error_message` is shown when the rule fails: "suffix must be 3 to 6 lowercase letters or digits."
- Closing lines: `}` end the blocks opened above.

**Lines 55 to 59**

```hcl
variable "deployer_object_id" {
  description = "Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing."
  type        = string
  default     = null
}
```

- `variable "deployer_object_id" {`: Declares the input variable `deployer_object_id`.
- `description = "Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get `…: `description` documents it: "Object id of the person who runs the lesson (`az ad signed-in-user show --query id`). They get Key Vault Secrets Officer on the vault and Storage Blob Data Reader on the container, so they can set the secret and list blobs. Null grants nothing."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = null`: `default` is used when the caller passes nothing: `null` (not set).
- Closing line: `}` ends the block opened above.

**Lines 61 to 65**

```hcl
variable "purge_protection_enabled" {
  description = "Vault purge protection. False for practice (the name can be purged and reused); true in production."
  type        = bool
  default     = false
}
```

- `variable "purge_protection_enabled" {`: Declares the input variable `purge_protection_enabled`.
- `description = "Vault purge protection. False for practice (the name can be purged and reused); true in product`…: `description` documents it: "Vault purge protection. False for practice (the name can be purged and reused); true in production."
- `type        = bool`: `type` limits what is accepted: `bool`: `true` or `false`.
- `default     = false`: `default` is used when the caller passes nothing: `false`.
- Closing line: `}` ends the block opened above.

**Lines 67 to 71**

```hcl
variable "deploy_app" {
  description = "False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)."
  type        = bool
  default     = false
}
```

- `variable "deploy_app" {`: Declares the input variable `deploy_app`.
- `description = "False creates everything except the container app, so the image can be built in the registry fi`…: `description` documents it: "False creates everything except the container app, so the image can be built in the registry first. True adds the app (set `image`)."
- `type        = bool`: `type` limits what is accepted: `bool`: `true` or `false`.
- `default     = false`: `default` is used when the caller passes nothing: `false`.
- Closing line: `}` ends the block opened above.

**Lines 73 to 82**

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

- `variable "image" {`: Declares the input variable `image`.
- `description = "Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Requ`…: `description` documents it: "Image for the container app, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Required when deploy_app is true."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = null`: `default` is used when the caller passes nothing: `null` (not set).
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = !var.deploy_app || var.image != null`: `condition` is the rule: `!var.deploy_app || var.image != null` must be true.
- `error_message = "Set image when deploy_app is true."`: `error_message` is shown when the rule fails: "Set image when deploy_app is true."
- Closing lines: `}` end the blocks opened above.

**Lines 84 to 88**

```hcl
variable "budget_contact_emails" {
  description = "Recipients of the budget alerts. An empty list creates no budget."
  type        = list(string)
  default     = []
}
```

- `variable "budget_contact_emails" {`: Declares the input variable `budget_contact_emails`.
- `description = "Recipients of the budget alerts. An empty list creates no budget."`: `description` documents it: "Recipients of the budget alerts. An empty list creates no budget."
- `type        = list(string)`: `type` limits what is accepted: `list(string)`: an ordered list of texts.
- `default     = []`: `default` is used when the caller passes nothing: `[]`.
- Closing line: `}` ends the block opened above.

**Lines 90 to 94**

```hcl
variable "budget_amount" {
  description = "Monthly budget in the billing currency."
  type        = number
  default     = 20
}
```

- `variable "budget_amount" {`: Declares the input variable `budget_amount`.
- `description = "Monthly budget in the billing currency."`: `description` documents it: "Monthly budget in the billing currency."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 20`: `default` is used when the caller passes nothing: the number `20`.
- Closing line: `}` ends the block opened above.

**Lines 96 to 105**

```hcl
variable "budget_start_date" {
  description = "First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contact_emails is set."
  type        = string
  default     = null

  validation {
    condition     = length(var.budget_contact_emails) == 0 || var.budget_start_date != null
    error_message = "Set budget_start_date when budget_contact_emails is set."
  }
}
```

- `variable "budget_start_date" {`: Declares the input variable `budget_start_date`.
- `description = "First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contac`…: `description` documents it: "First of a month at midnight UTC, for example 2026-11-01T00:00:00Z. Required when budget_contact_emails is set."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = null`: `default` is used when the caller passes nothing: `null` (not set).
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = length(var.budget_contact_emails) == 0 || var.budget_start_date != null`: `condition` is the rule: `length(var.budget_contact_emails) == 0 || var.budget_start_date != null` must be true.
- `error_message = "Set budget_start_date when budget_contact_emails is set."`: `error_message` is shown when the rule fails: "Set budget_start_date when budget_contact_emails is set."
- Closing lines: `}` end the blocks opened above.

**Lines 107 to 111**

```hcl
variable "tags" {
  description = "Extra tags merged into the standard ones."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Extra tags merged into the standard ones."`: `description` documents it: "Extra tags merged into the standard ones."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/budget/outputs.tf`

4 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "id" {
  description = "Budget resource id."
  value       = azurerm_consumption_budget_subscription.this.id
}
```

- `output "id" {`: Declares the output `id`.
- `description = "Budget resource id."`: `description` documents it: "Budget resource id."
- `value       = azurerm_consumption_budget_subscription.this.id`: `value` is what is exposed: the `id` of the resource `azurerm_consumption_budget_subscription.this`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/budget/tests/budget.tftest.hcl`

29 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 9**

```hcl
variables {
  name            = "budget-secretless"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  amount          = 20
  start_date      = "2026-11-01T00:00:00Z"
  contact_emails  = ["owner@example.com"]
}
```

- `variables {`: Starts a `variables` block.
- `name            = "budget-secretless"`: Sets the input variable `name` (Budget name) to the text `"budget-secretless"`.
- `subscription_id = "00000000-0000-0000-0000-000000000000"`: Sets the input variable `subscription_id` (Subscription GUID the budget watches) to the text `"00000000-0000-0000-0000-000000000000"`.
- `amount          = 20`: Sets the input variable `amount` (Monthly amount in the billing currency) to the number `20`.
- `start_date      = "2026-11-01T00:00:00Z"`: Sets the input variable `start_date` (First day of the budget's first month, as 2026-11-01T00:00:00Z. Azure requires the first of a month) to the text `"2026-11-01T00:00:00Z"`.
- `contact_emails  = ["owner@example.com"]`: Sets the input variable `contact_emails` (Addresses that receive the alerts) to `["owner@example.com"]`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 18**

```hcl
run "alerts_at_80_and_100_percent_of_actual_spend" {
  command = plan

  assert {
    condition     = toset([for notification in azurerm_consumption_budget_subscription.this.notification : notification.threshold]) == toset([80, 100])
    error_message = "the budget must alert at 80 and 100 percent"
  }
}
```

- `run "alerts_at_80_and_100_percent_of_actual_spend" {`: Starts the test step `alerts at 80 and 100 percent of actual spend`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = toset([for notification in azurerm_consumption_budget_subscription.this.notification : notific`…: `condition` is the rule: `toset([for notification in azurerm_consumption_budget_subscription.this.notification : notification.threshold]) == toset([80, 100])` must be true.
- `error_message = "the budget must alert at 80 and 100 percent"`: `error_message` is shown when the rule fails: "the budget must alert at 80 and 100 percent"
- Closing lines: `}` end the blocks opened above.

**Lines 20 to 28**

```hcl
run "refuses_a_start_date_that_is_not_the_first_of_a_month" {
  command = plan

  variables {
    start_date = "2026-11-15T00:00:00Z"
  }

  expect_failures = [var.start_date]
}
```

- `run "refuses_a_start_date_that_is_not_the_first_of_a_month" {`: Starts the test step `refuses a start date that is not the first of a month`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `start_date = "2026-11-15T00:00:00Z"`: Sets the input variable `start_date` (First day of the budget's first month, as 2026-11-01T00:00:00Z. Azure requires the first of a month) to the text `"2026-11-15T00:00:00Z"`.
- `expect_failures = [var.start_date]`: Expects the failure of [var.start_date].
- Closing lines: `}` end the blocks opened above.

**Lines 30 to 38**

```hcl
run "refuses_a_budget_that_alerts_nobody" {
  command = plan

  variables {
    contact_emails = []
  }

  expect_failures = [var.contact_emails]
}
```

- `run "refuses_a_budget_that_alerts_nobody" {`: Starts the test step `refuses a budget that alerts nobody`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `contact_emails = []`: Sets the input variable `contact_emails` (Addresses that receive the alerts) to `[]`.
- `expect_failures = [var.contact_emails]`: Expects the failure of [var.contact_emails].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/budget/variables.tf`

41 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
variable "name" {
  description = "Budget name."
  type        = string
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Budget name."`: `description` documents it: "Budget name."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 6 to 14**

```hcl
variable "subscription_id" {
  description = "Subscription GUID the budget watches."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}
```

- `variable "subscription_id" {`: Declares the input variable `subscription_id`.
- `description = "Subscription GUID the budget watches."`: `description` documents it: "Subscription GUID the budget watches."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))`: `condition` is the rule: `can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))` must be true.
- `error_message = "subscription_id must be a GUID."`: `error_message` is shown when the rule fails: "subscription_id must be a GUID."
- Closing lines: `}` end the blocks opened above.

**Lines 16 to 24**

```hcl
variable "amount" {
  description = "Monthly amount in the billing currency."
  type        = number

  validation {
    condition     = var.amount > 0
    error_message = "amount must be positive."
  }
}
```

- `variable "amount" {`: Declares the input variable `amount`.
- `description = "Monthly amount in the billing currency."`: `description` documents it: "Monthly amount in the billing currency."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = var.amount > 0`: `condition` is the rule: `var.amount > 0` must be true.
- `error_message = "amount must be positive."`: `error_message` is shown when the rule fails: "amount must be positive."
- Closing lines: `}` end the blocks opened above.

**Lines 26 to 34**

```hcl
variable "start_date" {
  description = "First day of the budget's first month, as 2026-11-01T00:00:00Z. Azure requires the first of a month."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.start_date))
    error_message = "start_date must be the first of a month at midnight UTC, for example 2026-11-01T00:00:00Z."
  }
}
```

- `variable "start_date" {`: Declares the input variable `start_date`.
- `description = "First day of the budget's first month, as 2026-11-01T00:00:00Z. Azure requires the first of a m`…: `description` documents it: "First day of the budget's first month, as 2026-11-01T00:00:00Z. Azure requires the first of a month."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.start_date))`: `condition` is the rule: `can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.start_date))` must be true.
- `error_message = "start_date must be the first of a month at midnight UTC, for example 2026-11-01T00:00:00Z."`: `error_message` is shown when the rule fails: "start_date must be the first of a month at midnight UTC, for example 2026-11-01T00:00:00Z."
- Closing lines: `}` end the blocks opened above.

**Lines 36 to 44**

```hcl
variable "contact_emails" {
  description = "Addresses that receive the alerts."
  type        = list(string)

  validation {
    condition     = length(var.contact_emails) > 0
    error_message = "At least one contact email is needed or the budget alerts nobody."
  }
}
```

- `variable "contact_emails" {`: Declares the input variable `contact_emails`.
- `description = "Addresses that receive the alerts."`: `description` documents it: "Addresses that receive the alerts."
- `type        = list(string)`: `type` limits what is accepted: `list(string)`: an ordered list of texts.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = length(var.contact_emails) > 0`: `condition` is the rule: `length(var.contact_emails) > 0` must be true.
- `error_message = "At least one contact email is needed or the budget alerts nobody."`: `error_message` is shown when the rule fails: "At least one contact email is needed or the budget alerts nobody."
- Closing lines: `}` end the blocks opened above.

**Lines 46 to 50**

```hcl
variable "thresholds_percent" {
  description = "Actual-spend percentages that send an alert."
  type        = list(number)
  default     = [80, 100]
}
```

- `variable "thresholds_percent" {`: Declares the input variable `thresholds_percent`.
- `description = "Actual-spend percentages that send an alert."`: `description` documents it: "Actual-spend percentages that send an alert."
- `type        = list(number)`: `type` limits what is accepted: the type `list(number)`
- `default     = [80, 100]`: `default` is used when the caller passes nothing: `[80, 100]`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/budget/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: The `terraform` block sets rules for Terraform itself: which version may run this code, which provider plug-ins it needs and where to find them, and where to keep state. Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: `required_providers` lists the provider plug-ins this code needs, each with `source` (where to download it from) and `version` (which releases are allowed). `~> 4.81` means "4.81 or newer, but below 5.0".
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/container_app/outputs.tf`

12 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "name" {
  description = "Container app name."
  value       = azurerm_container_app.this.name
}
```

- `output "name" {`: Declares the output `name`.
- `description = "Container app name."`: `description` documents it: "Container app name."
- `value       = azurerm_container_app.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_container_app.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "fqdn" {
  description = "Public host name of the app."
  value       = azurerm_container_app.this.ingress[0].fqdn
}
```

- `output "fqdn" {`: Declares the output `fqdn`.
- `description = "Public host name of the app."`: `description` documents it: "Public host name of the app."
- `value       = azurerm_container_app.this.ingress[0].fqdn`: `value` is what is exposed: the `ingress[0]` of the resource `azurerm_container_app.this`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "url" {
  description = "HTTPS address of the app."
  value       = "https://${azurerm_container_app.this.ingress[0].fqdn}"
}
```

- `output "url" {`: Declares the output `url`.
- `description = "HTTPS address of the app."`: `description` documents it: "HTTPS address of the app."
- `value       = "https://${azurerm_container_app.this.ingress[0].fqdn}"`: `value` is what is exposed: text built from the pieces the `ingress[0]` of the resource `azurerm_container_app.this`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/container_app/tests/container_app.tftest.hcl`

75 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 18**

```hcl
variables {
  name                       = "ca-secretless"
  environment_name           = "cae-secretless"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  image                      = "acrtest.azurecr.io/azure-secretless-app:0.1.0"
  app_identity_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app"
  pull_identity_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-pull"
  registry_server            = "acrtest.azurecr.io"
  env = {
    AZURE_CLIENT_ID = "00000000-0000-0000-0000-000000000000"
    VAULT_URL       = "https://kv-test.vault.azure.net/"
    STORAGE_URL     = "https://sttest.blob.core.windows.net/"
  }
}
```

- `variables {`: Starts a `variables` block.
- `name                       = "ca-secretless"`: Sets the input variable `name` (Container app name) to the text `"ca-secretless"`.
- `environment_name           = "cae-secretless"`: Sets the input variable `environment_name` (Container Apps environment name) to the text `"cae-secretless"`.
- `resource_group_name        = "rg-test"`: Sets the input variable `resource_group_name` (Resource group that holds both) to the text `"rg-test"`.
- `location                   = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- `log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/provi`…: Sets the input variable `log_analytics_workspace_id` (Workspace that receives the console logs) to the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"`.
- `image                      = "acrtest.azurecr.io/azure-secretless-app:0.1.0"`: Sets the input variable `image` (Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest) to the text `"acrtest.azurecr.io/azure-secretless-app:0.1.0"`.
- `app_identity_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/provi`…: Sets the input variable `app_identity_id` (Resource id of the identity the app runs as (it holds the two data roles)) to the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app"`.
- `pull_identity_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/provi`…: Sets the input variable `pull_identity_id` (Resource id of the identity that only pulls the image (AcrPull on the registry)) to the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-pull"`.
- `registry_server            = "acrtest.azurecr.io"`: Sets the input variable `registry_server` (Registry host, for example myregistry.azurecr.io) to the text `"acrtest.azurecr.io"`.
- `env = {`: Sets the input variable `env` (Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value) to a group of named values that follows.
- `AZURE_CLIENT_ID = "00000000-0000-0000-0000-000000000000"`: Entry `AZURE_CLIENT_ID`: the text `"00000000-0000-0000-0000-000000000000"`.
- `VAULT_URL       = "https://kv-test.vault.azure.net/"`: Entry `VAULT_URL`: the text `"https://kv-test.vault.azure.net/"`.
- `STORAGE_URL     = "https://sttest.blob.core.windows.net/"`: Entry `STORAGE_URL`: the text `"https://sttest.blob.core.windows.net/"`.
- Closing lines: `}` end the blocks opened above.

**Lines 20 to 37**

```hcl
run "carries_no_secret_blocks_and_only_the_given_plain_variables" {
  command = plan

  assert {
    condition     = length(azurerm_container_app.this.secret) == 0
    error_message = "the app must hold no secret"
  }

  assert {
    condition     = toset([for variable in one(one(azurerm_container_app.this.template).container).env : variable.name]) == toset(["AZURE_CLIENT_ID", "VAULT_URL", "STORAGE_URL"])
    error_message = "only the three addresses may be set"
  }

  assert {
    condition     = alltrue([for variable in one(one(azurerm_container_app.this.template).container).env : variable.secret_name == null])
    error_message = "no variable may reference a secret"
  }
}
```

- `run "carries_no_secret_blocks_and_only_the_given_plain_variables" {`: Starts the test step `carries no secret blocks and only the given plain variables`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = length(azurerm_container_app.this.secret) == 0`: `condition` is the rule: `length(azurerm_container_app.this.secret) == 0` must be true.
- `error_message = "the app must hold no secret"`: `error_message` is shown when the rule fails: "the app must hold no secret"
- `assert {`: Starts an `assert` block.
- `condition     = toset([for variable in one(one(azurerm_container_app.this.template).container).env : variable.`…: `condition` is the rule: `toset([for variable in one(one(azurerm_container_app.this.template).container).env : variable.name]) == toset(["AZURE_CLIENT_ID", "VAULT_URL", "STORAGE_URL"])` must be true.
- `error_message = "only the three addresses may be set"`: `error_message` is shown when the rule fails: "only the three addresses may be set"
- `assert {`: Starts an `assert` block.
- `condition     = alltrue([for variable in one(one(azurerm_container_app.this.template).container).env : variabl`…: `condition` is the rule: `alltrue([for variable in one(one(azurerm_container_app.this.template).container).env : variable.secret_name == null])` must be true.
- `error_message = "no variable may reference a secret"`: `error_message` is shown when the rule fails: "no variable may reference a secret"
- Closing lines: `}` end the blocks opened above.

**Lines 39 to 51**

```hcl
run "serves_only_https_and_runs_as_both_identities" {
  command = plan

  assert {
    condition     = one(azurerm_container_app.this.ingress).allow_insecure_connections == false
    error_message = "plain HTTP must be refused"
  }

  assert {
    condition     = length(one(azurerm_container_app.this.identity).identity_ids) == 2
    error_message = "the app and pull identities must both be attached"
  }
}
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

- `run "serves_only_https_and_runs_as_both_identities" {`: Starts the test step `serves only https and runs as both identities`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = one(azurerm_container_app.this.ingress).allow_insecure_connections == false`: `condition` is the rule: `one(azurerm_container_app.this.ingress).allow_insecure_connections == false` must be true.
- `error_message = "plain HTTP must be refused"`: `error_message` is shown when the rule fails: "plain HTTP must be refused"
- `assert {`: Starts an `assert` block.
- `condition     = length(one(azurerm_container_app.this.identity).identity_ids) == 2`: `condition` is the rule: `length(one(azurerm_container_app.this.identity).identity_ids) == 2` must be true.
- `error_message = "the app and pull identities must both be attached"`: `error_message` is shown when the rule fails: "the app and pull identities must both be attached"
- Closing lines: `}` end the blocks opened above.

**Lines 53 to 63**

```hcl
run "refuses_a_variable_named_like_a_credential" {
  command = plan

  variables {
    env = {
      STORAGE_CONNECTION_STRING = "x"
    }
  }

  expect_failures = [var.env]
}
```

- `run "refuses_a_variable_named_like_a_credential" {`: Starts the test step `refuses a variable named like a credential`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `env = {`: Sets the input variable `env` (Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value) to a group of named values that follows.
- `STORAGE_CONNECTION_STRING = "x"`: Entry `STORAGE_CONNECTION_STRING`: the text `"x"`.
- `expect_failures = [var.env]`: Expects the failure of [var.env].
- Closing lines: `}` end the blocks opened above.

**Lines 65 to 75**

```hcl
run "refuses_a_variable_valued_like_a_connection_string" {
  command = plan

  variables {
    env = {
      STORAGE = "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=abc"
    }
  }

  expect_failures = [var.env]
}
```

- `run "refuses_a_variable_valued_like_a_connection_string" {`: Starts the test step `refuses a variable valued like a connection string`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `env = {`: Sets the input variable `env` (Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value) to a group of named values that follows.
- `STORAGE = "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=abc"`: Entry `STORAGE`: the text `"DefaultEndpointsProtocol=https;AccountName=x;AccountKey=abc"`.
- `expect_failures = [var.env]`: Expects the failure of [var.env].
- Closing lines: `}` end the blocks opened above.

**Lines 77 to 85**

```hcl
run "refuses_the_latest_tag" {
  command = plan

  variables {
    image = "acrtest.azurecr.io/azure-secretless-app:latest"
  }

  expect_failures = [var.image]
}
```

- `run "refuses_the_latest_tag" {`: Starts the test step `refuses the latest tag`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `image = "acrtest.azurecr.io/azure-secretless-app:latest"`: Sets the input variable `image` (Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest) to the text `"acrtest.azurecr.io/azure-secretless-app:latest"`.
- `expect_failures = [var.image]`: Expects the failure of [var.image].
- Closing lines: `}` end the blocks opened above.

**Lines 87 to 95**

```hcl
run "refuses_an_image_without_a_tag" {
  command = plan

  variables {
    image = "acrtest.azurecr.io/azure-secretless-app"
  }

  expect_failures = [var.image]
}
```

- `run "refuses_an_image_without_a_tag" {`: Starts the test step `refuses an image without a tag`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `image = "acrtest.azurecr.io/azure-secretless-app"`: Sets the input variable `image` (Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest) to the text `"acrtest.azurecr.io/azure-secretless-app"`.
- `expect_failures = [var.image]`: Expects the failure of [var.image].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/container_app/variables.tf`

93 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
variable "name" {
  description = "Container app name."
  type        = string
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Container app name."`: `description` documents it: "Container app name."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
variable "environment_name" {
  description = "Container Apps environment name."
  type        = string
}
```

- `variable "environment_name" {`: Declares the input variable `environment_name`.
- `description = "Container Apps environment name."`: `description` documents it: "Container Apps environment name."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
variable "resource_group_name" {
  description = "Resource group that holds both."
  type        = string
}
```

- `variable "resource_group_name" {`: Declares the input variable `resource_group_name`.
- `description = "Resource group that holds both."`: `description` documents it: "Resource group that holds both."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 21 to 24**

```hcl
variable "log_analytics_workspace_id" {
  description = "Workspace that receives the console logs."
  type        = string
}
```

- `variable "log_analytics_workspace_id" {`: Declares the input variable `log_analytics_workspace_id`.
- `description = "Workspace that receives the console logs."`: `description` documents it: "Workspace that receives the console logs."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 26 to 34**

```hcl
variable "image" {
  description = "Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest."
  type        = string

  validation {
    condition     = !endswith(var.image, ":latest") && can(regex(":[^/]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry a version tag or a digest, and not be :latest."
  }
}
```

- `variable "image" {`: Declares the input variable `image`.
- `description = "Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag o`…: `description` documents it: "Image to run, for example myregistry.azurecr.io/azure-secretless-app:0.1.0. Use a version tag or a digest, never latest."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = !endswith(var.image, ":latest") && can(regex(":[^/]+$|@sha256:[0-9a-f]{64}$", var.image))`: `condition` is the rule: `!endswith(var.image, ":latest") && can(regex(":[^/]+$|@sha256:[0-9a-f]{64}$", var.image))` must be true.
- `error_message = "image must carry a version tag or a digest, and not be :latest."`: `error_message` is shown when the rule fails: "image must carry a version tag or a digest, and not be :latest."
- Closing lines: `}` end the blocks opened above.

**Lines 36 to 40**

```hcl
variable "container_port" {
  description = "Port the app listens on."
  type        = number
  default     = 8000
}
```

- `variable "container_port" {`: Declares the input variable `container_port`.
- `description = "Port the app listens on."`: `description` documents it: "Port the app listens on."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 8000`: `default` is used when the caller passes nothing: the number `8000`.
- Closing line: `}` ends the block opened above.

**Lines 42 to 45**

```hcl
variable "app_identity_id" {
  description = "Resource id of the identity the app runs as (it holds the two data roles)."
  type        = string
}
```

- `variable "app_identity_id" {`: Declares the input variable `app_identity_id`.
- `description = "Resource id of the identity the app runs as (it holds the two data roles)."`: `description` documents it: "Resource id of the identity the app runs as (it holds the two data roles)."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 47 to 50**

```hcl
variable "pull_identity_id" {
  description = "Resource id of the identity that only pulls the image (AcrPull on the registry)."
  type        = string
}
```

- `variable "pull_identity_id" {`: Declares the input variable `pull_identity_id`.
- `description = "Resource id of the identity that only pulls the image (AcrPull on the registry)."`: `description` documents it: "Resource id of the identity that only pulls the image (AcrPull on the registry)."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 52 to 55**

```hcl
variable "registry_server" {
  description = "Registry host, for example myregistry.azurecr.io."
  type        = string
}
```

- `variable "registry_server" {`: Declares the input variable `registry_server`.
- `description = "Registry host, for example myregistry.azurecr.io."`: `description` documents it: "Registry host, for example myregistry.azurecr.io."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 57 to 77**

```hcl
variable "env" {
  description = "Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value."
  type        = map(string)
  default     = {}

  validation {
    condition = !anytrue([
      for name in keys(var.env) :
      can(regex("(?i)(password|passwd|connection_?string|client_?secret|account_?key|sas_?token|api_?key)", name))
    ])
    error_message = "An environment variable name suggests a credential (password, connection string, client secret, account key, SAS token, API key). The app authenticates with its managed identity instead."
  }

  validation {
    condition = !anytrue([
      for value in values(var.env) :
      can(regex("(?i)(accountkey=|sharedaccesssignature=|[?&]sig=|password=|pwd=|-----BEGIN)", value))
    ])
    error_message = "An environment variable value looks like a connection string, SAS token or private key."
  }
}
```

**New idea.** An **API** (application programming interface) is a way for one program to ask another to do something. A **REST** API does it with ordinary web requests: the program sends an HTTP request to an address and reads the answer, usually JSON.

**New idea.** An **access token** is a short-lived piece of text, issued by an identity service after you prove who you are, that you attach to a request to show that you are allowed to make it. It expires after about an hour, so a stolen one is far less dangerous than a password.

- `variable "env" {`: Declares the input variable `env`.
- `description = "Plain environment variables: addresses and the client id of the identity. Credentials are refus`…: `description` documents it: "Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition = !anytrue([`: `condition` is the rule: `!anytrue([` must be true. `anytrue(list)` is true when at least one item is true.
- `for name in keys(var.env) :`: Part of a `for` expression: `for name in keys(var.env) :`. `keys(map)` lists a map's keys.
- `can(regex("(?i)(password|passwd|connection_?string|client_?secret|account_?key|sas_?token|api_?key)", name))`: Item: an expression (see the quote).
- `error_message = "An environment variable name suggests a credential (password, connection string, client secre`…: `error_message` is shown when the rule fails: "An environment variable name suggests a credential (password, connection string, client secret, account key, SAS token, API key). The app authenticates with its managed identity instead."
- `validation {`: Starts a rule the input value must satisfy.
- `condition = !anytrue([`: `condition` is the rule: `!anytrue([` must be true.
- `for value in values(var.env) :`: Part of a `for` expression: `for value in values(var.env) :`. `values(map)` lists a map's values.
- `can(regex("(?i)(accountkey=|sharedaccesssignature=|[?&]sig=|password=|pwd=|-----BEGIN)", value))`: Item: `can(regex("(?i)(accountkey=|sharedaccesssignature=|[?&]sig=|password=|pwd=|-----BEGIN)", value))`.
- `error_message = "An environment variable value looks like a connection string, SAS token or private key."`: `error_message` is shown when the rule fails: "An environment variable value looks like a connection string, SAS token or private key."
- Closing lines: `])`, `}` end the blocks opened above.

**Lines 79 to 88**

```hcl
variable "min_replicas" {
  description = "Minimum replicas. 0 scales to zero and costs nothing idle but adds a cold start."
  type        = number
  default     = 0

  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= var.max_replicas
    error_message = "min_replicas must be between 0 and max_replicas."
  }
}
```

- `variable "min_replicas" {`: Declares the input variable `min_replicas`.
- `description = "Minimum replicas. 0 scales to zero and costs nothing idle but adds a cold start."`: `description` documents it: "Minimum replicas. 0 scales to zero and costs nothing idle but adds a cold start."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 0`: `default` is used when the caller passes nothing: the number `0`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = var.min_replicas >= 0 && var.min_replicas <= var.max_replicas`: `condition` is the rule: `var.min_replicas >= 0 && var.min_replicas <= var.max_replicas` must be true.
- `error_message = "min_replicas must be between 0 and max_replicas."`: `error_message` is shown when the rule fails: "min_replicas must be between 0 and max_replicas."
- Closing lines: `}` end the blocks opened above.

**Lines 90 to 94**

```hcl
variable "max_replicas" {
  description = "Maximum replicas."
  type        = number
  default     = 2
}
```

- `variable "max_replicas" {`: Declares the input variable `max_replicas`.
- `description = "Maximum replicas."`: `description` documents it: "Maximum replicas."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 2`: `default` is used when the caller passes nothing: the number `2`.
- Closing line: `}` ends the block opened above.

**Lines 96 to 100**

```hcl
variable "cpu" {
  description = "vCPU per replica."
  type        = number
  default     = 0.25
}
```

- `variable "cpu" {`: Declares the input variable `cpu`.
- `description = "vCPU per replica."`: `description` documents it: "vCPU per replica."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 0.25`: `default` is used when the caller passes nothing: the number `0.25`.
- Closing line: `}` ends the block opened above.

**Lines 102 to 106**

```hcl
variable "memory" {
  description = "Memory per replica; Container Apps pairs 0.25 vCPU with 0.5Gi."
  type        = string
  default     = "0.5Gi"
}
```

- `variable "memory" {`: Declares the input variable `memory`.
- `description = "Memory per replica; Container Apps pairs 0.25 vCPU with 0.5Gi."`: `description` documents it: "Memory per replica; Container Apps pairs 0.25 vCPU with 0.5Gi."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "0.5Gi"`: `default` is used when the caller passes nothing: the text `"0.5Gi"`.
- Closing line: `}` ends the block opened above.

**Lines 108 to 112**

```hcl
variable "tags" {
  description = "Tags applied to both resources."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Tags applied to both resources."`: `description` documents it: "Tags applied to both resources."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/container_app/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/container_registry/outputs.tf`

12 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "id" {
  description = "Resource id; the scope for AcrPull."
  value       = azurerm_container_registry.this.id
}
```

- `output "id" {`: Declares the output `id`.
- `description = "Resource id; the scope for AcrPull."`: `description` documents it: "Resource id; the scope for AcrPull."
- `value       = azurerm_container_registry.this.id`: `value` is what is exposed: the `id` of the resource `azurerm_container_registry.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "name" {
  description = "Registry name; `az acr build --registry` takes it."
  value       = azurerm_container_registry.this.name
}
```

- `output "name" {`: Declares the output `name`.
- `description = "Registry name; `az acr build --registry` takes it."`: `description` documents it: "Registry name; `az acr build --registry` takes it."
- `value       = azurerm_container_registry.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_container_registry.this`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "login_server" {
  description = "Registry host, for example myregistry.azurecr.io."
  value       = azurerm_container_registry.this.login_server
}
```

- `output "login_server" {`: Declares the output `login_server`.
- `description = "Registry host, for example myregistry.azurecr.io."`: `description` documents it: "Registry host, for example myregistry.azurecr.io."
- `value       = azurerm_container_registry.this.login_server`: `value` is what is exposed: the `login_server` of the resource `azurerm_container_registry.this`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/container_registry/tests/container_registry.tftest.hcl`

20 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 7**

```hcl
variables {
  name                = "acrsecretless12345"
  resource_group_name = "rg-test"
  location            = "westeurope"
}
```

- `variables {`: Starts a `variables` block.
- `name                = "acrsecretless12345"`: Sets the input variable `name` (Registry name: 5 to 50 letters and digits, globally unique) to the text `"acrsecretless12345"`.
- `resource_group_name = "rg-test"`: Sets the input variable `resource_group_name` (Resource group that holds the registry) to the text `"rg-test"`.
- `location            = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- Closing line: `}` ends the block opened above.

**Lines 9 to 16**

```hcl
run "has_no_admin_user_and_no_anonymous_pull" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false && azurerm_container_registry.this.anonymous_pull_enabled == false
    error_message = "the registry must not offer a shared password or anonymous pulls"
  }
}
```

- `run "has_no_admin_user_and_no_anonymous_pull" {`: Starts the test step `has no admin user and no anonymous pull`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_container_registry.this.admin_enabled == false && azurerm_container_registry.this.anon`…: `condition` is the rule: `azurerm_container_registry.this.admin_enabled == false && azurerm_container_registry.this.anonymous_pull_enabled == false` must be true.
- `error_message = "the registry must not offer a shared password or anonymous pulls"`: `error_message` is shown when the rule fails: "the registry must not offer a shared password or anonymous pulls"
- Closing lines: `}` end the blocks opened above.

**Lines 18 to 26**

```hcl
run "refuses_a_name_with_a_hyphen" {
  command = plan

  variables {
    name = "acr-secretless"
  }

  expect_failures = [var.name]
}
```

- `run "refuses_a_name_with_a_hyphen" {`: Starts the test step `refuses a name with a hyphen`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `name = "acr-secretless"`: Sets the input variable `name` (Registry name: 5 to 50 letters and digits, globally unique) to the text `"acr-secretless"`.
- `expect_failures = [var.name]`: Expects the failure of [var.name].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/container_registry/variables.tf`

30 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 9**

```hcl
variable "name" {
  description = "Registry name: 5 to 50 letters and digits, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "A registry name has 5 to 50 letters and digits."
  }
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Registry name: 5 to 50 letters and digits, globally unique."`: `description` documents it: "Registry name: 5 to 50 letters and digits, globally unique."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))`: `condition` is the rule: `can(regex("^[a-zA-Z0-9]{5,50}$", var.name))` must be true.
- `error_message = "A registry name has 5 to 50 letters and digits."`: `error_message` is shown when the rule fails: "A registry name has 5 to 50 letters and digits."
- Closing lines: `}` end the blocks opened above.

**Lines 11 to 14**

```hcl
variable "resource_group_name" {
  description = "Resource group that holds the registry."
  type        = string
}
```

- `variable "resource_group_name" {`: Declares the input variable `resource_group_name`.
- `description = "Resource group that holds the registry."`: `description` documents it: "Resource group that holds the registry."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 21 to 30**

```hcl
variable "sku" {
  description = "Basic is the cheapest tier and enough to build and pull one image."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}
```

- `variable "sku" {`: Declares the input variable `sku`.
- `description = "Basic is the cheapest tier and enough to build and pull one image."`: `description` documents it: "Basic is the cheapest tier and enough to build and pull one image."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "Basic"`: `default` is used when the caller passes nothing: the text `"Basic"`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = contains(["Basic", "Standard", "Premium"], var.sku)`: `condition` is the rule: `contains(["Basic", "Standard", "Premium"], var.sku)` must be true. `contains(list, value)` is true when the list holds the value.
- `error_message = "sku must be Basic, Standard or Premium."`: `error_message` is shown when the rule fails: "sku must be Basic, Standard or Premium."
- Closing lines: `}` end the blocks opened above.

**Lines 32 to 36**

```hcl
variable "tags" {
  description = "Tags applied to the registry."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Tags applied to the registry."`: `description` documents it: "Tags applied to the registry."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/container_registry/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/key_vault/outputs.tf`

12 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "id" {
  description = "Resource id; the narrowest scope for the Key Vault Secrets User role."
  value       = azurerm_key_vault.this.id
}
```

- `output "id" {`: Declares the output `id`.
- `description = "Resource id; the narrowest scope for the Key Vault Secrets User role."`: `description` documents it: "Resource id; the narrowest scope for the Key Vault Secrets User role."
- `value       = azurerm_key_vault.this.id`: `value` is what is exposed: the `id` of the resource `azurerm_key_vault.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "name" {
  description = "Vault name."
  value       = azurerm_key_vault.this.name
}
```

- `output "name" {`: Declares the output `name`.
- `description = "Vault name."`: `description` documents it: "Vault name."
- `value       = azurerm_key_vault.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_key_vault.this`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "vault_uri" {
  description = "Vault address; the app's VAULT_URL. An address, not a secret."
  value       = azurerm_key_vault.this.vault_uri
}
```

- `output "vault_uri" {`: Declares the output `vault_uri`.
- `description = "Vault address; the app's VAULT_URL. An address, not a secret."`: `description` documents it: "Vault address; the app's VAULT_URL. An address, not a secret."
- `value       = azurerm_key_vault.this.vault_uri`: `value` is what is exposed: the `vault_uri` of the resource `azurerm_key_vault.this`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/key_vault/tests/key_vault.tftest.hcl`

50 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 9**

```hcl
variables {
  name                       = "kv-test-12345"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  tenant_id                  = "11111111-1111-1111-1111-111111111111"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
}
```

- `variables {`: Starts a `variables` block.
- `name                       = "kv-test-12345"`: Sets the input variable `name` (Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique) to the text `"kv-test-12345"`.
- `resource_group_name        = "rg-test"`: Sets the input variable `resource_group_name` (Resource group that holds the vault) to the text `"rg-test"`.
- `location                   = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- `tenant_id                  = "11111111-1111-1111-1111-111111111111"`: Sets the input variable `tenant_id` (Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)) to the text `"11111111-1111-1111-1111-111111111111"`.
- `log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/provi`…: Sets the input variable `log_analytics_workspace_id` (Workspace that receives the AuditEvent log) to the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 18**

```hcl
run "authorizes_with_azure_roles_not_access_policies" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "the vault must use Azure RBAC"
  }
}
```

- `run "authorizes_with_azure_roles_not_access_policies" {`: Starts the test step `authorizes with azure roles not access policies`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_key_vault.this.rbac_authorization_enabled`: `condition` is the rule: `azurerm_key_vault.this.rbac_authorization_enabled` must be true.
- `error_message = "the vault must use Azure RBAC"`: `error_message` is shown when the rule fails: "the vault must use Azure RBAC"
- Closing lines: `}` end the blocks opened above.

**Lines 20 to 27**

```hcl
run "keeps_the_shortest_soft_delete_and_no_purge_protection_for_practice" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 7 && !azurerm_key_vault.this.purge_protection_enabled
    error_message = "practice defaults are 7 days and no purge protection"
  }
}
```

- `run "keeps_the_shortest_soft_delete_and_no_purge_protection_for_practice" {`: Starts the test step `keeps the shortest soft delete and no purge protection for practice`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_key_vault.this.soft_delete_retention_days == 7 && !azurerm_key_vault.this.purge_protec`…: `condition` is the rule: `azurerm_key_vault.this.soft_delete_retention_days == 7 && !azurerm_key_vault.this.purge_protection_enabled` must be true.
- `error_message = "practice defaults are 7 days and no purge protection"`: `error_message` is shown when the rule fails: "practice defaults are 7 days and no purge protection"
- Closing lines: `}` end the blocks opened above.

**Lines 29 to 36**

```hcl
run "sends_the_audit_event_log_to_the_workspace" {
  command = plan

  assert {
    condition     = one(azurerm_monitor_diagnostic_setting.audit.enabled_log).category == "AuditEvent"
    error_message = "the AuditEvent category must be enabled"
  }
}
```

**New idea.** **Log Analytics** is Azure's store for logs and metrics, queried with the Kusto Query Language (KQL). A *diagnostic setting* tells a resource to send its logs there, so that, for example, every refused request to a vault can be found afterwards.

- `run "sends_the_audit_event_log_to_the_workspace" {`: Starts the test step `sends the audit event log to the workspace`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = one(azurerm_monitor_diagnostic_setting.audit.enabled_log).category == "AuditEvent"`: `condition` is the rule: `one(azurerm_monitor_diagnostic_setting.audit.enabled_log).category == "AuditEvent"` must be true.
- `error_message = "the AuditEvent category must be enabled"`: `error_message` is shown when the rule fails: "the AuditEvent category must be enabled"
- Closing lines: `}` end the blocks opened above.

**Lines 38 to 46**

```hcl
run "refuses_a_name_that_is_too_short" {
  command = plan

  variables {
    name = "kv"
  }

  expect_failures = [var.name]
}
```

- `run "refuses_a_name_that_is_too_short" {`: Starts the test step `refuses a name that is too short`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `name = "kv"`: Sets the input variable `name` (Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique) to the text `"kv"`.
- `expect_failures = [var.name]`: Expects the failure of [var.name].
- Closing lines: `}` end the blocks opened above.

**Lines 48 to 56**

```hcl
run "refuses_a_retention_outside_the_allowed_range" {
  command = plan

  variables {
    soft_delete_retention_days = 3
  }

  expect_failures = [var.soft_delete_retention_days]
}
```

- `run "refuses_a_retention_outside_the_allowed_range" {`: Starts the test step `refuses a retention outside the allowed range`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `soft_delete_retention_days = 3`: Sets the input variable `soft_delete_retention_days` (Days a deleted vault keeps its name reserved. The minimum, 7, keeps practice runs short) to the number `3`.
- `expect_failures = [var.soft_delete_retention_days]`: Expects the failure of [var.soft_delete_retention_days].
- Closing lines: `}` end the blocks opened above.

**Lines 58 to 66**

```hcl
run "refuses_a_tenant_id_that_is_not_a_guid" {
  command = plan

  variables {
    tenant_id = "my-tenant"
  }

  expect_failures = [var.tenant_id]
}
```

- `run "refuses_a_tenant_id_that_is_not_a_guid" {`: Starts the test step `refuses a tenant id that is not a guid`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `tenant_id = "my-tenant"`: Sets the input variable `tenant_id` (Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)) to the text `"my-tenant"`.
- `expect_failures = [var.tenant_id]`: Expects the failure of [var.tenant_id].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/key_vault/variables.tf`

52 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 9**

```hcl
variable "name" {
  description = "Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "A vault name has 3 to 24 characters, starts with a letter, ends with a letter or digit and holds only letters, digits and hyphens."
  }
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique."`: `description` documents it: "Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))`: `condition` is the rule: `can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))` must be true.
- `error_message = "A vault name has 3 to 24 characters, starts with a letter, ends with a letter or digit and ho`…: `error_message` is shown when the rule fails: "A vault name has 3 to 24 characters, starts with a letter, ends with a letter or digit and holds only letters, digits and hyphens."
- Closing lines: `}` end the blocks opened above.

**Lines 11 to 14**

```hcl
variable "resource_group_name" {
  description = "Resource group that holds the vault."
  type        = string
}
```

- `variable "resource_group_name" {`: Declares the input variable `resource_group_name`.
- `description = "Resource group that holds the vault."`: `description` documents it: "Resource group that holds the vault."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 21 to 29**

```hcl
variable "tenant_id" {
  description = "Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}
```

- `variable "tenant_id" {`: Declares the input variable `tenant_id`.
- `description = "Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)."`: `description` documents it: "Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))`: `condition` is the rule: `can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))` must be true.
- `error_message = "tenant_id must be a GUID."`: `error_message` is shown when the rule fails: "tenant_id must be a GUID."
- Closing lines: `}` end the blocks opened above.

**Lines 31 to 34**

```hcl
variable "log_analytics_workspace_id" {
  description = "Workspace that receives the AuditEvent log."
  type        = string
}
```

- `variable "log_analytics_workspace_id" {`: Declares the input variable `log_analytics_workspace_id`.
- `description = "Workspace that receives the AuditEvent log."`: `description` documents it: "Workspace that receives the AuditEvent log."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 36 to 45**

```hcl
variable "soft_delete_retention_days" {
  description = "Days a deleted vault keeps its name reserved. The minimum, 7, keeps practice runs short."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}
```

- `variable "soft_delete_retention_days" {`: Declares the input variable `soft_delete_retention_days`.
- `description = "Days a deleted vault keeps its name reserved. The minimum, 7, keeps practice runs short."`: `description` documents it: "Days a deleted vault keeps its name reserved. The minimum, 7, keeps practice runs short."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 7`: `default` is used when the caller passes nothing: the number `7`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90`: `condition` is the rule: `var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90` must be true.
- `error_message = "soft_delete_retention_days must be between 7 and 90."`: `error_message` is shown when the rule fails: "soft_delete_retention_days must be between 7 and 90."
- Closing lines: `}` end the blocks opened above.

**Lines 47 to 51**

```hcl
variable "purge_protection_enabled" {
  description = "When true, a deleted vault cannot be purged until the retention ends. Turn it on in production; leave it off for practice so the name can be reused."
  type        = bool
  default     = false
}
```

- `variable "purge_protection_enabled" {`: Declares the input variable `purge_protection_enabled`.
- `description = "When true, a deleted vault cannot be purged until the retention ends. Turn it on in production;`…: `description` documents it: "When true, a deleted vault cannot be purged until the retention ends. Turn it on in production; leave it off for practice so the name can be reused."
- `type        = bool`: `type` limits what is accepted: `bool`: `true` or `false`.
- `default     = false`: `default` is used when the caller passes nothing: `false`.
- Closing line: `}` ends the block opened above.

**Lines 53 to 57**

```hcl
variable "public_network_access_enabled" {
  description = "Public endpoint on or off. This project keeps it on; the private platform slice project turns it off behind a private endpoint."
  type        = bool
  default     = true
}
```

**New idea.** A **private endpoint** gives an Azure service (a vault, a storage account) a private IP address inside your subnet, so traffic stays on your private network. For the service's normal name to lead to that private address, a *private DNS zone* (such as `privatelink.vaultcore.azure.net`) must be linked to the network.

- `variable "public_network_access_enabled" {`: Declares the input variable `public_network_access_enabled`.
- `description = "Public endpoint on or off. This project keeps it on; the private platform slice project turns i`…: `description` documents it: "Public endpoint on or off. This project keeps it on; the private platform slice project turns it off behind a private endpoint."
- `type        = bool`: `type` limits what is accepted: `bool`: `true` or `false`.
- `default     = true`: `default` is used when the caller passes nothing: `true`.
- Closing line: `}` ends the block opened above.

**Lines 59 to 63**

```hcl
variable "tags" {
  description = "Tags applied to the vault."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Tags applied to the vault."`: `description` documents it: "Tags applied to the vault."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/key_vault/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/log_analytics/outputs.tf`

12 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "id" {
  description = "Resource id of the workspace; diagnostic settings and the container app environment take this."
  value       = azurerm_log_analytics_workspace.this.id
}
```

- `output "id" {`: Declares the output `id`.
- `description = "Resource id of the workspace; diagnostic settings and the container app environment take this."`: `description` documents it: "Resource id of the workspace; diagnostic settings and the container app environment take this."
- `value       = azurerm_log_analytics_workspace.this.id`: `value` is what is exposed: the `id` of the resource `azurerm_log_analytics_workspace.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "name" {
  description = "Workspace name."
  value       = azurerm_log_analytics_workspace.this.name
}
```

- `output "name" {`: Declares the output `name`.
- `description = "Workspace name."`: `description` documents it: "Workspace name."
- `value       = azurerm_log_analytics_workspace.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_log_analytics_workspace.this`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "workspace_id" {
  description = "The workspace's customer id (a GUID, not a secret); `az monitor log-analytics query --workspace` takes it."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}
```

- `output "workspace_id" {`: Declares the output `workspace_id`.
- `description = "The workspace's customer id (a GUID, not a secret); `az monitor log-analytics query --workspace`…: `description` documents it: "The workspace's customer id (a GUID, not a secret); `az monitor log-analytics query --workspace` takes it."
- `value       = azurerm_log_analytics_workspace.this.workspace_id`: `value` is what is exposed: the `workspace_id` of the resource `azurerm_log_analytics_workspace.this`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/log_analytics/tests/log_analytics.tftest.hcl`

20 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 7**

```hcl
variables {
  name                = "law-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
}
```

- `variables {`: Starts a `variables` block.
- `name                = "law-test"`: Sets the input variable `name` (Workspace name, for example law-secretless) to the text `"law-test"`.
- `resource_group_name = "rg-test"`: Sets the input variable `resource_group_name` (Resource group that holds the workspace) to the text `"rg-test"`.
- `location            = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- Closing line: `}` ends the block opened above.

**Lines 9 to 16**

```hcl
run "keeps_logs_for_the_free_retention_by_default" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "the default retention must be the free 30 days"
  }
}
```

- `run "keeps_logs_for_the_free_retention_by_default" {`: Starts the test step `keeps logs for the free retention by default`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30`: `condition` is the rule: `azurerm_log_analytics_workspace.this.retention_in_days == 30` must be true.
- `error_message = "the default retention must be the free 30 days"`: `error_message` is shown when the rule fails: "the default retention must be the free 30 days"
- Closing lines: `}` end the blocks opened above.

**Lines 18 to 26**

```hcl
run "refuses_retention_below_the_tier_minimum" {
  command = plan

  variables {
    retention_in_days = 7
  }

  expect_failures = [var.retention_in_days]
}
```

- `run "refuses_retention_below_the_tier_minimum" {`: Starts the test step `refuses retention below the tier minimum`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `retention_in_days = 7`: Sets the input variable `retention_in_days` (How long logs stay queryable. 30 days is the free retention of the PerGB2018 tier) to the number `7`.
- `expect_failures = [var.retention_in_days]`: Expects the failure of [var.retention_in_days].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/log_analytics/variables.tf`

26 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
variable "name" {
  description = "Workspace name, for example law-secretless."
  type        = string
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Workspace name, for example law-secretless."`: `description` documents it: "Workspace name, for example law-secretless."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
variable "resource_group_name" {
  description = "Resource group that holds the workspace."
  type        = string
}
```

- `variable "resource_group_name" {`: Declares the input variable `resource_group_name`.
- `description = "Resource group that holds the workspace."`: `description` documents it: "Resource group that holds the workspace."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 16 to 25**

```hcl
variable "retention_in_days" {
  description = "How long logs stay queryable. 30 days is the free retention of the PerGB2018 tier."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}
```

- `variable "retention_in_days" {`: Declares the input variable `retention_in_days`.
- `description = "How long logs stay queryable. 30 days is the free retention of the PerGB2018 tier."`: `description` documents it: "How long logs stay queryable. 30 days is the free retention of the PerGB2018 tier."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 30`: `default` is used when the caller passes nothing: the number `30`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730`: `condition` is the rule: `var.retention_in_days >= 30 && var.retention_in_days <= 730` must be true.
- `error_message = "retention_in_days must be between 30 and 730."`: `error_message` is shown when the rule fails: "retention_in_days must be between 30 and 730."
- Closing lines: `}` end the blocks opened above.

**Lines 27 to 31**

```hcl
variable "tags" {
  description = "Tags applied to the workspace."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Tags applied to the workspace."`: `description` documents it: "Tags applied to the workspace."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/log_analytics/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/role_assignments/outputs.tf`

10 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
output "assignments" {
  description = "What was assigned, by key: principal, role and scope."
  value = {
    for key, assignment in azurerm_role_assignment.this : key => {
      principal_id = assignment.principal_id
      role         = assignment.role_definition_name
      scope        = assignment.scope
    }
  }
}
```

- `output "assignments" {`: Declares the output `assignments`.
- `description = "What was assigned, by key: principal, role and scope."`: `description` documents it: "What was assigned, by key: principal, role and scope."
- `value = {`: `value` is what is exposed: a group of named values that follows.
- `for key, assignment in azurerm_role_assignment.this : key => {`: Part of a `for` expression: `for key, assignment in azurerm_role_assignment.this : key => {`.
- `principal_id = assignment.principal_id`: Entry `principal_id`: `assignment.principal_id`.
- `role         = assignment.role_definition_name`: Entry `role`: `assignment.role_definition_name`.
- `scope        = assignment.scope`: Entry `scope`: `assignment.scope`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/role_assignments/tests/role_assignments.tftest.hcl`

74 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 11**

```hcl
variables {
  assignments = {
    blob = {
      principal_id = "22222222-2222-2222-2222-222222222222"
      role         = "Storage Blob Data Contributor"
      scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stsecretless12345/blobServices/default/containers/uploads"
    }
  }
}
```

- `variables {`: Starts a `variables` block.
- `assignments = {`: Sets the input variable `assignments` to a group of named values that follows.
- `blob = {`: Entry `blob`: a group of named values that follows.
- `principal_id = "22222222-2222-2222-2222-222222222222"`: Entry `principal_id`: the text `"22222222-2222-2222-2222-222222222222"`.
- `role         = "Storage Blob Data Contributor"`: Entry `role`: the text `"Storage Blob Data Contributor"`.
- `scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft`…: Entry `scope`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stsecretless12345/blobServices/default/containers/uploads"`.
- Closing lines: `}` end the blocks opened above.

**Lines 13 to 25**

```hcl
run "accepts_a_container_scope_and_assigns_without_the_directory_lookup" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.this["blob"].skip_service_principal_aad_check
    error_message = "a new service principal must be assigned by its type"
  }

  assert {
    condition     = azurerm_role_assignment.this["blob"].role_definition_name == "Storage Blob Data Contributor"
    error_message = "the role must be the one requested"
  }
}
```

- `run "accepts_a_container_scope_and_assigns_without_the_directory_lookup" {`: Starts the test step `accepts a container scope and assigns without the directory lookup`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_role_assignment.this["blob"].skip_service_principal_aad_check`: `condition` is the rule: `azurerm_role_assignment.this["blob"].skip_service_principal_aad_check` must be true.
- `error_message = "a new service principal must be assigned by its type"`: `error_message` is shown when the rule fails: "a new service principal must be assigned by its type"
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_role_assignment.this["blob"].role_definition_name == "Storage Blob Data Contributor"`: `condition` is the rule: `azurerm_role_assignment.this["blob"].role_definition_name == "Storage Blob Data Contributor"` must be true.
- `error_message = "the role must be the one requested"`: `error_message` is shown when the rule fails: "the role must be the one requested"
- Closing lines: `}` end the blocks opened above.

**Lines 27 to 41**

```hcl
run "refuses_a_resource_group_scope" {
  command = plan

  variables {
    assignments = {
      blob = {
        principal_id = "22222222-2222-2222-2222-222222222222"
        role         = "Storage Blob Data Contributor"
        scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
      }
    }
  }

  expect_failures = [var.assignments]
}
```

- `run "refuses_a_resource_group_scope" {`: Starts the test step `refuses a resource group scope`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `assignments = {`: Sets the input variable `assignments` to a group of named values that follows.
- `blob = {`: Entry `blob`: a group of named values that follows.
- `principal_id = "22222222-2222-2222-2222-222222222222"`: Entry `principal_id`: the text `"22222222-2222-2222-2222-222222222222"`.
- `role         = "Storage Blob Data Contributor"`: Entry `role`: the text `"Storage Blob Data Contributor"`.
- `scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"`: Entry `scope`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"`.
- `expect_failures = [var.assignments]`: Expects the failure of [var.assignments].
- Closing lines: `}` end the blocks opened above.

**Lines 43 to 57**

```hcl
run "refuses_a_subscription_scope" {
  command = plan

  variables {
    assignments = {
      blob = {
        principal_id = "22222222-2222-2222-2222-222222222222"
        role         = "Reader"
        scope        = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
    }
  }

  expect_failures = [var.assignments]
}
```

- `run "refuses_a_subscription_scope" {`: Starts the test step `refuses a subscription scope`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `assignments = {`: Sets the input variable `assignments` to a group of named values that follows.
- `blob = {`: Entry `blob`: a group of named values that follows.
- `principal_id = "22222222-2222-2222-2222-222222222222"`: Entry `principal_id`: the text `"22222222-2222-2222-2222-222222222222"`.
- `role         = "Reader"`: Entry `role`: the text `"Reader"`.
- `scope        = "/subscriptions/00000000-0000-0000-0000-000000000000"`: Entry `scope`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000"`.
- `expect_failures = [var.assignments]`: Expects the failure of [var.assignments].
- Closing lines: `}` end the blocks opened above.

**Lines 59 to 73**

```hcl
run "refuses_a_management_role" {
  command = plan

  variables {
    assignments = {
      owner = {
        principal_id = "22222222-2222-2222-2222-222222222222"
        role         = "Contributor"
        scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
      }
    }
  }

  expect_failures = [var.assignments]
}
```

- `run "refuses_a_management_role" {`: Starts the test step `refuses a management role`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `assignments = {`: Sets the input variable `assignments` to a group of named values that follows.
- `owner = {`: Entry `owner`: a group of named values that follows.
- `principal_id = "22222222-2222-2222-2222-222222222222"`: Entry `principal_id`: the text `"22222222-2222-2222-2222-222222222222"`.
- `role         = "Contributor"`: Entry `role`: the text `"Contributor"`.
- `scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft`…: Entry `scope`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"`.
- `expect_failures = [var.assignments]`: Expects the failure of [var.assignments].
- Closing lines: `}` end the blocks opened above.

**Lines 75 to 90**

```hcl
run "refuses_an_unknown_principal_type" {
  command = plan

  variables {
    assignments = {
      blob = {
        principal_id   = "22222222-2222-2222-2222-222222222222"
        role           = "Reader"
        scope          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        principal_type = "Robot"
      }
    }
  }

  expect_failures = [var.assignments]
}
```

- `run "refuses_an_unknown_principal_type" {`: Starts the test step `refuses an unknown principal type`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `assignments = {`: Sets the input variable `assignments` to a group of named values that follows.
- `blob = {`: Entry `blob`: a group of named values that follows.
- `principal_id   = "22222222-2222-2222-2222-222222222222"`: Entry `principal_id`: the text `"22222222-2222-2222-2222-222222222222"`.
- `role           = "Reader"`: Entry `role`: the text `"Reader"`.
- `scope          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microso`…: Entry `scope`: the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"`.
- `principal_type = "Robot"`: Entry `principal_type`: the text `"Robot"`.
- `expect_failures = [var.assignments]`: Expects the failure of [var.assignments].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/role_assignments/variables.tf`

31 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 28**

```hcl
variable "assignments" {
  description = <<-EOT
    Role assignments by a stable key. Each entry names the principal's object id (not its client id), the built-in
    role and the scope. The scope must be a single resource or sub-resource: a subscription or a resource group is
    refused, which is the "narrowest scope that works" rule written as code.
  EOT
  type = map(object({
    principal_id   = string
    role           = string
    scope          = string
    principal_type = optional(string, "ServicePrincipal")
  }))

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

- `variable "assignments" {`: Declares the input variable `assignments`.
- `description = <<-EOT`: `description` documents it: <<-EOT `<<-EOT ... EOT` (a **heredoc**) writes a multi-line text; `<<-` lets the lines be indented.
- `Role assignments by a stable key. Each entry names the principal's object id (not its client id), the built-in`: continues the structure above.
- `role and the scope. The scope must be a single resource or sub-resource: a subscription or a resource group is`: continues the structure above.
- `refused, which is the "narrowest scope that works" rule written as code.`: continues the structure above.
- `EOT`: continues the structure above.
- `type = map(object({`: `type` limits what is accepted: `map(object({...}))`: a set of named records, each with the fields listed.
- `principal_id   = string`: Entry `principal_id`: `string`.
- `role           = string`: Entry `role`: `string`.
- `scope          = string`: Entry `scope`: `string`.
- `principal_type = optional(string, "ServicePrincipal")`: Entry `principal_type`: `optional(string, "ServicePrincipal")`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition = alltrue([`: `condition` is the rule: `alltrue([` must be true.
- `for assignment in var.assignments :`: Part of a `for` expression: `for assignment in var.assignments :`.
- `can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/.+/.+", assignment.scope))`: Item: `can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/.+/.+", assignment.scope))`.
- `error_message = "Every scope must be a resource (/subscriptions/.../resourceGroups/.../providers/...), never a`…: `error_message` is shown when the rule fails: "Every scope must be a resource (/subscriptions/.../resourceGroups/.../providers/...), never a subscription or a resource group."
- `validation {`: Starts a rule the input value must satisfy.
- `condition = alltrue([`: `condition` is the rule: `alltrue([` must be true.
- `for assignment in var.assignments :`: Part of a `for` expression: `for assignment in var.assignments :`.
- `contains(["ServicePrincipal", "User", "Group"], assignment.principal_type)`: Item: `contains(["ServicePrincipal", "User", "Group"], assignment.principal_type)`.
- `error_message = "principal_type must be ServicePrincipal, User or Group."`: `error_message` is shown when the rule fails: "principal_type must be ServicePrincipal, User or Group."
- Closing lines: `}))`, `])`, `}` end the blocks opened above.

**Lines 30 to 34**

```hcl
  validation {
    condition     = !anytrue([for assignment in var.assignments : contains(["Owner", "Contributor", "User Access Administrator"], assignment.role)])
    error_message = "Owner, Contributor and User Access Administrator are management roles; this project assigns data roles only."
  }
}
```

- `validation {`: Starts a rule the input value must satisfy.
- `condition     = !anytrue([for assignment in var.assignments : contains(["Owner", "Contributor", "User Access A`…: `condition` is the rule: `!anytrue([for assignment in var.assignments : contains(["Owner", "Contributor", "User Access Administrator"], assignment.role)])` must be true.
- `error_message = "Owner, Contributor and User Access Administrator are management roles; this project assigns d`…: `error_message` is shown when the rule fails: "Owner, Contributor and User Access Administrator are management roles; this project assigns data roles only."
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/role_assignments/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/storage_uploads/outputs.tf`

20 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "id" {
  description = "Account resource id."
  value       = azurerm_storage_account.this.id
}
```

- `output "id" {`: Declares the output `id`.
- `description = "Account resource id."`: `description` documents it: "Account resource id."
- `value       = azurerm_storage_account.this.id`: `value` is what is exposed: the `id` of the resource `azurerm_storage_account.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "name" {
  description = "Account name."
  value       = azurerm_storage_account.this.name
}
```

- `output "name" {`: Declares the output `name`.
- `description = "Account name."`: `description` documents it: "Account name."
- `value       = azurerm_storage_account.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_storage_account.this`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "blob_endpoint" {
  description = "Blob address; the app's STORAGE_URL. An address, not a secret."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}
```

- `output "blob_endpoint" {`: Declares the output `blob_endpoint`.
- `description = "Blob address; the app's STORAGE_URL. An address, not a secret."`: `description` documents it: "Blob address; the app's STORAGE_URL. An address, not a secret."
- `value       = azurerm_storage_account.this.primary_blob_endpoint`: `value` is what is exposed: the `primary_blob_endpoint` of the resource `azurerm_storage_account.this`.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
output "container_name" {
  description = "Name of the uploads container."
  value       = azurerm_storage_container.uploads.name
}
```

- `output "container_name" {`: Declares the output `container_name`.
- `description = "Name of the uploads container."`: `description` documents it: "Name of the uploads container."
- `value       = azurerm_storage_container.uploads.name`: `value` is what is exposed: the `name` of the resource `azurerm_storage_container.uploads`.
- Closing line: `}` ends the block opened above.

**Lines 21 to 24**

```hcl
output "container_resource_manager_id" {
  description = "Resource id of the container (.../blobServices/default/containers/uploads): the narrowest scope for the blob role."
  value       = azurerm_storage_container.uploads.id
}
```

- `output "container_resource_manager_id" {`: Declares the output `container_resource_manager_id`.
- `description = "Resource id of the container (.../blobServices/default/containers/uploads): the narrowest scope`…: `description` documents it: "Resource id of the container (.../blobServices/default/containers/uploads): the narrowest scope for the blob role."
- `value       = azurerm_storage_container.uploads.id`: `value` is what is exposed: the `id` of the resource `azurerm_storage_container.uploads`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/storage_uploads/tests/storage_uploads.tftest.hcl`

50 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 8**

```hcl
variables {
  name                       = "stsecretless12345"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
}
```

- `variables {`: Starts a `variables` block.
- `name                       = "stsecretless12345"`: Sets the input variable `name` (Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique) to the text `"stsecretless12345"`.
- `resource_group_name        = "rg-test"`: Sets the input variable `resource_group_name` (Resource group that holds the account) to the text `"rg-test"`.
- `location                   = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- `log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/provi`…: Sets the input variable `log_analytics_workspace_id` (Workspace that receives the blob logs) to the text `"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"`.
- Closing line: `}` ends the block opened above.

**Lines 10 to 22**

```hcl
run "turns_account_keys_off_so_the_identity_is_the_only_way_in" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "shared key access must be disabled"
  }

  assert {
    condition     = azurerm_storage_account.this.default_to_oauth_authentication
    error_message = "the portal and tools must default to Entra authentication"
  }
}
```

- `run "turns_account_keys_off_so_the_identity_is_the_only_way_in" {`: Starts the test step `turns account keys off so the identity is the only way in`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_storage_account.this.shared_access_key_enabled == false`: `condition` is the rule: `azurerm_storage_account.this.shared_access_key_enabled == false` must be true.
- `error_message = "shared key access must be disabled"`: `error_message` is shown when the rule fails: "shared key access must be disabled"
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_storage_account.this.default_to_oauth_authentication`: `condition` is the rule: `azurerm_storage_account.this.default_to_oauth_authentication` must be true.
- `error_message = "the portal and tools must default to Entra authentication"`: `error_message` is shown when the rule fails: "the portal and tools must default to Entra authentication"
- Closing lines: `}` end the blocks opened above.

**Lines 24 to 31**

```hcl
run "blocks_public_blobs_and_old_tls" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false && azurerm_storage_account.this.min_tls_version == "TLS1_2" && azurerm_storage_account.this.https_traffic_only_enabled
    error_message = "no public blobs, TLS 1.2 or newer, HTTPS only"
  }
}
```

- `run "blocks_public_blobs_and_old_tls" {`: Starts the test step `blocks public blobs and old tls`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false && azurerm_storage_accou`…: `condition` is the rule: `azurerm_storage_account.this.allow_nested_items_to_be_public == false && azurerm_storage_account.this.min_tls_version == "TLS1_2" && azurerm_storage_account.this.https_traffic_only_enabled` must be true.
- `error_message = "no public blobs, TLS 1.2 or newer, HTTPS only"`: `error_message` is shown when the rule fails: "no public blobs, TLS 1.2 or newer, HTTPS only"
- Closing lines: `}` end the blocks opened above.

**Lines 33 to 45**

```hcl
run "keeps_the_container_private_and_logs_the_blob_service" {
  command = plan

  assert {
    condition     = azurerm_storage_container.uploads.container_access_type == "private"
    error_message = "the uploads container must be private"
  }

  assert {
    condition     = toset([for log in azurerm_monitor_diagnostic_setting.blob.enabled_log : log.category]) == toset(["StorageRead", "StorageWrite", "StorageDelete"])
    error_message = "read, write and delete logs must go to the workspace"
  }
}
```

- `run "keeps_the_container_private_and_logs_the_blob_service" {`: Starts the test step `keeps the container private and logs the blob service`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_storage_container.uploads.container_access_type == "private"`: `condition` is the rule: `azurerm_storage_container.uploads.container_access_type == "private"` must be true.
- `error_message = "the uploads container must be private"`: `error_message` is shown when the rule fails: "the uploads container must be private"
- `assert {`: Starts an `assert` block.
- `condition     = toset([for log in azurerm_monitor_diagnostic_setting.blob.enabled_log : log.category]) == tose`…: `condition` is the rule: `toset([for log in azurerm_monitor_diagnostic_setting.blob.enabled_log : log.category]) == toset(["StorageRead", "StorageWrite", "StorageDelete"])` must be true.
- `error_message = "read, write and delete logs must go to the workspace"`: `error_message` is shown when the rule fails: "read, write and delete logs must go to the workspace"
- Closing lines: `}` end the blocks opened above.

**Lines 47 to 55**

```hcl
run "refuses_a_name_with_a_hyphen" {
  command = plan

  variables {
    name = "st-secretless"
  }

  expect_failures = [var.name]
}
```

- `run "refuses_a_name_with_a_hyphen" {`: Starts the test step `refuses a name with a hyphen`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `name = "st-secretless"`: Sets the input variable `name` (Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique) to the text `"st-secretless"`.
- `expect_failures = [var.name]`: Expects the failure of [var.name].
- Closing lines: `}` end the blocks opened above.

**Lines 57 to 65**

```hcl
run "refuses_an_unknown_replication_type" {
  command = plan

  variables {
    replication_type = "RAGRS-PLUS"
  }

  expect_failures = [var.replication_type]
}
```

- `run "refuses_an_unknown_replication_type" {`: Starts the test step `refuses an unknown replication type`.
- `command = plan`: `command = plan`.
- `variables {`: Starts a `variables` block.
- `replication_type = "RAGRS-PLUS"`: Sets the input variable `replication_type` (LRS keeps three copies in one datacenter: the cheapest, enough for practice) to the text `"RAGRS-PLUS"`.
- `expect_failures = [var.replication_type]`: Expects the failure of [var.replication_type].
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/storage_uploads/variables.tf`

52 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 9**

```hcl
variable "name" {
  description = "Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "A storage account name has 3 to 24 lowercase letters and digits and no hyphens."
  }
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique."`: `description` documents it: "Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[a-z0-9]{3,24}$", var.name))`: `condition` is the rule: `can(regex("^[a-z0-9]{3,24}$", var.name))` must be true.
- `error_message = "A storage account name has 3 to 24 lowercase letters and digits and no hyphens."`: `error_message` is shown when the rule fails: "A storage account name has 3 to 24 lowercase letters and digits and no hyphens."
- Closing lines: `}` end the blocks opened above.

**Lines 11 to 14**

```hcl
variable "resource_group_name" {
  description = "Resource group that holds the account."
  type        = string
}
```

- `variable "resource_group_name" {`: Declares the input variable `resource_group_name`.
- `description = "Resource group that holds the account."`: `description` documents it: "Resource group that holds the account."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 21 to 30**

```hcl
variable "container_name" {
  description = "The one container the app writes to."
  type        = string
  default     = "uploads"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", var.container_name))
    error_message = "A container name has 3 to 63 lowercase letters, digits and hyphens, without a leading or trailing hyphen."
  }
}
```

- `variable "container_name" {`: Declares the input variable `container_name`.
- `description = "The one container the app writes to."`: `description` documents it: "The one container the app writes to."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "uploads"`: `default` is used when the caller passes nothing: the text `"uploads"`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", var.container_name))`: `condition` is the rule: `can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", var.container_name))` must be true.
- `error_message = "A container name has 3 to 63 lowercase letters, digits and hyphens, without a leading or trai`…: `error_message` is shown when the rule fails: "A container name has 3 to 63 lowercase letters, digits and hyphens, without a leading or trailing hyphen."
- Closing lines: `}` end the blocks opened above.

**Lines 32 to 41**

```hcl
variable "replication_type" {
  description = "LRS keeps three copies in one datacenter: the cheapest, enough for practice."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GRS or GZRS."
  }
}
```

- `variable "replication_type" {`: Declares the input variable `replication_type`.
- `description = "LRS keeps three copies in one datacenter: the cheapest, enough for practice."`: `description` documents it: "LRS keeps three copies in one datacenter: the cheapest, enough for practice."
- `type        = string`: `type` limits what is accepted: `string`: text.
- `default     = "LRS"`: `default` is used when the caller passes nothing: the text `"LRS"`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)`: `condition` is the rule: `contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)` must be true.
- `error_message = "replication_type must be LRS, ZRS, GRS or GZRS."`: `error_message` is shown when the rule fails: "replication_type must be LRS, ZRS, GRS or GZRS."
- Closing lines: `}` end the blocks opened above.

**Lines 43 to 52**

```hcl
variable "soft_delete_days" {
  description = "Days deleted blobs and containers can be recovered."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_days >= 1 && var.soft_delete_days <= 365
    error_message = "soft_delete_days must be between 1 and 365."
  }
}
```

- `variable "soft_delete_days" {`: Declares the input variable `soft_delete_days`.
- `description = "Days deleted blobs and containers can be recovered."`: `description` documents it: "Days deleted blobs and containers can be recovered."
- `type        = number`: `type` limits what is accepted: `number`: a numeric value (whole or decimal).
- `default     = 7`: `default` is used when the caller passes nothing: the number `7`.
- `validation {`: Starts a rule the input value must satisfy.
- `condition     = var.soft_delete_days >= 1 && var.soft_delete_days <= 365`: `condition` is the rule: `var.soft_delete_days >= 1 && var.soft_delete_days <= 365` must be true.
- `error_message = "soft_delete_days must be between 1 and 365."`: `error_message` is shown when the rule fails: "soft_delete_days must be between 1 and 365."
- Closing lines: `}` end the blocks opened above.

**Lines 54 to 57**

```hcl
variable "log_analytics_workspace_id" {
  description = "Workspace that receives the blob logs."
  type        = string
}
```

- `variable "log_analytics_workspace_id" {`: Declares the input variable `log_analytics_workspace_id`.
- `description = "Workspace that receives the blob logs."`: `description` documents it: "Workspace that receives the blob logs."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 59 to 63**

```hcl
variable "tags" {
  description = "Tags applied to the account."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Tags applied to the account."`: `description` documents it: "Tags applied to the account."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/storage_uploads/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/user_assigned_identity/outputs.tf`

16 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
output "id" {
  description = "Resource id; a container app lists it under `identity_ids`."
  value       = azurerm_user_assigned_identity.this.id
}
```

- `output "id" {`: Declares the output `id`.
- `description = "Resource id; a container app lists it under `identity_ids`."`: `description` documents it: "Resource id; a container app lists it under `identity_ids`."
- `value       = azurerm_user_assigned_identity.this.id`: `value` is what is exposed: the `id` of the resource `azurerm_user_assigned_identity.this`.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
output "principal_id" {
  description = "Object id of the identity's service principal; role assignments take this, not the client id."
  value       = azurerm_user_assigned_identity.this.principal_id
}
```

- `output "principal_id" {`: Declares the output `principal_id`.
- `description = "Object id of the identity's service principal; role assignments take this, not the client id."`: `description` documents it: "Object id of the identity's service principal; role assignments take this, not the client id."
- `value       = azurerm_user_assigned_identity.this.principal_id`: `value` is what is exposed: the `principal_id` of the resource `azurerm_user_assigned_identity.this`.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
output "client_id" {
  description = "Application id; the app's AZURE_CLIENT_ID. It names the identity and is not a secret."
  value       = azurerm_user_assigned_identity.this.client_id
}
```

- `output "client_id" {`: Declares the output `client_id`.
- `description = "Application id; the app's AZURE_CLIENT_ID. It names the identity and is not a secret."`: `description` documents it: "Application id; the app's AZURE_CLIENT_ID. It names the identity and is not a secret."
- `value       = azurerm_user_assigned_identity.this.client_id`: `value` is what is exposed: the `client_id` of the resource `azurerm_user_assigned_identity.this`.
- Closing line: `}` ends the block opened above.

**Lines 16 to 19**

```hcl
output "name" {
  description = "Identity name."
  value       = azurerm_user_assigned_identity.this.name
}
```

- `output "name" {`: Declares the output `name`.
- `description = "Identity name."`: `description` documents it: "Identity name."
- `value       = azurerm_user_assigned_identity.this.name`: `value` is what is exposed: the `name` of the resource `azurerm_user_assigned_identity.this`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/user_assigned_identity/tests/user_assigned_identity.tftest.hcl`

14 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```hcl
mock_provider "azurerm" {}
```

- `mock_provider "azurerm" {}`: An empty `mock_provider` block for `azurerm`: the fake invents every value, with no special settings.

**Lines 3 to 8**

```hcl
variables {
  name                = "id-secretless-app"
  resource_group_name = "rg-test"
  location            = "westeurope"
  tags                = { project = "test" }
}
```

- `variables {`: Starts a `variables` block.
- `name                = "id-secretless-app"`: Sets the input variable `name` (Identity name, for example id-secretless-app) to the text `"id-secretless-app"`.
- `resource_group_name = "rg-test"`: Sets the input variable `resource_group_name` (Resource group that holds the identity) to the text `"rg-test"`.
- `location            = "westeurope"`: Sets the input variable `location` (Azure region) to the text `"westeurope"`.
- `tags                = { project = "test" }`: Sets the input variable `tags` (Tags applied to the identity) to `{ project = "test" }`.
- Closing line: `}` ends the block opened above.

**Lines 10 to 17**

```hcl
run "creates_a_user_assigned_identity_with_the_given_name_and_tags" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.this.name == "id-secretless-app" && azurerm_user_assigned_identity.this.tags["project"] == "test"
    error_message = "the identity must carry the requested name and tags"
  }
}
```

- `run "creates_a_user_assigned_identity_with_the_given_name_and_tags" {`: Starts the test step `creates a user assigned identity with the given name and tags`.
- `command = plan`: `command = plan`.
- `assert {`: Starts an `assert` block.
- `condition     = azurerm_user_assigned_identity.this.name == "id-secretless-app" && azurerm_user_assigned_ident`…: `condition` is the rule: `azurerm_user_assigned_identity.this.name == "id-secretless-app" && azurerm_user_assigned_identity.this.tags["project"] == "test"` must be true.
- `error_message = "the identity must carry the requested name and tags"`: `error_message` is shown when the rule fails: "the identity must carry the requested name and tags"
- Closing lines: `}` end the blocks opened above.

#### `infra/modules/user_assigned_identity/variables.tf`

17 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 4**

```hcl
variable "name" {
  description = "Identity name, for example id-secretless-app."
  type        = string
}
```

- `variable "name" {`: Declares the input variable `name`.
- `description = "Identity name, for example id-secretless-app."`: `description` documents it: "Identity name, for example id-secretless-app."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 6 to 9**

```hcl
variable "resource_group_name" {
  description = "Resource group that holds the identity."
  type        = string
}
```

- `variable "resource_group_name" {`: Declares the input variable `resource_group_name`.
- `description = "Resource group that holds the identity."`: `description` documents it: "Resource group that holds the identity."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 11 to 14**

```hcl
variable "location" {
  description = "Azure region."
  type        = string
}
```

- `variable "location" {`: Declares the input variable `location`.
- `description = "Azure region."`: `description` documents it: "Azure region."
- `type        = string`: `type` limits what is accepted: `string`: text.
- Closing line: `}` ends the block opened above.

**Lines 16 to 20**

```hcl
variable "tags" {
  description = "Tags applied to the identity."
  type        = map(string)
  default     = {}
}
```

- `variable "tags" {`: Declares the input variable `tags`.
- `description = "Tags applied to the identity."`: `description` documents it: "Tags applied to the identity."
- `type        = map(string)`: `type` limits what is accepted: `map(string)`: a set of named texts (name to text).
- `default     = {}`: `default` is used when the caller passes nothing: `{}`.
- Closing line: `}` ends the block opened above.

#### `infra/modules/user_assigned_identity/versions.tf`

9 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 10**

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

- `terraform {`: Starts the settings for Terraform itself.
- `required_version = ">= 1.9"`: `required_version`: Which Terraform versions may run this code. `>= 1.9` means 1.9 or newer. Here: the text `">= 1.9"`.
- `required_providers {`: Lists the provider plug-ins needed.
- `azurerm = {`: Names the provider `azurerm`; its settings follow.
- `source  = "hashicorp/azurerm"`: Entry `source`: the text `"hashicorp/azurerm"`.
- `version = "~> 4.81"`: Entry `version`: the text `"~> 4.81"`.
- Closing lines: `}` end the blocks opened above.


### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `Makefile` | 36, 42, 47, 50, 66 to 67, 70 to 73, 104 | [make.md](make.md) |
| `scripts/provision.sh` | 8, 21, 34 to 35 | [bash.md](bash.md) |
| `.gitignore` | 17 to 18, 28 | [git.md](git.md) |
| `.dockerignore` | 11 to 12 | [docker.md](docker.md) |
| `.github/workflows/ci.yml` | 21, 25 | [github-actions.md](github-actions.md) |
| `.tflint.hcl` | 6, 14 | [tflint.md](tflint.md) |
| `infra/environments/dev/versions.tf` | 1, 16 | [terraform-providers.md](terraform-providers.md) |
| `scripts/break-and-measure.sh` | 7, 57 | [bash.md](bash.md) |
| `scripts/build-and-deploy.sh` | 8, 26 | [bash.md](bash.md) |
| `scripts/teardown.sh` | 6, 15 | [bash.md](bash.md) |
| `.checkov.yaml` | 10 | [checkov.md](checkov.md) |
| `scripts/audit-config.sh` | 6 | [bash.md](bash.md) |
| `scripts/lib.sh` | 25 | [bash.md](bash.md) |
| `scripts/prove-key-access-closed.sh` | 5 | [bash.md](bash.md) |
| `scripts/read-denials.sh` | 7 | [bash.md](bash.md) |
| `scripts/seed-secret.sh` | 6 | [bash.md](bash.md) |
| `scripts/smoke.sh` | 5 | [bash.md](bash.md) |

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
