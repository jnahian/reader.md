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

# Copy resources into Contents/Resources (standard, signable). Bundle.resources
# loads them via Bundle.main there. Placing the SwiftPM .bundle at the .app root
# (where Bundle.module looks) is unsignable — codesign rejects contents at root.
for b in "${BIN_DIR}"/*.bundle; do
  [ -e "${b}" ] && cp -R "${b}"/* "${APP}/Contents/Resources/"
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
  <key>CFBundleShortVersionString</key><string>1.3.1</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown Document</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Default</string>
      <key>LSItemContentTypes</key>
      <array><string>net.daringfireball.markdown</string></array>
    </dict>
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
      <key>UTTypeDescription</key><string>Markdown Document</string>
      <key>UTTypeConformsTo</key>
      <array><string>public.plain-text</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array><string>md</string><string>markdown</string><string>mdown</string><string>mdx</string></array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc sign so a quarantined copy isn't rejected as "damaged" on other Macs.
# ponytail: ad-hoc (-) is free/no Developer ID; teammates still right-click→Open once.
codesign --force --deep --sign - "${APP}"
codesign --verify --deep --strict "${APP}"

# Zip for sharing. ditto preserves the bundle so it double-clicks on arrival.
# No Developer ID here, so teammates clear quarantine once — see README.
ZIP="build/${APP_NAME}.zip"
rm -f "${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "Done: ${APP}"
echo "Open with: open \"${APP}\""
echo "Share:    ${ZIP}"
