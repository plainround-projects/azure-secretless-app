#!/usr/bin/env bash
# Steps 3 and 4 "Done when": exactly two narrow role assignments, a working app, an upload in the container.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform curl
require_login

URL="$(tf_out app_url)"
PRINCIPAL="$(tf_out app_identity_principal_id)"
ACCOUNT="$(tf_out storage_account_name)"
CONTAINER="$(tf_out container_name)"

log "role assignments of the app identity (exactly two, each on one resource)"
az role assignment list --assignee "$PRINCIPAL" --all --query '[].{role:roleDefinitionName, scope:scope}' --output table
COUNT="$(az role assignment list --assignee "$PRINCIPAL" --all --query 'length(@)' --output tsv)"
[[ "$COUNT" == "2" ]] || die "expected 2 role assignments, found $COUNT"

log "GET /health"
curl --fail --silent --show-error "$URL/health"; echo

FILE="$(mktemp)"
trap 'rm -f "$FILE"' EXIT
echo "hello from the secretless app" >"$FILE"
log "POST /upload/hello.txt"
curl --fail --silent --show-error -X POST --data-binary "@$FILE" "$URL/upload/hello.txt"; echo

log "blobs in the container (listed with your own login, no key)"
az storage blob list --account-name "$ACCOUNT" --container-name "$CONTAINER" --auth-mode login --query '[].name' --output json
