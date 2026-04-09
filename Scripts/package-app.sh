#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ReleaseWatcher"
CONFIGURATION="release"
BINARY_PATH=".build/arm64-apple-macosx/${CONFIGURATION}/${APP_NAME}"
APP_DIR="dist/${APP_NAME}.app"
RAW_VERSION="${GITHUB_REF_NAME:-0.1.0}"
APP_VERSION="${RAW_VERSION#v}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCE_DIR="${CONTENTS_DIR}/Resources"
ZIP_PATH="dist/${APP_NAME}.zip"
SIGN_IDENTITY="-"

rm -rf dist
mkdir -p "${MACOS_DIR}" "${RESOURCE_DIR}"

swift build -c "${CONFIGURATION}"
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.alvarosanchez.ReleaseWatcher</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${GITHUB_RUN_NUMBER:-1}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"
echo "Packaged ${ZIP_PATH}"
