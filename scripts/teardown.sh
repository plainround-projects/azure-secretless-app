#!/usr/bin/env bash
# Step 6: delete everything, then look at the soft-deleted vault and decide whether to purge it.
#   scripts/teardown.sh [--yes]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login

AUTO_APPROVE=""
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE="-auto-approve"

RG="$(tf_out resource_group_name)"
VAULT="$(tf_out key_vault_name)"

terraform -chdir="$TF_DIR" destroy -input=false $AUTO_APPROVE   # also removes the subscription-scoped budget

log "resource group $RG exists? -> $(az group exists --name "$RG")"
log "soft-deleted vaults (a deleted vault keeps its name reserved until scheduledPurgeDate):"
az keyvault list-deleted --query "[?name=='$VAULT'].{name:name, deleted:properties.deletionDate, purgeDate:properties.scheduledPurgeDate, purgeProtection:properties.purgeProtectionEnabled}" --output table

PROTECTED="$(az keyvault list-deleted --query "[?name=='$VAULT'].properties.purgeProtectionEnabled | [0]" --output tsv)"
if [[ "$PROTECTED" == "true" ]]; then
  log "purge protection is on: the name stays reserved until the date above and cannot be purged"
elif [[ -n "$PROTECTED" ]]; then
  log "purge protection is off: purging frees the name now"
  if [[ -n "$AUTO_APPROVE" ]]; then
    az keyvault purge --name "$VAULT"
  else
    log "run: az keyvault purge --name $VAULT"
  fi
fi
