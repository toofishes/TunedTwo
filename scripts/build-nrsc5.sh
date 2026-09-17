#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NRSC5_DIR="${ROOT_DIR}/Vendor/nrsc5"
BUILD_DIR="${NRSC5_DIR}/build"

echo "[build-nrsc5] Building libnrsc5 in ${BUILD_DIR}..."

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake -DUSE_SSE=ON -DBUILD_CLI=OFF -DCMAKE_BUILD_TYPE=Release "${NRSC5_DIR}"
make -j"$(sysctl -n hw.ncpu)"

# Ensure the dynamic library has an @rpath-based install name so it can be
# embedded in the app bundle without absolute paths.
DYLIB="${BUILD_DIR}/src/libnrsc5.dylib"
if [[ -f "${DYLIB}" ]]; then
    install_name_tool -id "@rpath/libnrsc5.dylib" "${DYLIB}" || true
fi

echo "[build-nrsc5] Done. Built: ${DYLIB}"
