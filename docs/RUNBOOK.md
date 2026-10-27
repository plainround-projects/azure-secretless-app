# Runbook: the secretless app

The lesson's step 5 and step 6 as an on-call page. Commands assume `scripts/` from the repository root and a signed-in `az` session.

## When a call from the app to Azure is refused

| Signal | Cause | Fix |
|---|---|---|
| `POST /upload` answers 502, body `code` is `AuthorizationPermissionMismatch`; the app log has `"level":"ERROR"` and `service":"blob"` | The app identity has no (or lost its) `Storage Blob Data Contributor` on the `uploads` container | List: `az role assignment list --assignee $(terraform -chdir=infra/environments/dev output -raw app_identity_principal_id) --all -o table`. Restore: `terraform -chdir=infra/environments/dev apply`. Then wait for propagation (table below) |
| `GET /health` answers 502, `code` is `ForbiddenByRbac` | The app identity has no `Key Vault Secrets User` on the vault | Same, for the vault scope |
| 502 with `code` `AuthenticationFailed` | The credential produced no token: wrong `AZURE_CLIENT_ID`, or the identity is not attached to the app | `az containerapp show -g rg-secretless -n ca-secretless --query identity`; compare with `terraform output app_identity_client_id` |
| 502 with `code` `SecretNotFound` / `ResourceNotFound` | The secret `partner-api-key` was never set, or was deleted | `scripts/seed-secret.sh` |
| 502 with `code` `Unreachable` | A network problem or a firewall on the vault or account | Check the vault and account network settings; this project leaves both open |
| `az storage ... --auth-mode key` fails with `KeyBasedAuthenticationNotPermitted` | Expected: shared key access is off | Use `--auth-mode login` and a data role |
| `az keyvault create` fails because the name is taken | A soft-deleted vault holds the name | `az keyvault list-deleted`, then `az keyvault purge --name NAME` (impossible with purge protection) or use a new suffix |
| Role assignment fails with `principal does not exist` | The client id was used where the principal (object) id is needed, or the identity was created seconds ago | Use `app_identity_principal_id`; Terraform sets `principal_type` and skips the directory lookup |

Where to read the denial (logs arrive a few minutes after the event): `scripts/read-denials.sh blob|vault|app`. The queries are:

```kusto
// Storage: the app identity's object id is RequesterObjectId
StorageBlobLogs
| where StatusCode == 403
| project TimeGenerated, OperationName, StatusText, RequesterObjectId, AuthenticationType, Uri
| order by TimeGenerated desc

// Key Vault
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT" and httpStatusCode_d == 403
| project TimeGenerated, OperationName, ResultSignature, identity_claim_oid_g, requestUri_s, CallerIPAddress
| order by TimeGenerated desc

// The app's own log line, with the SDK's message (caller object id and denied action)
ContainerAppConsoleLogs_CL
| where Log_s has "access denied"
| project TimeGenerated, Log_s
```

The column names above are the documented ones for these tables; they were not run against a live workspace when this repository was written, so if a query returns "failed to resolve column", open the table in the portal's Logs blade and adjust.

## Measured propagation (fill this in at step 5)

Run `scripts/break-and-measure.sh blob` and `vault`. The lesson saw between about one and five minutes.

| Role | Removal to first refused request (s) | Restore to first successful request (s) | Date |
|---|---|---|---|
| Storage Blob Data Contributor on the container | | | |
| Key Vault Secrets User on the vault | | | |

## Clean-up (step 6)

1. `make down`.
2. Read the soft-deleted vault line: with purge protection off, `az keyvault purge --name NAME` frees the name now; with it on, the name is reserved until the printed purge date.
3. `az group exists --name rg-secretless` must print `false`.
4. `az consumption budget list` must not list `budget-secretless`.
