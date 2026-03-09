#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="${ROOT_DIR}/packaging/macos/AppHost/Resources"
ICONSET_DIR="${RESOURCES_DIR}/AppIcon.iconset"
ICNS_PATH="${RESOURCES_DIR}/AppIcon.icns"

mkdir -p "${RESOURCES_DIR}"
swift "${ROOT_DIR}/scripts/generate_app_icon.swift" "${ROOT_DIR}"
rm -f "${ICNS_PATH}"
iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
echo "Generated ${ICNS_PATH}"
