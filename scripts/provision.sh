#!/usr/bin/env bash
# Phase 1 (lesson steps 1 to 3): resource group, workspace, identities, vault, storage, registry, role assignments,
# budget. The container app comes in phase 2 (build-and-deploy.sh) because its image must exist first.
#
#   BUDGET_EMAIL=you@example.com scripts/provision.sh [--yes]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login

AUTO_APPROVE=""
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE="-auto-approve"

# Register the resource providers once, so the Terraform plan never changes subscription-wide settings itself.
for provider in Microsoft.App Microsoft.ContainerRegistry Microsoft.Consumption Microsoft.Insights \
  Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Storage; do
  log "registering $provider"
  az provider register --namespace "$provider" --wait >/dev/null
done

TFVARS="$TF_DIR/terraform.tfvars"
if [[ ! -f "$TFVARS" ]]; then
  [[ -n "${BUDGET_EMAIL:-}" ]] || die "set BUDGET_EMAIL=you@example.com (lesson step 1: a budget alert), or write $TFVARS yourself"
  log "writing $TFVARS from your az session (it holds ids, so it is git-ignored)"
  cat >"$TFVARS" <<TFVARS_EOF
subscription_id       = "$(az account show --query id --output tsv)"
tenant_id             = "$(az account show --query tenantId --output tsv)"
deployer_object_id    = "$(az ad signed-in-user show --query id --output tsv)"
budget_contact_emails = ["$BUDGET_EMAIL"]
budget_start_date     = "$(date -u +%Y-%m-01T00:00:00Z)"
TFVARS_EOF
fi

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false $AUTO_APPROVE

"$ROOT/scripts/seed-secret.sh"
"$ROOT/scripts/prove-key-access-closed.sh"
log "phase 1 done. Next: scripts/build-and-deploy.sh"
