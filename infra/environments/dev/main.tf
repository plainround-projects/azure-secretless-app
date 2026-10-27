resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

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

resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

module "log_analytics" {
  source = "../../modules/log_analytics"

  name                = local.names.workspace
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

module "app_identity" {
  source = "../../modules/user_assigned_identity"

  name                = local.names.app_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

module "pull_identity" {
  source = "../../modules/user_assigned_identity"

  name                = local.names.pull_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

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

module "storage" {
  source = "../../modules/storage_uploads"

  name                       = local.names.storage
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.tags
}

module "registry" {
  source = "../../modules/container_registry"

  name                = local.names.registry
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

module "role_assignments" {
  source = "../../modules/role_assignments"

  assignments = merge(local.app_assignments, local.pull_assignments, local.deployer_assignments)
}

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

module "budget" {
  source = "../../modules/budget"
  count  = length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = local.names.budget
  subscription_id = var.subscription_id
  amount          = var.budget_amount
  start_date      = coalesce(var.budget_start_date, "2026-01-01T00:00:00Z")
  contact_emails  = var.budget_contact_emails
}
