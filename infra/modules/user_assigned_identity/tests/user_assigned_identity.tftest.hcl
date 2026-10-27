mock_provider "azurerm" {}

variables {
  name                = "id-secretless-app"
  resource_group_name = "rg-test"
  location            = "westeurope"
  tags                = { project = "test" }
}

run "creates_a_user_assigned_identity_with_the_given_name_and_tags" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.this.name == "id-secretless-app" && azurerm_user_assigned_identity.this.tags["project"] == "test"
    error_message = "the identity must carry the requested name and tags"
  }
}
