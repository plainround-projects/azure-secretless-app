#!/usr/bin/env bash
# Step 4 "Done when": a search of the app's configuration and source finds no key, password or connection string.
# It looks for credential *values* (the word "key" appears in the secret's name, which is harmless).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform grep
require_login

PATTERN='AccountKey=|SharedAccessSignature=|[?&]sig=|DefaultEndpointsProtocol=|password=|pwd=|client_secret|-----BEGIN [A-Z ]*PRIVATE KEY'

APP="$(tf_out app_name)"
RG="$(tf_out resource_group_name)"
CONFIG="$(az containerapp show --resource-group "$RG" --name "$APP" --output json)"

log "environment variables of the deployed container (names and values)"
jq -r '.properties.template.containers[].env[] | "\(.name)=\(.value // "<secretRef " + (.secretRef // "") + ">")"' <<<"$CONFIG"

log "secrets defined on the app (must be empty)"
SECRETS="$(jq -r '.properties.configuration.secrets // [] | length' <<<"$CONFIG")"
[[ "$SECRETS" == "0" ]] || die "the app defines $SECRETS secret(s)"

if grep -Eq "$PATTERN" <<<"$CONFIG"; then die "the deployed configuration contains a credential-shaped value"; fi
log "OK: no credential-shaped value in the deployed configuration"

if grep -rEn "$PATTERN" "$ROOT/src" "$ROOT/requirements.lock" "$ROOT/Dockerfile" >/dev/null; then
  grep -rEn "$PATTERN" "$ROOT/src" "$ROOT/requirements.lock" "$ROOT/Dockerfile"
  die "the source contains a credential-shaped value"
fi
log "OK: no credential-shaped value in the source, the lock file or the Dockerfile"
