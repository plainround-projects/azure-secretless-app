mock_provider "azurerm" {}

variables {
  name                       = "kv-test-12345"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  tenant_id                  = "11111111-1111-1111-1111-111111111111"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
}

run "authorizes_with_azure_roles_not_access_policies" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "the vault must use Azure RBAC"
  }
}

run "keeps_the_shortest_soft_delete_and_no_purge_protection_for_practice" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 7 && !azurerm_key_vault.this.purge_protection_enabled
    error_message = "practice defaults are 7 days and no purge protection"
  }
}

run "sends_the_audit_event_log_to_the_workspace" {
  command = plan

  assert {
    condition     = one(azurerm_monitor_diagnostic_setting.audit.enabled_log).category == "AuditEvent"
    error_message = "the AuditEvent category must be enabled"
  }
}

run "refuses_a_name_that_is_too_short" {
  command = plan

  variables {
    name = "kv"
  }

  expect_failures = [var.name]
}

run "refuses_a_retention_outside_the_allowed_range" {
  command = plan

  variables {
    soft_delete_retention_days = 3
  }

  expect_failures = [var.soft_delete_retention_days]
}

run "refuses_a_tenant_id_that_is_not_a_guid" {
  command = plan

  variables {
    tenant_id = "my-tenant"
  }

  expect_failures = [var.tenant_id]
}
