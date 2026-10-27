# Module: log_analytics

A Log Analytics workspace where the vault's audit events, the storage account's blob logs and the container app's console logs land, so the two denials of step 5 can be read with a query.

| Input | Meaning | Default |
|---|---|---|
| `name` | Workspace name | required |
| `resource_group_name`, `location` | Where it lives | required |
| `retention_in_days` | 30 to 730 | `30` |
| `tags` | Tags | `{}` |

| Output | Meaning |
|---|---|
| `id` | Resource id for diagnostic settings |
| `name` | Workspace name |
| `workspace_id` | Customer id for queries |

Test: `tests/log_analytics.tftest.hcl` (retention bounds).
