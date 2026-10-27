mock_provider "azurerm" {}

variables {
  name                       = "stsecretless12345"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
}

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

run "blocks_public_blobs_and_old_tls" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false && azurerm_storage_account.this.min_tls_version == "TLS1_2" && azurerm_storage_account.this.https_traffic_only_enabled
    error_message = "no public blobs, TLS 1.2 or newer, HTTPS only"
  }
}

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

run "refuses_a_name_with_a_hyphen" {
  command = plan

  variables {
    name = "st-secretless"
  }

  expect_failures = [var.name]
}

run "refuses_an_unknown_replication_type" {
  command = plan

  variables {
    replication_type = "RAGRS-PLUS"
  }

  expect_failures = [var.replication_type]
}
