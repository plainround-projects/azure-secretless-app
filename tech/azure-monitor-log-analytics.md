# Log Analytics and diagnostic settings

*Where the denials are read. Pinned here: Log Analytics PerGB2018, 30-day retention.*

## What it is

A **Log Analytics workspace** is a store for logs that you can query. **Diagnostic settings** tell an Azure resource to send its logs and metrics to a workspace. **Kusto Query Language (KQL)** is the language you use to ask the workspace questions. **Azure Monitor** also has **alert rules** that send a message when a condition holds.

## Why this repository uses it

The lesson's step 5 ends with finding both denials in logs, naming the identity and the missing permission.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/modules/log_analytics/` | The workspace. |
| `infra/modules/key_vault/main.tf` | Vault `AuditEvent` log. |
| `infra/modules/storage_uploads/main.tf` | Blob service logs. |
| `infra/modules/container_app/main.tf` | The environment's console logs. |
| `scripts/read-denials.sh` | The three queries. |

## How it works underneath

Each service has named **log categories**. Key Vault's `AuditEvent` records every data-plane call. Storage has `StorageRead`, `StorageWrite` and `StorageDelete`. Service Bus has `OperationalLogs`. A diagnostic setting picks categories and a destination. Logs land in the workspace a few minutes after they happen, in tables such as `AzureDiagnostics` or `StorageBlobLogs`.

A KQL query is a pipeline: `Table | where Status == 403 | project TimeGenerated, Caller | order by TimeGenerated desc`. The `|` passes the rows to the next step. A **metric alert** watches a number (for example the dead-letter message count) and fires when it passes a threshold, notifying an **action group** (an email list).

The workspace's first 5 GB of ingestion each month are free on the pay-as-you-go tier; retention beyond 30 days costs extra.

## Walkthrough of this repository's use

```bash
case "${1:-}" in
  blob)
    QUERY='StorageBlobLogs
| where StatusCode == 403
| project TimeGenerated, OperationName, StatusText, RequesterObjectId, AuthenticationType, Uri
| order by TimeGenerated desc | take 10' ;;
  vault)
    QUERY='AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT" and httpStatusCode_d == 403
| project TimeGenerated, OperationName, ResultSignature, identity_claim_oid_g, requestUri_s, CallerIPAddress
| order by TimeGenerated desc | take 10' ;;
  app)
    QUERY='ContainerAppConsoleLogs_CL
| where Log_s has "access denied"
| project TimeGenerated, Log_s
| order by TimeGenerated desc | take 10' ;;
  *) die "usage: $0 blob|vault|app" ;;
esac
```

Three KQL queries. For storage, `StorageBlobLogs | where StatusCode == 403` shows `RequesterObjectId`, the identity's principal id. For the vault, `AzureDiagnostics | where ResourceProvider == "MICROSOFT.KEYVAULT" and httpStatusCode_d == 403` shows the caller's object id in `identity_claim_oid_g`. For the app, `ContainerAppConsoleLogs_CL | where Log_s has "access denied"` finds the app's own error line, whose JSON holds the SDK's message.

These column names are the documented ones and were not run against a live workspace; adjust them in the portal's Logs view if a query reports an unknown column.

```hcl
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}
```

`sku = "PerGB2018"` is the pay-per-GB tier; `retention_in_days` defaults to 30 (the free retention).

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `infra/modules/log_analytics/main.tf`

8 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 8**

