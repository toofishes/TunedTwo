#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="${ROOT_DIR}/Vendor/nrsc5/support/sample.xz"
DEST="${ROOT_DIR}/Resources/sample.bin"

if [[ ! -f "${SOURCE}" ]]; then
    echo "[prepare-sample] sample.xz not found at ${SOURCE}"
    exit 1
fi

if [[ -f "${DEST}" ]] && [[ "${DEST}" -nt "${SOURCE}" ]]; then
    echo "[prepare-sample] sample.bin is up to date"
    exit 0
fi

echo "[prepare-sample] Extracting sample.xz -> sample.bin..."
mkdir -p "$(dirname "${DEST}")"
xz -d -c "${SOURCE}" > "${DEST}"
echo "[prepare-sample] Done: ${DEST}"
