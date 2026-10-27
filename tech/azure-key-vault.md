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
