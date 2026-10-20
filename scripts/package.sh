#!/usr/bin/env bash
set -euo pipefail

# Build a self-contained Zigine distribution on the current platform.
# Cross-compiling the editor binary is supported by Zig, but the bundled Zig
# compiler must match the platform it runs on. Build this script natively on
# each release OS (or provide ZIGINE_RUNTIME_ZIG and ZIGINE_RUNTIME_LIB_DIR).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_TARGET="$(zig env | awk -F'"' '/\.target =/ { print $2; exit }' | cut -d. -f1)"
TARGET="${1:-${DEFAULT_TARGET}}"
VERSION="${ZIGINE_VERSION:-dev}"
OUT_DIR="${ROOT_DIR}/dist/zigine-${TARGET}"
ARCHIVE="${ROOT_DIR}/dist/zigine-${TARGET}.tar.gz"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/bin" "${OUT_DIR}/lib" "${OUT_DIR}/templates" "${OUT_DIR}/assets"

if [[ $# -eq 0 ]]; then
    zig build -Doptimize=ReleaseSafe
else
    zig build -Dtarget="${TARGET}" -Doptimize=ReleaseSafe
fi

ZIG_RUNTIME_BIN="${ZIGINE_RUNTIME_ZIG:-$(command -v zig)}"
ZIG_RUNTIME_LIB="${ZIGINE_RUNTIME_LIB_DIR:-$(zig env | awk -F'"' '/\.lib_dir =/ { print $2; exit }')}"

if [[ -z "${ZIG_RUNTIME_BIN}" || ! -f "${ZIG_RUNTIME_BIN}" ]]; then
    echo "Could not locate the Zig runtime executable." >&2
    exit 1
fi
if [[ -z "${ZIG_RUNTIME_LIB}" || ! -d "${ZIG_RUNTIME_LIB}" ]]; then
    echo "Could not locate the Zig runtime library directory." >&2
    exit 1
fi

cp "${ROOT_DIR}/zig-out/bin/zigine" "${OUT_DIR}/bin/zigine"
cp "${ZIG_RUNTIME_BIN}" "${OUT_DIR}/bin/zig"
cp -R "${ZIG_RUNTIME_LIB}" "${OUT_DIR}/lib/zig"
cp -R "${ROOT_DIR}/templates/sdl3" "${OUT_DIR}/templates/sdl3"
cp -R "${ROOT_DIR}/templates/raylib" "${OUT_DIR}/templates/raylib"
cp -R "${ROOT_DIR}/assets/." "${OUT_DIR}/assets/" 2>/dev/null || true

cat > "${OUT_DIR}/README.txt" <<EOF
Zigine ${VERSION} (${TARGET})

Run ./bin/zigine to start the editor.
The bundled Zig compiler is used by the embedded terminal and project runner.
SDL3 and raylib project templates are in templates/.
EOF

mkdir -p "${ROOT_DIR}/dist"
rm -f "${ARCHIVE}"
tar -C "${ROOT_DIR}/dist" -czf "${ARCHIVE}" "zigine-${TARGET}"
echo "Created ${ARCHIVE}"
