#!/usr/bin/env bash
# Step 2 "Done when": an attempt to use a storage account key fails because shared key access is off.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login

ACCOUNT="$(tf_out storage_account_name)"
if output="$(az storage container list --account-name "$ACCOUNT" --auth-mode key 2>&1)"; then
  die "listing containers with an account key SUCCEEDED: shared key access is not disabled"
fi
grep -q "KeyBasedAuthenticationNotPermitted" <<<"$output" || die "the key request failed, but not with KeyBasedAuthenticationNotPermitted: $output"
log "OK: --auth-mode key is refused with KeyBasedAuthenticationNotPermitted"
