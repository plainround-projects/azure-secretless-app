# Azure Key Vault

*Holds the partner API key the app reads. Pinned here: Key Vault with Azure RBAC authorization.*

## What it is

Azure Key Vault is a managed service that stores **secrets** (such as an API key), keys and certificates, and controls who can read them. Reading a secret is logged. A vault is addressed as `https://<name>.vault.azure.net`.

## Why this repository uses it

The lesson's app reads a key from a vault with a role, not with a secret. The vault is created with RBAC on and soft delete at its shortest.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/modules/key_vault/` | The vault and its audit log. |
| `scripts/seed-secret.sh` | Sets the secret. |
| `scripts/teardown.sh` | Looks at the soft-deleted vault. |
| `src/secretless_app/infrastructure/azure_adapters.py` | Reads the secret. |

## How it works underneath

A vault can authorize callers in two ways: old *access policies* local to the vault, or **Azure RBAC**, the same role system the rest of Azure uses. This repository turns RBAC on (`rbac_authorization_enabled = true`). Roles such as `Key Vault Secrets User` (read values) and `Key Vault Secrets Officer` (manage secrets) are data roles on the vault.

Deleted vaults are kept for a **soft-delete** period (7 to 90 days) and the name stays reserved. **Purge protection**, when on, forbids purging a deleted vault before that period ends. The vault's **network setting** `publicNetworkAccess` decides whether its public address accepts calls; with it off, only a private endpoint reaches it.

The `AuditEvent` log records each data-plane call, including denials with the caller's object id.

## Walkthrough of this repository's use

```hcl
resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_189:public endpoint stays on so the operator can seed the secret; the private endpoint is the azure-private-platform-slice project
  #checkov:skip=CKV_AZURE_109:no firewall rules for the same reason
  #checkov:skip=CKV2_AZURE_32:a private endpoint for the vault is the lesson's stretch goal
  #checkov:skip=CKV_AZURE_110:purge protection is the purge_protection_enabled variable, off for practice so a vault can be purged; on in production
  #checkov:skip=CKV_AZURE_42:recoverable means soft delete (always on, 7 to 90 days) plus purge protection, which is the variable above
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Azure roles instead of the vault-only access policies: one permission model, with scopes and audit.
  rbac_authorization_enabled = true

  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = var.purge_protection_enabled
  public_network_access_enabled = var.public_network_access_enabled
}
```

`rbac_authorization_enabled = true` turns on Azure roles instead of the vault's own access policies. `soft_delete_retention_days` is 7 (the minimum): a deleted vault keeps its name reserved for that long. `purge_protection_enabled` is a variable, off for practice so a vault can be purged. `public_network_access_enabled` is on, because the operator's laptop sets the secret; the next project closes it.

```hcl
resource "azurerm_monitor_diagnostic_setting" "audit" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # AuditEvent holds every data-plane call and every denial, with the caller's object id.
  enabled_log {
    category = "AuditEvent"
  }
}
```

Sends the `AuditEvent` log to the workspace. Each secret read, and each refusal with the caller's object id, appears there.

### Why Terraform does not create the secret

The secret's value would be stored in Terraform's state file in clear text. `scripts/seed-secret.sh` sets it with `az keyvault secret set` instead.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `infra/modules/key_vault/main.tf`

27 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 20**

