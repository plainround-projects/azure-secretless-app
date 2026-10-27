#!/usr/bin/env bash
# Phase 2 (lesson step 4): build the image inside the registry (no local Docker needed), then add the container app.
#   scripts/build-and-deploy.sh                    az acr build (ACR Tasks)
#   BUILD_MODE=local scripts/build-and-deploy.sh   docker build and push, for subscriptions where ACR Tasks is not allowed
#                                                  (some free-trial subscriptions)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform curl
require_login

REGISTRY="$(tf_out registry_name)"
LOGIN_SERVER="$(tf_out registry_login_server)"
IMAGE="$LOGIN_SERVER/azure-secretless-app:$APP_VERSION"

if [[ "${BUILD_MODE:-acr}" == "local" ]]; then
  need docker
  log "building $IMAGE locally and pushing it"
  az acr login --name "$REGISTRY"
  docker build --platform linux/amd64 --tag "$IMAGE" "$ROOT"
  docker push "$IMAGE"
else
  log "building $IMAGE in $REGISTRY"
  az acr build --registry "$REGISTRY" --image "azure-secretless-app:$APP_VERSION" "$ROOT"
fi

terraform -chdir="$TF_DIR" apply -input=false -auto-approve -var "deploy_app=true" -var "image=$IMAGE"

URL="$(tf_out app_url)"
log "waiting for $URL/live (a scaled-to-zero app needs a cold start)"
retry 20 10 curl --fail --silent --show-error "$URL/live" >/dev/null
log "app is up: $URL"
