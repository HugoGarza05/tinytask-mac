#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TinyTaskMac"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_DIR="${ROOT_DIR}/.dist/${APP_NAME}.app"
EXECUTABLE_PATH="${ROOT_DIR}/.build/${CONFIGURATION}/${APP_NAME}"
INFO_PLIST="${ROOT_DIR}/packaging/macos/AppHost/Info.plist"
ICNS_PATH="${ROOT_DIR}/packaging/macos/AppHost/Resources/AppIcon.icns"

mkdir -p "${ROOT_DIR}/.dist"

if [[ ! -f "${ICNS_PATH}" ]]; then
  "${ROOT_DIR}/scripts/generate_app_icon.sh"
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

if [[ "${USE_XCODEGEN_APP_TARGET:-0}" == "1" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required when USE_XCODEGEN_APP_TARGET=1" >&2
    exit 1
  fi

  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Full Xcode is required when USE_XCODEGEN_APP_TARGET=1" >&2
    exit 1
  fi

  pushd "${ROOT_DIR}/packaging/xcodegen" >/dev/null
  xcodegen generate
  popd >/dev/null

  DERIVED_DATA="${ROOT_DIR}/.dist/DerivedData"
  xcodebuild \
    -project "${ROOT_DIR}/packaging/xcodegen/TinyTaskMac.xcodeproj" \
    -scheme TinyTaskMacApp \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    build

  cp -R "${DERIVED_DATA}/Build/Products/Release/TinyTaskMac.app" "${APP_DIR}"
else
  swift build -c "${CONFIGURATION}" --product "${APP_NAME}"
  cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
  cp "${INFO_PLIST}" "${APP_DIR}/Contents/Info.plist"

  if [[ -f "${ICNS_PATH}" ]]; then
    cp "${ICNS_PATH}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
  fi
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_DIR}/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
fi

echo "Built app bundle at ${APP_DIR}"
