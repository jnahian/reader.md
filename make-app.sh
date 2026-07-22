#!/bin/bash
# Build Reader.md and assemble a double-clickable .app bundle.
# Requires macOS with the Swift toolchain (Xcode or Command Line Tools).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Reader.md"
BUNDLE_ID="com.nahian.reader-md"
# CFBundleVersion is what Sparkle compares; derive it from the build time so it's
# always monotonic — no manual bump, no silent "no update" from a stale integer.
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

echo "Building release..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
EXE="${BIN_DIR}/ReaderMd"
APP="build/${APP_NAME}.app"

echo "Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${EXE}" "${APP}/Contents/MacOS/${APP_NAME}"

# The `reader` CLI ships inside the bundle. It locates the app by walking up from
# its own executable path, so it must live at Contents/MacOS/reader — and it must
# be copied before codesign, since it's nested code that has to be sealed.
cp "${BIN_DIR}/reader" "${APP}/Contents/MacOS/reader"

# Bundle Sparkle.framework (auto-update) and point the binary at ../Frameworks.
SPARKLE_FW="$(find .build/artifacts/sparkle/Sparkle/Sparkle.xcframework -type d -name Sparkle.framework -path '*macos*' | head -1)"
mkdir -p "${APP}/Contents/Frameworks"
cp -R "${SPARKLE_FW}" "${APP}/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

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
  <key>CFBundleShortVersionString</key><string>1.13.0</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>https://github.com/jnahian/reader.md/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>tNhNMsfHkLZmnS/mTWYiAVIzYcj7yDjsHJWLgtB0Xe8=</string>
  <key>SUEnableAutomaticChecks</key><true/>
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
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
      <key>CFBundleURLSchemes</key>
      <array><string>readermd</string></array>
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

# Styled drag-to-Applications installer DMG. Native only (hdiutil + Finder via
# osascript, no create-dmg dep): build a read-write image, lay out the icons over
# a background picture, then convert to a compressed read-only .dmg.
DMG="build/${APP_NAME}.dmg"
RW="build/rw.dmg"
VOL="/Volumes/${APP_NAME}"

swift dmg-background.swift build/dmg-bg.png

rm -f "${DMG}" "${RW}"
hdiutil detach "${VOL}" >/dev/null 2>&1 || true
hdiutil create -size 100m -fs HFS+ -volname "${APP_NAME}" -ov "${RW}" >/dev/null
hdiutil attach "${RW}" -readwrite -noverify -noautoopen -mountpoint "${VOL}" >/dev/null

cp -R "${APP}" "${VOL}/"
ln -s /Applications "${VOL}/Applications"
mkdir "${VOL}/.background"
cp build/dmg-bg.png "${VOL}/.background/bg.png"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 1040, 500}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.png"
    set position of item "${APP_NAME}.app" of container window to {160, 205}
    set position of item "Applications" of container window to {480, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "${VOL}" >/dev/null
hdiutil convert "${RW}" -format UDZO -ov -o "${DMG}" >/dev/null
rm -f "${RW}"

echo "Done: ${APP}"
echo "Open with: open \"${APP}\""
echo "Share:    ${ZIP}"
echo "Installer: ${DMG}"
