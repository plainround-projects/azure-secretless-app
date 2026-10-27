mock_provider "azurerm" {}

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

run "refuses_a_variable_named_like_a_credential" {
  command = plan

  variables {
    env = {
      STORAGE_CONNECTION_STRING = "x"
    }
  }

  expect_failures = [var.env]
}

run "refuses_a_variable_valued_like_a_connection_string" {
  command = plan

  variables {
    env = {
      STORAGE = "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=abc"
    }
  }

  expect_failures = [var.env]
}

run "refuses_the_latest_tag" {
  command = plan

  variables {
    image = "acrtest.azurecr.io/azure-secretless-app:latest"
  }

  expect_failures = [var.image]
}

run "refuses_an_image_without_a_tag" {
  command = plan

  variables {
    image = "acrtest.azurecr.io/azure-secretless-app"
  }

  expect_failures = [var.image]
}
