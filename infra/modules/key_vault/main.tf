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

resource "azurerm_monitor_diagnostic_setting" "audit" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # AuditEvent holds every data-plane call and every denial, with the caller's object id.
  enabled_log {
    category = "AuditEvent"
  }
}
