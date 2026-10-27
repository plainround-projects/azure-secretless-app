resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_59:public network access stays on for the operator; the private endpoint is the azure-private-platform-slice project
  #checkov:skip=CKV2_AZURE_33:a private endpoint for the account is that same later project
  #checkov:skip=CKV_AZURE_206:LRS is the cheapest replication and enough for practice; replication_type is a variable
  #checkov:skip=CKV2_AZURE_1:customer-managed keys are a production control outside this lesson; Microsoft-managed keys encrypt the data
  #checkov:skip=CKV_AZURE_33:the account uses no queue service, so there is nothing to log
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"
  tags                     = var.tags

  # The identity is the only way in: account keys and SAS tokens signed with them stop working.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = true
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  cross_tenant_replication_enabled = false

  blob_properties {
    delete_retention_policy {
      days = var.soft_delete_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_days
    }
  }
}

# Created through the Azure Resource Manager API (storage_account_id), so Terraform needs no data-plane
# permission and no account key to make it.
resource "azurerm_storage_container" "uploads" {
  #checkov:skip=CKV2_AZURE_21:the blob service's read logs go to the workspace through azurerm_monitor_diagnostic_setting.blob; the check cannot follow the interpolated blobServices id
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Read, write and delete carry the HTTP status and the error code of each denied call.
  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}
