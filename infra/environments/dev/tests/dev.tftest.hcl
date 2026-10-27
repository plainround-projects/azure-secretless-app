# Plans and applies the whole environment against a mocked azurerm provider: no credentials, no network.
# It proves the composition (who holds which role, what the app is told) and the guards, not Azure's behavior.

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

override_resource {
  target = module.app_identity.azurerm_user_assigned_identity.this
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-secretless-app"
    principal_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    client_id    = "cccccccc-cccc-cccc-cccc-cccccccccccc"
  }
}

override_resource {
  target = module.pull_identity.azurerm_user_assigned_identity.this
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-secretless/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-secretless-pull"
    principal_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    client_id    = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "11111111-1111-1111-1111-111111111111"
  suffix          = "abcde"
}

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

run "no_deployer_roles_unless_asked" {
  command = apply

  assert {
    condition     = length(module.role_assignments.assignments) == 3
    error_message = "two for the app and one for the pull identity, and nothing for a deployer that was not named"
  }
}

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

run "an_app_without_an_image_is_refused" {
  command = plan

  variables {
    deploy_app = true
  }

  expect_failures = [var.image]
}

run "a_budget_needs_a_start_date" {
  command = plan

  variables {
    budget_contact_emails = ["owner@example.com"]
  }

  expect_failures = [var.budget_start_date]
}

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
