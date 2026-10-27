# Module: container_registry

An Azure Container Registry with the admin user and anonymous pull off. The container app pulls through a second managed identity that holds `AcrPull` on this registry only, so the app's own identity keeps exactly the two roles the lesson asks for.

| Input | Meaning | Default |
|---|---|---|
| `name` | 5 to 50 letters and digits | required |
| `resource_group_name`, `location` | Placement | required |
| `sku` | Basic, Standard, Premium | `Basic` |
| `tags` | Tags | `{}` |

| Output | Meaning |
|---|---|
| `id` | Scope for AcrPull |
| `name` | For `az acr build` |
| `login_server` | Image prefix |

Test: `tests/container_registry.tftest.hcl` (no admin user, no anonymous pull).
