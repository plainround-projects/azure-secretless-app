#!/usr/bin/env bash
# Step 5 "Done when": find the denial in the logs, with the identity and the missing permission named.
# Logs reach the workspace a few minutes after the event. The queries are the ones in docs/RUNBOOK.md.
#   scripts/read-denials.sh blob | vault | app
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login

WORKSPACE="$(tf_out log_analytics_customer_id)"
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

log "the app identity's object id is $(tf_out app_identity_principal_id); it should appear as the caller"
az monitor log-analytics query --workspace "$WORKSPACE" --analytics-query "$QUERY" --output table
