# Module: storage_uploads

A storage account with **shared key access disabled**, public blob access off, TLS 1.2 and blob soft delete, one private container, and the blob service's read, write and delete logs sent to a workspace.

With `shared_access_key_enabled = false`, `az storage container list --account-name <name> --auth-mode key` fails with `KeyBasedAuthenticationNotPermitted`: that is the proof for step 2 ("Done when").

The container is created through the Resource Manager API (`storage_account_id`), so Terraform needs neither a key nor a data role.

| Input | Meaning | Default |
|---|---|---|
| `name` | 3 to 24 lowercase letters and digits | required |
| `resource_group_name`, `location` | Placement | required |
| `container_name` | The one container | `uploads` |
| `replication_type` | LRS, ZRS, GRS, GZRS | `LRS` |
| `soft_delete_days` | 1 to 365 | `7` |
| `log_analytics_workspace_id` | Receives the blob logs | required |
| `tags` | Tags | `{}` |

| Output | Meaning |
|---|---|
| `id`, `name` | Account |
| `blob_endpoint` | STORAGE_URL for the app |
| `container_name` | `uploads` |
| `container_resource_manager_id` | Scope for the Storage Blob Data Contributor role |

Test: `tests/storage_uploads.tftest.hcl` (keys off, public access off, TLS, private container, logs, name rule).
