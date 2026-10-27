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

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `infra/modules/storage_uploads/main.tf`

54 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 24**

```hcl
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_59:public network access stays on for the operator; the private endpoint is the azure-private-platform-slice project
  #checkov:skip=CKV2_AZURE_33:a private endpoint for the account is that same later project
  #checkov:skip=CKV_AZURE_206:LRS is the cheapest replication and enough for practice; replication_type is a variable
  #checkov:skip=CKV2_AZURE_1:customer-managed keys are a production control outside this lesson; Microsoft-managed keys encrypt the data
  #checkov:skip=CKV_AZURE_33:the account uses no queue service, so there is nothing to log
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"
  tags                     = var.tags

  # The identity is the only way in: account keys and SAS tokens signed with them stop working.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = true
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  cross_tenant_replication_enabled = false
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** **TLS** is the protocol that encrypts a network connection and proves who is on the other end, which is what the `s` in `https` stands for. The server proves its identity with a **certificate**, a signed document that names the server and carries its public key; a client refuses a certificate it cannot trust.

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

**New idea.** An **access token** is a short-lived piece of text, issued by an identity service after you prove who you are, that you attach to a request to show that you are allowed to make it. It expires after about an hour, so a stolen one is far less dangerous than a password.

**New idea.** **Microsoft Entra ID** (formerly Azure Active Directory) is the identity service of Azure. A **tenant** is one organization's directory in it. Every identity in the directory (a person, a group, an application, a managed identity) has an *object id*, and the party that receives permissions is called the *principal*.

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** A **private endpoint** gives an Azure service (a vault, a storage account) a private IP address inside your subnet, so traffic stays on your private network. For the service's normal name to lead to that private address, a *private DNS zone* (such as `privatelink.vaultcore.azure.net`) must be linked to the network.

**New idea.** An Azure **resource group** is a folder-like container for the resources of one project. Resources in a group share a life cycle: deleting the group deletes everything in it.

**New idea.** **Tags** are name/value labels attached to Azure resources. They change no behavior; they record the owner, project and environment and make cost reports and clean-up possible.

**New idea.** An Azure **region** (such as `westeurope`) is a group of data centers in one geographic area. Where a resource is created decides its latency, its price and which legal rules apply.

- `resource "azurerm_storage_account" "this" {`: A `resource` block declares one real thing Terraform must create and keep in step with this file. It has two labels: the **type** (such as `azurerm_key_vault`, which names the provider and the kind of thing) and a **local name** (such as `this`) used only to refer to it from other places as `azurerm_key_vault.this`. The lines inside are the thing's settings, called **arguments**. Declares the resource `azurerm_storage_account.this`. A **storage account** is the top-level container for Azure's storage services (blobs, files, queues, tables) with its own settings for networking, encryption and authentication.
- `#checkov:skip=CKV_AZURE_59:public network access stays on for the operator; the private endpoint is the azure-`…: A comment of the form `#checkov:skip=RULE:reason` tells the scanner checkov to ignore one rule for this resource and records why. Without the reason the skip is hard to defend in review. Scanner exception for rule `CKV_AZURE_59`: public network access stays on for the operator; the private endpoint is the azure-private-platform-slice project.
- `#checkov:skip=CKV2_AZURE_33:a private endpoint for the account is that same later project`: Scanner exception for rule `CKV2_AZURE_33`: a private endpoint for the account is that same later project.
- `#checkov:skip=CKV_AZURE_206:LRS is the cheapest replication and enough for practice; replication_type is a var`…: Scanner exception for rule `CKV_AZURE_206`: LRS is the cheapest replication and enough for practice; replication_type is a variable.
- `#checkov:skip=CKV2_AZURE_1:customer-managed keys are a production control outside this lesson; Microsoft-manag`…: Scanner exception for rule `CKV2_AZURE_1`: customer-managed keys are a production control outside this lesson; Microsoft-managed keys encrypt the data.
- `#checkov:skip=CKV_AZURE_33:the account uses no queue service, so there is nothing to log`: Scanner exception for rule `CKV_AZURE_33`: the account uses no queue service, so there is nothing to log.
- `name                     = var.name`: `name`: The name of this thing in Azure. Here: the input variable `name` (Account name: 3 to 24 lowercase letters and digits, no hyphens, globally unique).
- `resource_group_name      = var.resource_group_name`: `resource_group_name`: The resource group the thing is created in. Here: the input variable `resource_group_name` (Resource group that holds the account).
- `location                 = var.location`: `location`: The Azure region (data center area) where the thing is created. Here: the input variable `location` (Azure region).
- `account_tier             = "Standard"`: `account_tier`: The performance tier of the storage account (`Standard` is the ordinary disk-based tier). Here: the text `"Standard"`.
- `account_replication_type = var.replication_type`: `account_replication_type`: How many copies of the data Azure keeps and where (`LRS` keeps three copies inside one data center). Here: the input variable `replication_type` (LRS keeps three copies in one datacenter: the cheapest, enough for practice).
- `account_kind             = "StorageV2"`: `account_kind`: The kind of storage account (`StorageV2` is the general-purpose current kind). Here: the text `"StorageV2"`.
- `tags                     = var.tags`: `tags`: Tags are name/value labels attached to the thing. They do not change behavior; they identify the owner, project and environment and make cost reports readable. Here: the input variable `tags` (Tags applied to the account).
- `# The identity is the only way in: account keys and SAS tokens signed with them stop working.`: A line starting with `#` (or `//`) is a **comment**: Terraform ignores it; it is there for the reader. Comment for the reader: The identity is the only way in: account keys and SAS tokens signed with them stop working.
- `shared_access_key_enabled       = false`: `shared_access_key_enabled`: When `false`, the account's master keys and key-signed tokens (SAS) stop working, so every request must carry an Entra ID token. Here: `false`.
- `default_to_oauth_authentication = true`: `default_to_oauth_authentication`: When `true`, tools default to Entra ID sign-in instead of account keys. Here: `true`.
- `local_user_enabled              = false`: `local_user_enabled`: Whether SFTP-style local users exist on the account. `false` removes that way in. Here: `false`.
- `allow_nested_items_to_be_public  = false`: `allow_nested_items_to_be_public`: When `false`, no blob or container in the account can be made publicly readable. Here: `false`.
- `public_network_access_enabled    = true`: `public_network_access_enabled`: Whether the service accepts connections from the public internet. `false` leaves only private endpoints. Here: `true`.
- `min_tls_version                  = "TLS1_2"`: `min_tls_version`: The oldest TLS (encryption protocol) version the service accepts. Here: the text `"TLS1_2"`.
- `https_traffic_only_enabled       = true`: `https_traffic_only_enabled`: When `true`, plain `http://` requests are refused; only encrypted `https://` is served. Here: `true`.
- `cross_tenant_replication_enabled = false`: `cross_tenant_replication_enabled`: Whether data may be copied to an account in another tenant. `false` blocks it. Here: `false`.

**Lines 26 to 34**

```hcl
  blob_properties {
    delete_retention_policy {
      days = var.soft_delete_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_days
    }
  }
}
```

- `blob_properties {`: Starts the nested `blob_properties` block: Settings for the blob service of the storage account.
- `delete_retention_policy {`: Starts the nested `delete_retention_policy` block: Keeps deleted blobs recoverable for some days.
- `days = var.soft_delete_days`: `days`: How many days the retention lasts. Here: the input variable `soft_delete_days` (Days deleted blobs and containers can be recovered).
- `container_delete_retention_policy {`: Starts the nested `container_delete_retention_policy` block: Keeps deleted containers recoverable for some days.
- `days = var.soft_delete_days`: `days`: How many days the retention lasts. Here: the input variable `soft_delete_days` (Days deleted blobs and containers can be recovered).
- Closing lines: `}` end the blocks opened above.

**Lines 36 to 43**

```hcl
# Created through the Azure Resource Manager API (storage_account_id), so Terraform needs no data-plane
# permission and no account key to make it.
resource "azurerm_storage_container" "uploads" {
  #checkov:skip=CKV2_AZURE_21:the blob service's read logs go to the workspace through azurerm_monitor_diagnostic_setting.blob; the check cannot follow the interpolated blobServices id
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
```

**New idea.** An **API** (application programming interface) is a way for one program to ask another to do something. A **REST** API does it with ordinary web requests: the program sends an HTTP request to an address and reads the answer, usually JSON.

**New idea.** **Log Analytics** is Azure's store for logs and metrics, queried with the Kusto Query Language (KQL). A *diagnostic setting* tells a resource to send its logs there, so that, for example, every refused request to a vault can be found afterwards.

- `# Created through the Azure Resource Manager API (storage_account_id), so Terraform needs no data-plane`: Comment for the reader: Created through the Azure Resource Manager API (storage_account_id), so Terraform needs no data-plane
- `# permission and no account key to make it.`: Comment for the reader: permission and no account key to make it.
- `resource "azurerm_storage_container" "uploads" {`: Declares the resource `azurerm_storage_container.uploads`. A **blob container** is a folder-like group of blobs (files) inside a storage account. Roles can be granted on one container, which is narrower than the whole account.
- `#checkov:skip=CKV2_AZURE_21:the blob service's read logs go to the workspace through azurerm_monitor_diagnosti`…: Scanner exception for rule `CKV2_AZURE_21`: the blob service's read logs go to the workspace through azurerm_monitor_diagnostic_setting.blob; the check cannot follow the interpolated blobServices id.
- `name                  = var.container_name`: `name`: The name of this thing in Azure. Here: the input variable `container_name` (The one container the app writes to).
- `storage_account_id    = azurerm_storage_account.this.id`: `storage_account_id`: The id of the storage account the container belongs to. Here: the `id` of the resource `azurerm_storage_account.this`.
- `container_access_type = "private"`: `container_access_type`: Who may read the container without signing in. `private` means nobody. Here: the text `"private"`.
- Closing line: `}` ends the block opened above.

**Lines 45 to 60**

```hcl
resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Read, write and delete carry the HTTP status and the error code of each denied call.
  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

- `resource "azurerm_monitor_diagnostic_setting" "blob" {`: Declares the resource `azurerm_monitor_diagnostic_setting.blob`. A **diagnostic setting** tells an Azure resource to send its logs and metrics to a destination, here a Log Analytics workspace.
- `name                       = "to-log-analytics"`: `name`: The name of this thing in Azure. Here: the text `"to-log-analytics"`.
- `target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"`: `target_resource_id`: The id of the Azure resource whose diagnostics are being routed. Here: text built from the pieces the `id` of the resource `azurerm_storage_account.this`. `${...}` inside a quoted string is **interpolation**: Terraform evaluates what is inside and puts its text into the string.
- `log_analytics_workspace_id = var.log_analytics_workspace_id`: `log_analytics_workspace_id`: The id of the Log Analytics workspace that receives the data. Here: the input variable `log_analytics_workspace_id` (Workspace that receives the blob logs).
- `# Read, write and delete carry the HTTP status and the error code of each denied call.`: Comment for the reader: Read, write and delete carry the HTTP status and the error code of each denied call.
- `enabled_log {`: Starts the nested `enabled_log` block: Selects one log category to send to the destination.
- `category = "StorageRead"`: `category`: The name of one log category to send (for example `AuditEvent`). Here: the text `"StorageRead"`.
- `enabled_log {`: Starts the nested `enabled_log` block: Selects one log category to send to the destination.
- `category = "StorageWrite"`: `category`: The name of one log category to send (for example `AuditEvent`). Here: the text `"StorageWrite"`.
- `enabled_log {`: Starts the nested `enabled_log` block: Selects one log category to send to the destination.
- `category = "StorageDelete"`: `category`: The name of one log category to send (for example `AuditEvent`). Here: the text `"StorageDelete"`.
- Closing lines: `}` end the blocks opened above.

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
