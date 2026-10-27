# Module: container_app

A Container Apps environment (logging to the workspace) and one container app that runs as a user-assigned identity.

- **Two identities, two jobs.** `app_identity_id` is what the application code uses (named by `AZURE_CLIENT_ID`); `pull_identity_id` only pulls the image from the registry. That keeps the application identity at exactly two role assignments.
- **No secrets by construction.** The module has no `secret` block. `env` rejects names such as `password`, `connection_string`, `account_key` and values such as `AccountKey=`, `sig=` or a private key header.
- **No `:latest`.** `image` must carry a version tag or a digest.
- **Probes.** Liveness and startup call `/live`, which touches no dependency; a missing role shows as a 502 on `/health` and `/upload`, not as a restart loop.
- **Scale to zero** by default (`min_replicas = 0`): idle cost is zero, the first request after idle pays a cold start.

| Input | Meaning | Default |
|---|---|---|
| `name`, `environment_name`, `resource_group_name`, `location` | Placement | required |
| `log_analytics_workspace_id` | Console logs | required |
| `image` | Versioned image | required |
| `app_identity_id`, `pull_identity_id`, `registry_server` | Identities and registry | required |
| `env` | Plain variables | `{}` |
| `container_port` | App port | `8000` |
| `min_replicas`, `max_replicas` | Scale range | `0`, `2` |
| `cpu`, `memory` | Per replica | `0.25`, `0.5Gi` |
| `tags` | Tags | `{}` |

| Output | Meaning |
|---|---|
| `name` | App name |
| `fqdn` | Host name |
| `url` | `https://` address |

Test: `tests/container_app.tftest.hcl` (no secret blocks, HTTPS only, credential-shaped variables and `:latest` refused).
