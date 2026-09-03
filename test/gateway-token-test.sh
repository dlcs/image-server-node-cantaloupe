#!/usr/bin/env bash
#
# Exercises the X-Gateway-Token verification implemented by
# GatewayToken/pre_authorize in delegates.rb.
#
# The point of most of these cases is that a token is only good for one
# identifier and one time window: a proxy that signs the wrong thing, or an
# attacker replaying yesterday's header, must not get an image out.
#
# Usage:
#   test/gateway-token-test.sh [image-tag]     # default: dlcs-cantaloupe:local
#
# Fixtures are generated inside the image and passed around in a named volume,
# so there are no bind mounts and no host paths - it behaves the same on Linux
# CI and on Windows/Git Bash.
#
set -euo pipefail

IMAGE="${1:-dlcs-cantaloupe:local}"
RUN_ID="gateway-$$"
VOLUME="$RUN_ID-fixtures"
FAILURES=0

SECRET="primary-shared-secret"
SECONDARY="secondary-shared-secret"
# An hour-long window keeps the bucket arithmetic below well away from a
# rollover, so the "previous bucket" case can't flake into "two buckets ago".
WINDOW=3600

cleanup() {
  docker rm -f "$RUN_ID" >/dev/null 2>&1 || true
  docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Testing gateway token verification in $IMAGE"

# --- fixtures ---------------------------------------------------------------
# `nested/deep.jpg` is reached as the identifier `nested%2Fdeep.jpg`, which is
# what proves the encoded identifier survives routing and reaches the delegate
# byte-for-byte - the whole scheme rests on it.
echo "Generating fixtures ..."
docker volume create "$VOLUME" >/dev/null
docker run --rm --user root -v "$VOLUME:/out" --entrypoint bash "$IMAGE" -c '
set -euo pipefail
cd /out
mkdir -p nested
ffmpeg -v error -f lavfi -i "testsrc2=size=1200x800" -frames:v 1 -q:v 2 test.jpg -y
cp test.jpg nested/deep.jpg
chown -R cantaloupe:cantaloupe /out
' >/dev/null

# --- helpers ----------------------------------------------------------------
start_server() {
  docker rm -f "$RUN_ID" >/dev/null 2>&1 || true
  docker run -d --name "$RUN_ID" \
    -p 127.0.0.1::8182 \
    -e DELEGATE_SCRIPT_ENABLED=true \
    -e CACHE_SERVER_DERIVATIVE_ENABLED=false \
    -v "$VOLUME:/home/cantaloupe/images" \
    "$@" "$IMAGE" >/dev/null

  PORT=$(docker port "$RUN_ID" 8182/tcp | head -1 | sed 's/.*://')
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  echo "  ERROR: server did not come up"
  docker logs "$RUN_ID" 2>&1 | tail -20
  return 1
}

# token <secret> <identifier> [bucket-offset]
token() {
  local secret=$1 identifier=$2 offset=${3:-0} bucket
  bucket=$(( ($(date +%s) / WINDOW) + offset ))
  printf '%s' "orch|v1|${bucket}|${identifier}" \
    | openssl dgst -sha256 -hmac "$secret" -r \
    | cut -d' ' -f1
}

# check <description> <expected-status> <path> [curl-args...]
check() {
  local description=$1 expected=$2 path=$3
  shift 3
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' "$@" "http://127.0.0.1:$PORT$path")

  if [[ $status == "$expected" ]]; then
    printf '  ok    %-46s HTTP %s\n' "$description" "$status"
  else
    printf '  FAIL  %-46s expected HTTP %s, got %s\n' "$description" "$expected" "$status"
    FAILURES=$((FAILURES + 1))
  fi
}

IMG=test.jpg
IMAGE_REQUEST="/iiif/3/$IMG/full/!300,300/0/default.jpg"
INFO_REQUEST="/iiif/3/$IMG/info.json"
NESTED=nested%2Fdeep.jpg

# --- suite 1: no secret configured ------------------------------------------
# The feature is opt-in, so an existing deployment that sets no secret must
# behave exactly as it did before.
echo "Unconfigured (no GATEWAY_TOKEN_SECRET) ..."
start_server
check "image request without a token"      200 "$IMAGE_REQUEST"
check "info request without a token"       200 "$INFO_REQUEST"

# --- suite 2: secret configured ---------------------------------------------
echo "Configured with a single secret ..."
start_server \
  -e GATEWAY_TOKEN_SECRET="$SECRET" \
  -e GATEWAY_TOKEN_WINDOW_SECONDS="$WINDOW"

check "no token at all"                    403 "$IMAGE_REQUEST"
check "empty token"                        403 "$IMAGE_REQUEST" -H "X-Gateway-Token;"
check "garbage token"                      403 "$IMAGE_REQUEST" -H "X-Gateway-Token: not-a-digest"
check "token signed with the wrong secret" 403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token wrong-secret "$IMG")"
check "token signed for another image"     403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" other.jpg)"
check "token from two buckets ago"         403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG" -2)"
check "token from two buckets ahead"       403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG" 2)"
check "secondary secret, not configured"   403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECONDARY" "$IMG")"

