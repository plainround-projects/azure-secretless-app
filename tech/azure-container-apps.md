# Azure Container Apps

*Runs the app image with the managed identity attached. Pinned here: azurerm_container_app (azurerm 4.81).*

## What it is

Azure Container Apps runs containers without you managing servers or Kubernetes. A **Container Apps environment** is the shared boundary (networking and logging) for one or more **container apps**. Each app has one or more **replicas** (running copies), an optional **ingress** (a public HTTPS address), and **probes** that check health.

## Why this repository uses it

The lesson allows Container Apps or App Service. Container Apps scale to zero, so idle practice costs nothing.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/modules/container_app/` | The environment and the app. |
| `infra/environments/dev/main.tf` | Passes the addresses as environment variables. |

## How it works underneath

When a replica starts, the platform pulls the image (using the registry identity), starts the container with the environment variables you set, and waits for the **startup probe**. A **liveness probe** that fails makes the platform restart the replica; a **readiness probe** that fails stops traffic being sent to it. With `min_replicas = 0` the app **scales to zero** when idle and the first request pays a cold start.

A container app can have identities attached; the code gets tokens from them. Environment variables are plain text visible in the app's configuration, which is why no secret goes there. Console output goes to the environment's Log Analytics workspace. Ephemeral volumes (`EmptyDir`) live only as long as the replica.

## Walkthrough of this repository's use

```hcl
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
```

`revision_mode = "Single"` keeps only the latest revision. The `identity` block attaches both identities. The `registry` block says to pull with the pull identity, not a password.

```hcl
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
```

`external_enabled = true` gives the app a public HTTPS address; `allow_insecure_connections = false` refuses plain HTTP. `traffic_weight` sends 100 percent to the latest revision.

```hcl
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
```

`dynamic "env"` creates one `env` block per entry of the `env` map (there is no `secret` block at all). The liveness and startup probes call `/live`, which touches no dependency; a missing role shows as a 502 on `/health`, not as a restart loop.

### Settings with no secret in them

```hcl
  env = {
    AZURE_CLIENT_ID  = module.app_identity.client_id
    VAULT_URL        = module.key_vault.vault_uri
    STORAGE_URL      = module.storage.blob_endpoint
    UPLOAD_CONTAINER = module.storage.container_name
  }
```

Four plain values: the identity's client id, the vault address, the storage address and the container name.

### The module refuses credentials

```hcl
variable "env" {
  description = "Plain environment variables: addresses and the client id of the identity. Credentials are refused by name and by value."
  type        = map(string)
  default     = {}

  validation {
    condition = !anytrue([
      for name in keys(var.env) :
      can(regex("(?i)(password|passwd|connection_?string|client_?secret|account_?key|sas_?token|api_?key)", name))
    ])
    error_message = "An environment variable name suggests a credential (password, connection string, client secret, account key, SAS token, API key). The app authenticates with its managed identity instead."
  }

  validation {
    condition = !anytrue([
      for value in values(var.env) :
      can(regex("(?i)(accountkey=|sharedaccesssignature=|[?&]sig=|password=|pwd=|-----BEGIN)", value))
    ])
    error_message = "An environment variable value looks like a connection string, SAS token or private key."
  }
}
```

Two validations: variable **names** that suggest a credential (`password`, `connection_string`, `client_secret`...) and **values** that look like a connection string or a private key are refused at plan time.

## Try it yourself

Run the module tests, which try credential-shaped variables and `:latest`.

```bash
cd infra/modules/container_app && terraform init -backend=false -input=false >/dev/null && terraform test 2>&1 | tail -4
```

You should see something like this:

```text
tests/container_app.tftest.hcl... tearing down
tests/container_app.tftest.hcl... pass

Success! 6 passed, 0 failed.
```

See the scale-to-zero default.

```bash
grep -n 'min_replicas' -A2 infra/modules/container_app/variables.tf | head -6
```

You should see something like this:

```text
79:variable "min_replicas" {
80-  description = "Minimum replicas. 0 scales to zero and costs nothing idle but adds a cold start."
81-  type        = number
--
85:    condition     = var.min_replicas >= 0 && var.min_replicas <= var.max_replicas
86:    error_message = "min_replicas must be between 0 and max_replicas."
```

## Mistakes people make

- Probes that call a dependency. If the dependency's role is removed, the app restarts in a loop; liveness here checks only the process.
- Putting secrets in environment variables.
- Forgetting that scale-to-zero adds a cold start to the first request.
- Storing data on the replica's own disk and expecting it to survive.
- Attaching two identities and not saying which one the code should use.

## Check yourself

1. **What is a replica?**
   Answer: One running copy of the app's container.

2. **What does a failing liveness probe cause?**
   Answer: The platform restarts the replica.

3. **What does `min_replicas = 0` mean?**
   Answer: The app scales to zero when idle.

4. **Where do the app's console logs go?**
   Answer: To the environment's Log Analytics workspace.

5. **How does the app prove who it is to Key Vault?**
   Answer: With a token from its attached managed identity.

## Further reading

- Container Apps overview: https://learn.microsoft.com/en-us/azure/container-apps/overview
- Health probes: https://learn.microsoft.com/en-us/azure/container-apps/health-probes
- Managed identity: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
