#!/usr/bin/env bash
#
# Exercises every processor bundled in the image, so a broken one is caught at
# build time rather than by whoever selects it for a customer.
#
# This matters because the failure mode is quiet: when a processor's native
# binary won't load, Cantaloupe logs a WARN and returns HTTP 200 with a
# zero-byte body, which caches happily. Checking the status code is not enough -
# every probe below asserts a plausible response size too.
#
# Usage:
#   test/smoke-test.sh [image-tag]      # default: dlcs-cantaloupe:local
#
# Fixtures are generated inside the image and passed around in a named volume,
# so there are no bind mounts and no host paths - it behaves the same on Linux
# CI and on Windows/Git Bash.
#
set -euo pipefail

IMAGE="${1:-dlcs-cantaloupe:local}"
RUN_ID="smoke-$$"
VOLUME="$RUN_ID-fixtures"
FAILURES=0

cleanup() {
  docker rm -f "$RUN_ID" >/dev/null 2>&1 || true
  docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Smoke-testing $IMAGE"

# --- fixtures ---------------------------------------------------------------
# Generated with the image's own ffmpeg/opj_compress so the repo stays free of
# binary test assets. The PDF is hand-written; nothing in the image creates one.
echo "Generating fixtures ..."
docker volume create "$VOLUME" >/dev/null
docker run --rm --user root -v "$VOLUME:/out" --entrypoint bash "$IMAGE" -c '
set -euo pipefail
cd /out
src="testsrc2=size=1200x800"
ffmpeg -v error -f lavfi -i "$src" -frames:v 1 -q:v 2 test.jpg -y
ffmpeg -v error -f lavfi -i "$src" -frames:v 1 test.png -y
ffmpeg -v error -f lavfi -i "$src" -frames:v 1 test.tif -y
ffmpeg -v error -f lavfi -i "testsrc2=size=640x480:rate=10" -t 2 -pix_fmt yuv420p test.mp4 -y
opj_compress -i test.png -o test.jp2 -r 20 >/dev/null

content="1 0 0 RG 0.2 0.4 0.9 rg 50 50 300 200 re f"
printf "%%PDF-1.4\n\
1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n\
2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n\
3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Contents 4 0 R /Resources << >> >>\nendobj\n\
4 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n\
trailer\n<< /Size 5 /Root 1 0 R >>\n%%%%EOF\n" "${#content}" "$content" > test.pdf

chown -R cantaloupe:cantaloupe /out
' >/dev/null

# --- helpers ----------------------------------------------------------------
start_server() {
  docker rm -f "$RUN_ID" >/dev/null 2>&1 || true
  docker run -d --name "$RUN_ID" \
    -p 127.0.0.1::8182 \
    -e CACHE_SERVER_DERIVATIVE_ENABLED=false \
    -v "$VOLUME:/home/cantaloupe/images" \
    "$@" "$IMAGE" >/dev/null

  PORT=$(docker port "$RUN_ID" 8182/tcp | head -1 | sed 's/.*://')
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/iiif/3" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  echo "  ERROR: server did not come up"
  docker logs "$RUN_ID" 2>&1 | tail -20
  return 1
}

# probe <fixture> <expected-processor>
probe() {
  local fixture=$1 expected=$2 body status actual

  body=$(mktemp)
  status=$(curl -s -o "$body" -w '%{http_code}' \
    "http://127.0.0.1:$PORT/iiif/3/$fixture/full/!300,300/0/default.jpg")
  local size
  size=$(wc -c < "$body" | tr -d ' ')
  rm -f "$body"

  actual=$(docker logs "$RUN_ID" 2>&1 \
    | grep -oE '[A-Za-z0-9]+Processor selected for format' \
    | tail -1 | awk '{print $1}')

  if [[ $status != 200 ]]; then
    printf '  FAIL  %-9s %-19s HTTP %s\n' "$fixture" "$expected" "$status"
    FAILURES=$((FAILURES + 1))
  elif [[ $size -lt 1000 ]]; then
    # the zero-byte-200 signature of a native library that failed to load
    printf '  FAIL  %-9s %-19s HTTP 200 but only %s bytes\n' "$fixture" "$expected" "$size"
    FAILURES=$((FAILURES + 1))
  elif [[ $actual != "$expected" ]]; then
    printf '  FAIL  %-9s %-19s fell back to %s\n' "$fixture" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  else
    printf '  ok    %-9s %-19s %s bytes\n' "$fixture" "$expected" "$size"
  fi
}

# --- suite 1 ----------------------------------------------------------------
echo "Grok / TurboJpeg / Java2d / PdfBox / Ffmpeg ..."
start_server \
  -e PROCESSOR_MANUALSELECTIONSTRATEGY_JP2=GrokProcessor \
  -e PROCESSOR_MANUALSELECTIONSTRATEGY_JPG=TurboJpegProcessor
probe test.jp2 GrokProcessor
probe test.jpg TurboJpegProcessor
probe test.png Java2dProcessor
probe test.tif Java2dProcessor
probe test.pdf PdfBoxProcessor
probe test.mp4 FfmpegProcessor

# --- suite 2 ----------------------------------------------------------------
# Processor choice is read at startup, so the alternatives need a second run.
echo "OpenJpeg / Jai ..."
start_server \
  -e PROCESSOR_MANUALSELECTIONSTRATEGY_JP2=OpenJpegProcessor \
  -e PROCESSOR_MANUALSELECTIONSTRATEGY_PNG=JaiProcessor \
  -e PROCESSOR_MANUALSELECTIONSTRATEGY_TIF=JaiProcessor
probe test.jp2 OpenJpegProcessor
probe test.png JaiProcessor
probe test.tif JaiProcessor

# KakaduNativeProcessor is deliberately not covered - it needs licensed binaries
# supplied at runtime via KAKADU_LOCATION.

echo
if [[ $FAILURES -gt 0 ]]; then
  echo "$FAILURES processor check(s) FAILED"
  exit 1
fi
echo "All processor checks passed"
