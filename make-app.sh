#!/bin/bash
# Build Reader.md and assemble a double-clickable .app bundle.
# Requires macOS with the Swift toolchain (Xcode or Command Line Tools).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Reader.md"
BUNDLE_ID="com.nahian.reader-md"

echo "Building release..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
EXE="${BIN_DIR}/ReaderMd"
APP="build/${APP_NAME}.app"

echo "Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${EXE}" "${APP}/Contents/MacOS/${APP_NAME}"

# SwiftPM resource bundle must sit next to the executable for Bundle.module.
for b in "${BIN_DIR}"/*.bundle; do
  [ -e "${b}" ] && cp -R "${b}" "${APP}/Contents/MacOS/"
done

# App icon: PNG -> .icns
ICON_SRC="Sources/ReaderMd/Resources/AppIcon.png"
if [ -f "${ICON_SRC}" ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "${ICONSET}"
  for size in 16 32 64 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SRC}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size*2))" "$((size*2))" "${ICON_SRC}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Done: ${APP}"
echo "Open with: open \"${APP}\""
