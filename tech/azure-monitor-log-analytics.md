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
