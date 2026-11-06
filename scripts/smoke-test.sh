#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP="${ROOT_DIR}/build/TunedTwo.app"
BINARY="${APP}/Contents/MacOS/TunedTwo"

echo "[smoke-test] Building TunedTwo..."
make -C "${ROOT_DIR}" build

SAMPLE_FILE="${ROOT_DIR}/Resources/sample.bin"
make -C "${ROOT_DIR}" Resources/sample.bin

echo "[smoke-test] Running TunedTwo in smoke-test mode..."
TUNEDTWO_SAMPLE_FILE="${SAMPLE_FILE}" TUNEDTWO_SMOKE_TEST=1 "${BINARY}" 2>&1 | tee /tmp/tunedtwo-smoke.log &
PID=$!

# The app self-terminates after ~8 seconds, but guard against hangs.
wait $PID || true

if grep -q "SMOKE_OK" /tmp/tunedtwo-smoke.log; then
    echo "[smoke-test] PASS"
    grep "SMOKE_OK" /tmp/tunedtwo-smoke.log
    exit 0
else
    echo "[smoke-test] FAIL"
    tail -n 40 /tmp/tunedtwo-smoke.log
    exit 1
fi
