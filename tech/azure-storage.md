# Azure Storage account and Blob container

*Holds the uploaded files. Pinned here: StorageV2 account, LRS, shared key access disabled.*

## What it is

An Azure **storage account** is the container for Azure's storage services; this repository uses its **Blob** service, which stores files (blobs) in **containers**. The account has a unique name and an address `https://<account>.blob.core.windows.net`.

## Why this repository uses it

The lesson requires an account whose keys are useless, so the identity is the only way in, and a container where the identity may write.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/modules/storage_uploads/` | The account, the container and the blob logs. |
| `scripts/prove-key-access-closed.sh` | Proves keys are refused. |
| `scripts/smoke.sh` | Lists the uploaded blob with your own login. |

## How it works underneath

An account can authorize calls with a **shared key** (a long secret that grants everything) or with Microsoft Entra ID tokens plus roles. This repository switches shared key access off (`shared_access_key_enabled = false`), so the only way in is an identity with a role such as `Storage Blob Data Contributor`, which can be assigned on a single container.

Accounts have network settings too: public network access on or off, and a firewall default action (`Allow` or `Deny`). With public access off, only a private endpoint can reach the account. **Soft delete** keeps deleted blobs and containers for some days. Diagnostic settings can send the blob service's read, write and delete logs to a workspace.

## Walkthrough of this repository's use

```hcl
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = true
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  cross_tenant_replication_enabled = false
```

`shared_access_key_enabled = false` is the central line: account keys and key-signed tokens stop working. `default_to_oauth_authentication` makes the portal and tools use Entra ID by default. `local_user_enabled = false` switches off local (SFTP) users. `allow_nested_items_to_be_public = false` forbids public blobs. `min_tls_version` and `https_traffic_only_enabled` require encrypted connections.

```hcl
resource "azurerm_storage_container" "uploads" {
  #checkov:skip=CKV2_AZURE_21:the blob service's read logs go to the workspace through azurerm_monitor_diagnostic_setting.blob; the check cannot follow the interpolated blobServices id
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
```

The container is created with `storage_account_id`, which uses the management API, so Terraform needs neither a key nor a data role. `container_access_type = "private"`: no anonymous access.

```hcl
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Read, write and delete carry the HTTP status and the error code of each denied call.
  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
```

Diagnostic settings for storage are on the **blob service** inside the account, so the target id adds `/blobServices/default`. The three categories record reads, writes and deletes with their status codes.

## Try it yourself

Run the module's tests.

```bash
cd infra/modules/storage_uploads && terraform init -backend=false -input=false >/dev/null && terraform test 2>&1 | tail -4
```

You should see something like this:

```text
tests/storage_uploads.tftest.hcl... tearing down
tests/storage_uploads.tftest.hcl... pass

Success! 5 passed, 0 failed.
```

Find the line that closes the key path.

```bash
grep -n 'shared_access_key_enabled' infra/modules/storage_uploads/main.tf
```

You should see something like this:

```text
16:  shared_access_key_enabled       = false
```

## Mistakes people make

- Leaving shared key access on and then using a key in an app.
- Granting the blob role on the whole account when one container is enough.
- Using a name with capitals or hyphens: account names are 3 to 24 lowercase letters and digits.
- Forgetting that Owner cannot read blobs.
- Creating the container with a key when keys are off; the Terraform module creates it through the management API instead.

## Check yourself

1. **What is a blob container?**
   Answer: A grouping of blobs inside a storage account.

2. **What does disabling shared key access do?**
   Answer: Account keys and key-signed tokens stop working; only Entra ID access remains.

3. **What is the narrowest scope for a blob role here?**
   Answer: The single container.

4. **What are the rules for an account name?**
   Answer: 3 to 24 lowercase letters and digits, globally unique.

5. **What does the firewall default action control?**
   Answer: Whether traffic that matches no rule is allowed or denied.

## Further reading

- Storage accounts: https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview
- Prevent shared key authorization: https://learn.microsoft.com/en-us/azure/storage/common/shared-key-authorization-prevent
