#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TinyTaskMac"
VERSION="${1:-0.1.0-preview}"
CHANNEL="${2:-preview}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
RELEASE_DIR="${ROOT_DIR}/.dist/releases/${VERSION}"
APP_DIR="${ROOT_DIR}/.dist/${APP_NAME}.app"
ZIP_PATH="${RELEASE_DIR}/${APP_NAME}.zip"
DMG_PATH="${RELEASE_DIR}/${APP_NAME}.dmg"
CHECKSUM_PATH="${RELEASE_DIR}/SHA256SUMS.txt"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

VERSION="${VERSION}" BUILD_NUMBER="${BUILD_NUMBER}" "${ROOT_DIR}/scripts/build_macos_app_bundle.sh"

ditto -c -k --keepParent --sequesterRsrc "${APP_DIR}" "${ZIP_PATH}"
hdiutil create -quiet -volname "${APP_NAME}" -srcfolder "${APP_DIR}" -ov -format UDZO "${DMG_PATH}"

if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" && -n "${CODESIGN_IDENTITY:-}" ]]; then
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARYTOOL_KEYCHAIN_PROFILE}" --wait
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler staple "${APP_DIR}"
fi

shasum -a 256 "${DMG_PATH}" "${ZIP_PATH}" > "${CHECKSUM_PATH}"

echo "Created ${CHANNEL} release artifacts in ${RELEASE_DIR}"
