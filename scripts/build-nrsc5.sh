#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NRSC5_DIR="${ROOT_DIR}/Vendor/nrsc5"
BUILD_DIR="${NRSC5_DIR}/build"
STATIC_DIR="${BUILD_DIR}/static"

echo "[build-nrsc5] Building libnrsc5 in ${BUILD_DIR}..."

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake -DUSE_SSE=ON -DUSE_NEON=ON -DUSE_SYSTEM_FFTW=OFF -DUSE_SYSTEM_RTLSDR=OFF -DUSE_SYSTEM_LIBUSB=OFF -DBUILD_CLI=OFF -DCMAKE_BUILD_TYPE=Release "${NRSC5_DIR}"
make -j"$(sysctl -n hw.ncpu)"

# Build a single self-contained static archive that includes nrsc5 and all
# of its built-in dependencies (faad2, fftw, rtlsdr, libusb). This lets the
# Swift targets link one library and avoid dylib/rpath complexity.
mkdir -p "${STATIC_DIR}"
STATIC_LIB="${STATIC_DIR}/libnrsc5.a"
libtool -static -no_warning_for_no_symbols -o "${STATIC_LIB}" \
    "${BUILD_DIR}/src/libnrsc5_static.a" \
    "${BUILD_DIR}/faad2-prefix/lib/libfaad_hdc.a" \
    "${BUILD_DIR}/fftw-prefix/lib/libfftw3f.a" \
    "${BUILD_DIR}/rtlsdr-prefix/lib/librtlsdr.a" \
    "${BUILD_DIR}/libusb-prefix/lib/libusb-1.0.a"

echo "[build-nrsc5] Done. Built: ${STATIC_LIB}"
