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
ICON_SOURCE="Assets/IconSource/icon.png"
APP_ICONSET_DIR="Assets/AppIcon.iconset"
LEGACY_APP_ICON_PATH="Assets/AppIcon-1024.png"
DIST_ICONSET_DIR="dist/${APP_NAME}.iconset"
ICON_FILE="${APP_NAME}.icns"
ICON_PATH="${RESOURCE_DIR}/${ICON_FILE}"
SIGN_IDENTITY="-"

rm -rf dist
rm -rf "${APP_ICONSET_DIR}"
mkdir -p "$(dirname "${LEGACY_APP_ICON_PATH}")"
mkdir -p "${MACOS_DIR}" "${RESOURCE_DIR}" "${APP_ICONSET_DIR}" "${DIST_ICONSET_DIR}"

swift build -c "${CONFIGURATION}"
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

generate_iconset() {
    local target_dir="$1"

    sips -z 16 16     "${ICON_SOURCE}" --out "${target_dir}/icon_16x16.png" >/dev/null
    sips -z 32 32     "${ICON_SOURCE}" --out "${target_dir}/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "${ICON_SOURCE}" --out "${target_dir}/icon_32x32.png" >/dev/null
    sips -z 64 64     "${ICON_SOURCE}" --out "${target_dir}/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "${ICON_SOURCE}" --out "${target_dir}/icon_128x128.png" >/dev/null
    sips -z 256 256   "${ICON_SOURCE}" --out "${target_dir}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "${ICON_SOURCE}" --out "${target_dir}/icon_256x256.png" >/dev/null
    sips -z 512 512   "${ICON_SOURCE}" --out "${target_dir}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "${ICON_SOURCE}" --out "${target_dir}/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "${ICON_SOURCE}" --out "${target_dir}/icon_512x512@2x.png" >/dev/null
}

cp "${ICON_SOURCE}" "${LEGACY_APP_ICON_PATH}"
generate_iconset "${APP_ICONSET_DIR}"
rm -rf "${DIST_ICONSET_DIR}"
cp -R "${APP_ICONSET_DIR}" "${DIST_ICONSET_DIR}"
iconutil -c icns "${DIST_ICONSET_DIR}" -o "${ICON_PATH}"

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
    <key>CFBundleIconFile</key>
    <string>${ICON_FILE}</string>
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
