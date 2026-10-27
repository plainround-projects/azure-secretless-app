#!/usr/bin/env bash
# Step 2: put the partner key in the vault. The value never enters Terraform state.
#   PARTNER_API_KEY=... scripts/seed-secret.sh        (default: the lesson's demo value)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login

VAULT="$(tf_out key_vault_name)"
VALUE="${PARTNER_API_KEY:-demo-value-123}"

# The deployer's Secrets Officer role was assigned seconds ago; Owner alone cannot write secrets, and the role can take
# a few minutes to apply, so retry on 403.
retry 12 30 az keyvault secret set --vault-name "$VAULT" --name partner-api-key --value "$VALUE" --output none
log "secret partner-api-key set in $VAULT (length ${#VALUE})"
