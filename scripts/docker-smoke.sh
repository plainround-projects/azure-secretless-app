#!/usr/bin/env bash
# Run the built image with the in-memory backend and call it: proves the image starts as a non-root user,
# answers /live and /health, accepts an upload and refuses a bad name.
#   scripts/docker-smoke.sh <image>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need docker curl

IMAGE="${1:?usage: docker-smoke.sh <image>}"
NAME="secretless-smoke-$$"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$NAME" -e BACKEND=memory -p 127.0.0.1::8000 "$IMAGE" >/dev/null
PORT="$(docker port "$NAME" 8000/tcp | head -1 | sed 's/.*://')"
retry 20 1 curl --fail --silent "http://127.0.0.1:$PORT/live" >/dev/null

log "user inside the container: $(docker exec "$NAME" id -un) (uid $(docker exec "$NAME" id -u))"
[[ "$(docker exec "$NAME" id -u)" != "0" ]] || die "the container runs as root"

curl --fail --silent "http://127.0.0.1:$PORT/health"; echo
curl --fail --silent -X POST --data-binary 'hello' "http://127.0.0.1:$PORT/upload/hello.txt"; echo
STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST --data-binary x "http://127.0.0.1:$PORT/upload/.hidden")"
[[ "$STATUS" == "400" ]] || die "expected 400 for a bad name, got $STATUS"
docker stop --time 20 "$NAME" >/dev/null
EXIT_CODE="$(docker inspect "$NAME" --format '{{.State.ExitCode}}')"
[[ "$EXIT_CODE" == "0" ]] || die "the container exited with $EXIT_CODE after SIGTERM (expected a graceful 0)"
log "OK: image works, runs as non-root and shuts down gracefully"