check "valid token, image request"         200 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG")"
check "valid token, info request"          200 "$INFO_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG")"
check "valid token, lowercase header name" 200 "$IMAGE_REQUEST" \
  -H "x-gateway-token: $(token "$SECRET" "$IMG")"
check "valid token, uppercase digest"      403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG" | tr 'a-f' 'A-F')"
# The two adjacent buckets are accepted so that a clock a little out in either
# direction doesn't start failing requests near the window boundary.
check "valid token from previous bucket"   200 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG" -1)"
check "valid token from next bucket"       200 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG" 1)"

# The identifier is signed exactly as it appears in the path, so the token has
# to be computed over the percent-encoded form.
check "encoded identifier, token over raw" 200 "/iiif/3/$NESTED/full/!300,300/0/default.jpg" \
  -H "X-Gateway-Token: $(token "$SECRET" "$NESTED")"
check "encoded identifier, token decoded"  403 "/iiif/3/$NESTED/full/!300,300/0/default.jpg" \
  -H "X-Gateway-Token: $(token "$SECRET" nested/deep.jpg)"

# Endpoints that never invoke pre_authorize(), and so must stay reachable for
# load-balancer health checks and administration.
check "health endpoint, no token"          200 "/health"
check "IIIF 2 endpoint is also guarded"    403 "/iiif/2/$IMG/info.json"
check "IIIF 2 with a valid token"          200 "/iiif/2/$IMG/info.json" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG")"

# --- suite 3: rotation ------------------------------------------------------
# Both secrets are accepted at once, which is what lets Cantaloupe be restarted
# ahead of Orchestrator during a key change.
echo "Configured with primary + secondary secret ..."
start_server \
  -e GATEWAY_TOKEN_SECRET="$SECRET" \
  -e GATEWAY_TOKEN_SECRET_SECONDARY="$SECONDARY" \
  -e GATEWAY_TOKEN_WINDOW_SECONDS="$WINDOW"

check "primary secret"                     200 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG")"
check "secondary secret"                   200 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECONDARY" "$IMG")"
check "a third, unconfigured secret"       403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token retired-secret "$IMG")"

# --- suite 4: window mismatch -----------------------------------------------
# A window that doesn't match Orchestrator's fails closed rather than open.
echo "Window mismatch ..."
start_server \
  -e GATEWAY_TOKEN_SECRET="$SECRET" \
  -e GATEWAY_TOKEN_WINDOW_SECONDS=60

check "token signed with a 3600s window"   403 "$IMAGE_REQUEST" \
  -H "X-Gateway-Token: $(token "$SECRET" "$IMG")"

echo
if [[ $FAILURES -gt 0 ]]; then
  echo "$FAILURES gateway token check(s) FAILED"
  exit 1
fi
echo "All gateway token checks passed"