```hcl
resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_189:public endpoint stays on so the operator can seed the secret; the private endpoint is the azure-private-platform-slice project
  #checkov:skip=CKV_AZURE_109:no firewall rules for the same reason
  #checkov:skip=CKV2_AZURE_32:a private endpoint for the vault is the lesson's stretch goal
  #checkov:skip=CKV_AZURE_110:purge protection is the purge_protection_enabled variable, off for practice so a vault can be purged; on in production
  #checkov:skip=CKV_AZURE_42:recoverable means soft delete (always on, 7 to 90 days) plus purge protection, which is the variable above
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Azure roles instead of the vault-only access policies: one permission model, with scopes and audit.
  rbac_authorization_enabled = true

  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = var.purge_protection_enabled
  public_network_access_enabled = var.public_network_access_enabled
}
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** **TLS** is the protocol that encrypts a network connection and proves who is on the other end, which is what the `s` in `https` stands for. The server proves its identity with a **certificate**, a signed document that names the server and carries its public key; a client refuses a certificate it cannot trust.

**New idea.** **Microsoft Entra ID** (formerly Azure Active Directory) is the identity service of Azure. A **tenant** is one organization's directory in it. Every identity in the directory (a person, a group, an application, a managed identity) has an *object id*, and the party that receives permissions is called the *principal*.

**New idea.** **Azure role-based access control (RBAC)** decides who may do what. A *role* is a named bundle of permissions (for example "Key Vault Secrets User" may read secrets), a *scope* is where the grant applies (one resource, a resource group, a whole subscription), and a *role assignment* connects an identity, a role and a scope. The smaller the scope, the less a leaked identity can do.

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** A **private endpoint** gives an Azure service (a vault, a storage account) a private IP address inside your subnet, so traffic stays on your private network. For the service's normal name to lead to that private address, a *private DNS zone* (such as `privatelink.vaultcore.azure.net`) must be linked to the network.

**New idea.** An Azure **resource group** is a folder-like container for the resources of one project. Resources in a group share a life cycle: deleting the group deletes everything in it.

**New idea.** **Tags** are name/value labels attached to Azure resources. They change no behavior; they record the owner, project and environment and make cost reports and clean-up possible.

**New idea.** An Azure **region** (such as `westeurope`) is a group of data centers in one geographic area. Where a resource is created decides its latency, its price and which legal rules apply.

- `resource "azurerm_key_vault" "this" {`: A `resource` block declares one real thing Terraform must create and keep in step with this file. It has two labels: the **type** (such as `azurerm_key_vault`, which names the provider and the kind of thing) and a **local name** (such as `this`) used only to refer to it from other places as `azurerm_key_vault.this`. The lines inside are the thing's settings, called **arguments**. Declares the resource `azurerm_key_vault.this`. A **Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use.
- `#checkov:skip=CKV_AZURE_189:public endpoint stays on so the operator can seed the secret; the private endpoint`…: A comment of the form `#checkov:skip=RULE:reason` tells the scanner checkov to ignore one rule for this resource and records why. Without the reason the skip is hard to defend in review. Scanner exception for rule `CKV_AZURE_189`: public endpoint stays on so the operator can seed the secret; the private endpoint is the azure-private-platform-slice project.
- `#checkov:skip=CKV_AZURE_109:no firewall rules for the same reason`: Scanner exception for rule `CKV_AZURE_109`: no firewall rules for the same reason.
- `#checkov:skip=CKV2_AZURE_32:a private endpoint for the vault is the lesson's stretch goal`: Scanner exception for rule `CKV2_AZURE_32`: a private endpoint for the vault is the lesson's stretch goal.
- `#checkov:skip=CKV_AZURE_110:purge protection is the purge_protection_enabled variable, off for practice so a v`…: Scanner exception for rule `CKV_AZURE_110`: purge protection is the purge_protection_enabled variable, off for practice so a vault can be purged; on in production.
- `#checkov:skip=CKV_AZURE_42:recoverable means soft delete (always on, 7 to 90 days) plus purge protection, whic`…: Scanner exception for rule `CKV_AZURE_42`: recoverable means soft delete (always on, 7 to 90 days) plus purge protection, which is the variable above.
- `name                = var.name`: `name`: The name of this thing in Azure. Here: the input variable `name` (Vault name: 3 to 24 characters, letters, digits and hyphens, globally unique).
- `resource_group_name = var.resource_group_name`: `resource_group_name`: The resource group the thing is created in. Here: the input variable `resource_group_name` (Resource group that holds the vault).
- `location            = var.location`: `location`: The Azure region (data center area) where the thing is created. Here: the input variable `location` (Azure region).
- `tenant_id           = var.tenant_id`: `tenant_id`: The id of the Microsoft Entra ID tenant (the organization's identity directory) that owns the identities and decides access. Here: the input variable `tenant_id` (Microsoft Entra tenant id the vault belongs to (`az account show --query tenantId`)).
- `sku_name            = "standard"`: `sku_name`: The pricing tier / capability level (the SKU) of the service. Here: the text `"standard"`.
- `tags                = var.tags`: `tags`: Tags are name/value labels attached to the thing. They do not change behavior; they identify the owner, project and environment and make cost reports readable. Here: the input variable `tags` (Tags applied to the vault).
- `# Azure roles instead of the vault-only access policies: one permission model, with scopes and audit.`: A line starting with `#` (or `//`) is a **comment**: Terraform ignores it; it is there for the reader. Comment for the reader: Azure roles instead of the vault-only access policies: one permission model, with scopes and audit.
- `rbac_authorization_enabled = true`: `rbac_authorization_enabled`: When `true`, access to the vault's contents is decided by Azure roles (RBAC) instead of the older per-vault access policies, giving one permission model with scopes and audit. Here: `true`.
- `soft_delete_retention_days    = var.soft_delete_retention_days`: `soft_delete_retention_days`: How many days a deleted vault or secret stays recoverable before it is gone for good. Here: the input variable `soft_delete_retention_days` (Days a deleted vault keeps its name reserved. The minimum, 7, keeps practice runs short).
- `purge_protection_enabled      = var.purge_protection_enabled`: `purge_protection_enabled`: When `true`, a deleted vault cannot be purged (permanently erased) until the retention period ends, even by an administrator. Here: the input variable `purge_protection_enabled` (When true, a deleted vault cannot be purged until the retention ends. Turn it on in production; leave it off for practice so the name can be reused).
- `public_network_access_enabled = var.public_network_access_enabled`: `public_network_access_enabled`: Whether the service accepts connections from the public internet. `false` leaves only private endpoints. Here: the input variable `public_network_access_enabled` (Public endpoint on or off. This project keeps it on; the private platform slice project turns it off behind a private endpoint).
- Closing line: `}` ends the block opened above.

**Lines 22 to 31**

```hcl
resource "azurerm_monitor_diagnostic_setting" "audit" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # AuditEvent holds every data-plane call and every denial, with the caller's object id.
  enabled_log {
    category = "AuditEvent"
  }
}
```

**New idea.** **Log Analytics** is Azure's store for logs and metrics, queried with the Kusto Query Language (KQL). A *diagnostic setting* tells a resource to send its logs there, so that, for example, every refused request to a vault can be found afterwards.

- `resource "azurerm_monitor_diagnostic_setting" "audit" {`: Declares the resource `azurerm_monitor_diagnostic_setting.audit`. A **diagnostic setting** tells an Azure resource to send its logs and metrics to a destination, here a Log Analytics workspace.
- `name                       = "to-log-analytics"`: `name`: The name of this thing in Azure. Here: the text `"to-log-analytics"`.
- `target_resource_id         = azurerm_key_vault.this.id`: `target_resource_id`: The id of the Azure resource whose diagnostics are being routed. Here: the `id` of the resource `azurerm_key_vault.this`.
- `log_analytics_workspace_id = var.log_analytics_workspace_id`: `log_analytics_workspace_id`: The id of the Log Analytics workspace that receives the data. Here: the input variable `log_analytics_workspace_id` (Workspace that receives the AuditEvent log).
- `# AuditEvent holds every data-plane call and every denial, with the caller's object id.`: Comment for the reader: AuditEvent holds every data-plane call and every denial, with the caller's object id.
- `enabled_log {`: Starts the nested `enabled_log` block: Selects one log category to send to the destination.
- `category = "AuditEvent"`: `category`: The name of one log category to send (for example `AuditEvent`). Here: the text `"AuditEvent"`.
- Closing lines: `}` end the blocks opened above.


### Where else this technology appears

Lines of other files that use this technology are explained line by line in the notes of those files. This table lists where to find them.

| File | Matching lines | Explained in |
|---|---|---|
| `infra/environments/dev/tests/dev.tftest.hcl` | 5, 78 to 79, 124 | [terraform.md](terraform.md) |
| `infra/modules/key_vault/outputs.tf` | 2 to 3, 8, 13 | [terraform.md](terraform.md) |
| `scripts/teardown.sh` | 19 to 21, 27 to 29 | [bash.md](bash.md) |
| `src/secretless_app/infrastructure/azure_adapters.py` | 1, 4, 22, 33 | [azure-keyvault-secrets.md](azure-keyvault-secrets.md) |
| `scripts/break-and-measure.sh` | 4, 25 to 26 | [bash.md](bash.md) |
| `src/secretless_app/infrastructure/memory_adapters.py` | 1, 26, 29 | [python.md](python.md) |
| `infra/environments/dev/main.tf` | 37, 60 | [terraform.md](terraform.md) |
| `infra/modules/key_vault/tests/key_vault.tftest.hcl` | 15, 24 | [terraform.md](terraform.md) |
| `pyproject.toml` | 8, 17 | [pyproject-toml.md](pyproject-toml.md) |
| `tests/unit/infrastructure/test_azure_errors.py` | 52, 66 | [pytest.md](pytest.md) |
| `infra/environments/dev/outputs.tf` | 7 | [terraform.md](terraform.md) |
| `infra/environments/dev/variables.tf` | 56 | [terraform.md](terraform.md) |
| `scripts/seed-secret.sh` | 14 | [bash.md](bash.md) |
| `src/secretless_app/__init__.py` | 1 | [python.md](python.md) |
| `src/secretless_app/infrastructure/azure_errors.py` | 35 | [python.md](python.md) |
| `tests/unit/infrastructure/test_azure_adapters.py` | 55 | [pytest.md](pytest.md) |

## Try it yourself

Read the module.

```bash
sed -n 1,25p infra/modules/key_vault/main.tf
```

You should see something like this:

```text
resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_189:public endpoint stays on so the operator can seed the secret; the private endpoint is the azure-private-platform-slice project
  #checkov:skip=CKV_AZURE_109:no firewall rules for the same reason
  #checkov:skip=CKV2_AZURE_32:a private endpoint for the vault is the lesson's stretch goal
  #checkov:skip=CKV_AZURE_110:purge protection is the purge_protection_enabled variable, off for practice so a vault can be purged; on in production
  #checkov:skip=CKV_AZURE_42:recoverable means soft delete (always on, 7 to 90 days) plus purge protection, which is the variable above
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Azure roles instead of the vault-only access policies: one permission model, with scopes and audit.
...
  log_analytics_workspace_id = var.log_analytics_workspace_id
```

Run its tests (RBAC on, soft-delete bounds, name rule).

```bash
cd infra/modules/key_vault && terraform init -backend=false -input=false >/dev/null && terraform test 2>&1 | tail -4
```

You should see something like this:

```text
tests/key_vault.tftest.hcl... tearing down
tests/key_vault.tftest.hcl... pass

Success! 6 passed, 0 failed.
```

## Mistakes people make

- Believing Owner can read secrets (it cannot).
- Creating the vault name again after deleting it, while soft delete still reserves it.
- Putting the secret value into Terraform, which writes it to the state file.
- Leaving purge protection off in production.
- Switching off public access before the secret is seeded from a laptop.

## Check yourself

1. **What does a vault store?**
   Answer: Secrets, keys and certificates.

2. **Why use RBAC instead of access policies?**
   Answer: One permission model across Azure, with scopes and audit.

3. **What does soft delete do?**
   Answer: Keeps a deleted vault for a period and reserves its name.

4. **What does purge protection add?**
   Answer: A deleted vault cannot be purged until the retention ends.

5. **What does the AuditEvent log show?**
   Answer: Each data-plane call and denial, with the caller's identity.

## Further reading

- Key Vault: https://learn.microsoft.com/en-us/azure/key-vault/general/overview
- RBAC guide: https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide
- Soft delete: https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview
