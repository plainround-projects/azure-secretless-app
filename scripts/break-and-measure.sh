#!/usr/bin/env bash
# Step 5: remove one role, time how long until the app is refused, restore it, time how long until it recovers.
#   scripts/break-and-measure.sh blob     removes Storage Blob Data Contributor (watch POST /upload)
#   scripts/break-and-measure.sh vault    removes Key Vault Secrets User (watch GET /health)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform curl
require_login

TARGET="${1:-}"
URL="$(tf_out app_url)"
PRINCIPAL="$(tf_out app_identity_principal_id)"
ACCOUNT="$(tf_out storage_account_name)"
VAULT="$(tf_out key_vault_name)"
RG="$(tf_out resource_group_name)"

case "$TARGET" in
  blob)
    ROLE="Storage Blob Data Contributor"
    SCOPE="$(az storage account show --name "$ACCOUNT" --resource-group "$RG" --query id --output tsv)/blobServices/default/containers/$(tf_out container_name)"
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' -X POST --data-binary "probe" "$URL/upload/probe.txt"; }
    expect_ok=201
    ;;
  vault)
    ROLE="Key Vault Secrets User"
    SCOPE="$(az keyvault show --name "$VAULT" --query id --output tsv)"
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' "$URL/health"; }
    expect_ok=200
    ;;
  *) die "usage: $0 blob|vault" ;;
esac

[[ "$(probe)" == "$expect_ok" ]] || die "the app does not work before the break; run scripts/smoke.sh first"

wait_for() { # wait_for <description> <predicate: "refused" or "ok">
  local start end status
  start=$(date +%s)
  while true; do
    status="$(probe || true)"
    if [[ "$2" == "refused" && "$status" == "502" ]] || [[ "$2" == "ok" && "$status" == "$expect_ok" ]]; then break; fi
    sleep 10
  done
  end=$(date +%s)
  log "$1: $((end - start)) seconds (last status $status)"
}

log "removing '$ROLE' at $SCOPE"
az role assignment delete --assignee "$PRINCIPAL" --role "$ROLE" --scope "$SCOPE"
wait_for "removal to first refused request" refused

log "restoring the role"
az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "$ROLE" --scope "$SCOPE" --output none
wait_for "restore to first successful request" ok

log "Write both numbers into docs/RUNBOOK.md (propagation table). Now read the denial: scripts/read-denials.sh $TARGET"
log "Note: terraform state still lists this assignment; 'terraform apply' reports no change because the role is back."
