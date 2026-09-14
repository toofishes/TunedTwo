#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP="${ROOT_DIR}/DerivedData/Build/Products/Debug/TunedTwo.app"
BINARY="${APP}/Contents/MacOS/TunedTwo"

if [[ ! -d "${APP}" ]]; then
    echo "[smoke-test] App not built. Building now..."
    xcodebuild -project "${ROOT_DIR}/TunedTwo.xcodeproj" -scheme TunedTwo -configuration Debug -derivedDataPath "${ROOT_DIR}/DerivedData" build
fi

echo "[smoke-test] Running TunedTwo in smoke-test mode..."
TUNEDTWO_SMOKE_TEST=1 "${BINARY}" 2>&1 | tee /tmp/tunedtwo-smoke.log &
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
