resource "azurerm_container_app_environment" "this" {
  name                       = var.environment_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags
}

resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = var.tags

  # Both identities are attached; the registry block names the pull identity and DefaultAzureCredential in the app
  # is pointed at the app identity by AZURE_CLIENT_ID.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.app_identity_id, var.pull_identity_id]
  }

  registry {
    server   = var.registry_server
    identity = var.pull_identity_id
  }

  ingress {
    external_enabled           = true
    target_port                = var.container_port
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      # Plain environment variables only. There is deliberately no `secret` block and no `secret_name` here.
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Liveness touches no dependency, so a missing role never restarts the app and hides the denial being studied.
      liveness_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = "/live"
        interval_seconds        = 10
        failure_count_threshold = 3
      }

      startup_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = "/live"
        interval_seconds        = 3
        failure_count_threshold = 10
      }
    }
  }
}
