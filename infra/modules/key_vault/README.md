# Module: key_vault

A Key Vault that authorizes with Azure RBAC (no access policies), keeps deleted vaults for the shortest soft-delete period, and sends its `AuditEvent` log to a workspace. It creates no secret: the value never enters Terraform state (`scripts/seed-secret.sh` sets it).

| Input | Meaning | Default |
|---|---|---|
| `name` | 3 to 24 characters, globally unique | required |
| `resource_group_name`, `location`, `tenant_id` | Placement and tenant | required |
| `log_analytics_workspace_id` | Receives `AuditEvent` | required |
| `soft_delete_retention_days` | 7 to 90 | `7` |
| `purge_protection_enabled` | Block purge during retention | `false` (practice) |
| `public_network_access_enabled` | Public endpoint | `true` |
| `tags` | Tags | `{}` |

| Output | Meaning |
|---|---|
| `id` | Scope for the Secrets User role |
| `name` | Vault name |
| `vault_uri` | VAULT_URL for the app |

Owner of the resource group is a management role: it cannot read secrets. The operator needs a data role (`deployer_object_id` in the environment grants Key Vault Secrets Officer).

Test: `tests/key_vault.tftest.hcl` (RBAC on, name rule, soft-delete bounds).