```hcl
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** **Log Analytics** is Azure's store for logs and metrics, queried with the Kusto Query Language (KQL). A *diagnostic setting* tells a resource to send its logs there, so that, for example, every refused request to a vault can be found afterwards.

**New idea.** An Azure **resource group** is a folder-like container for the resources of one project. Resources in a group share a life cycle: deleting the group deletes everything in it.

**New idea.** **Tags** are name/value labels attached to Azure resources. They change no behavior; they record the owner, project and environment and make cost reports and clean-up possible.

**New idea.** An Azure **region** (such as `westeurope`) is a group of data centers in one geographic area. Where a resource is created decides its latency, its price and which legal rules apply.

- `resource "azurerm_log_analytics_workspace" "this" {`: A `resource` block declares one real thing Terraform must create and keep in step with this file. It has two labels: the **type** (such as `azurerm_key_vault`, which names the provider and the kind of thing) and a **local name** (such as `this`) used only to refer to it from other places as `azurerm_key_vault.this`. The lines inside are the thing's settings, called **arguments**. Declares the resource `azurerm_log_analytics_workspace.this`. A **Log Analytics workspace** is Azure's store for logs and metrics. Other resources send their diagnostics here, and you query it with the Kusto query language (KQL).
- `name                = var.name`: `name`: The name of this thing in Azure. Here: the input variable `name` (Workspace name, for example law-secretless).
- `resource_group_name = var.resource_group_name`: `resource_group_name`: The resource group the thing is created in. Here: the input variable `resource_group_name` (Resource group that holds the workspace).
- `location            = var.location`: `location`: The Azure region (data center area) where the thing is created. Here: the input variable `location` (Azure region).
- `sku                 = "PerGB2018"`: `sku`: The pricing tier / capability level (the SKU) of the service. Here: the text `"PerGB2018"`.
- `retention_in_days   = var.retention_in_days`: `retention_in_days`: How many days the workspace keeps data before deleting it. Here: the input variable `retention_in_days` (How long logs stay queryable. 30 days is the free retention of the PerGB2018 tier).
- `tags                = var.tags`: `tags`: Tags are name/value labels attached to the thing. They do not change behavior; they identify the owner, project and environment and make cost reports readable. Here: the input variable `tags` (Tags applied to the workspace).
- Closing line: `}` ends the block opened above.

## Try it yourself

Run the workspace tests.

```bash
cd infra/modules/log_analytics && terraform init -backend=false -input=false >/dev/null && terraform test 2>&1 | tail -4
```

You should see something like this:

```text
tests/log_analytics.tftest.hcl... tearing down
tests/log_analytics.tftest.hcl... pass

Success! 2 passed, 0 failed.
```

See which log categories are turned on.

```bash
grep -n 'enabled_log' -A2 infra/modules/key_vault/main.tf infra/modules/storage_uploads/main.tf | head -14
```

You should see something like this:

```text
infra/modules/key_vault/main.tf:28:  enabled_log {
infra/modules/key_vault/main.tf-29-    category = "AuditEvent"
infra/modules/key_vault/main.tf-30-  }
--
infra/modules/storage_uploads/main.tf:51:  enabled_log {
infra/modules/storage_uploads/main.tf-52-    category = "StorageRead"
infra/modules/storage_uploads/main.tf-53-  }
infra/modules/storage_uploads/main.tf:54:  enabled_log {
infra/modules/storage_uploads/main.tf-55-    category = "StorageWrite"
infra/modules/storage_uploads/main.tf-56-  }
infra/modules/storage_uploads/main.tf:57:  enabled_log {
infra/modules/storage_uploads/main.tf-58-    category = "StorageDelete"
infra/modules/storage_uploads/main.tf-59-  }
```

## Mistakes people make

- Querying right after an event and finding nothing: ingestion has a delay.
- Forgetting to enable the category you need; no category, no log.
- Assuming column names. Check the table's schema in the portal; the queries in the runbook were not run against a live workspace.
- Sending logs nowhere. A denial that is not logged cannot be investigated.
- Alerts with no recipients: nobody is told.

## Check yourself

1. **What is a diagnostic setting?**
   Answer: A configuration that sends a resource's logs and metrics to a destination such as a workspace.

2. **What does `AuditEvent` record?**
   Answer: Each data-plane request to a vault, including denials.

3. **What does `|` do in KQL?**
   Answer: Passes the rows of one step to the next.

4. **Why can a fresh query be empty?**
   Answer: Logs arrive in the workspace some minutes after the event.

5. **What is an action group?**
   Answer: The list of recipients and actions that an alert notifies.

## Further reading

- Log Analytics: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview
- KQL: https://learn.microsoft.com/en-us/kusto/query/
- Diagnostic settings: https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/diagnostic-settings
- Metric alerts: https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-metric-overview
