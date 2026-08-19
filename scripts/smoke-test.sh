#!/usr/bin/env bash
set -euo pipefail

# Black-box smoke test: runs the already-built container image and verifies
# it over real HTTP before tearing it down. See `make smoke-test` to build
# the image first.

IMAGE="${IMAGE_NAME:-rust-service}:${IMAGE_TAG:-dev}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"
CONTAINER_NAME="rust-service-smoke-$$"
PORT="${PORT:-8080}"
BASE_URL="http://localhost:${PORT}"

cleanup() {
  "$CONTAINER_ENGINE" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> starting $IMAGE as $CONTAINER_NAME ($CONTAINER_ENGINE)"
"$CONTAINER_ENGINE" run --rm -d --name "$CONTAINER_NAME" -p "${PORT}:8080" "$IMAGE" >/dev/null

echo "==> waiting for the service to become ready"
ready=false
for _ in $(seq 1 30); do
  if curl -sf "${BASE_URL}/healthz" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 0.5
done
if [ "$ready" != "true" ]; then
  echo "FAIL: service never became ready on ${BASE_URL}/healthz"
  "$CONTAINER_ENGINE" logs "$CONTAINER_NAME" || true
  exit 1
fi

check_status() {
  local path="$1" want="$2" got
  got=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}${path}")
  if [ "$got" != "$want" ]; then
    echo "FAIL: GET ${path} expected ${want}, got ${got}"
    exit 1
  fi
  echo "ok: GET ${path} -> ${got}"
}

check_status "/healthz" 200
check_status "/readyz" 200
check_status "/does-not-exist" 404

body=$(curl -sf "${BASE_URL}/")
case "$body" in
  *'"name":"rust-service"'*) echo "ok: GET / -> $body" ;;
  *) echo "FAIL: unexpected body from GET /: $body"; exit 1 ;;
esac

user=$("$CONTAINER_ENGINE" inspect "$CONTAINER_NAME" --format '{{.Config.User}}')
if [ "$user" != "65532:65532" ]; then
  echo "FAIL: expected container user 65532:65532 (distroless nonroot), got '${user}'"
  exit 1
fi
echo "ok: running as ${user}"

echo "==> all smoke tests passed"
