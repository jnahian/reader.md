#!/bin/bash
# Publish a release: upload the DMG and an informational appcast.xml to GitHub
# Releases under a v<version> tag, then point the Homebrew cask at it.
# Run ./make-app.sh first (bump the version in it), then ./release.sh.
# Requires: gh (authenticated).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Reader.md"
REPO="jnahian/reader.md"

APP="build/${APP_NAME}.app"
DMG="build/${APP_NAME}.dmg"
[ -f "${DMG}" ] || { echo "No ${DMG} — run ./make-app.sh first."; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
TAG="v${VERSION}"

# Installs still on Sparkle compare CFBundleVersion, not the display string. If it
# didn't increase past the published build, they see "no update". Refuse to
# publish in that case.
NEW_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
PUB_BUILD="$(curl -fsSL "https://github.com/${REPO}/releases/latest/download/appcast.xml" 2>/dev/null \
  | sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<.*/\1/p' | head -1 || true)"
if [ -n "${PUB_BUILD}" ] && [ "${NEW_BUILD}" -le "${PUB_BUILD}" ]; then
  echo "CFBundleVersion ${NEW_BUILD} must exceed the published ${PUB_BUILD}, or clients"
  echo "see no update. Bump CFBundleVersion in make-app.sh and rebuild."
  exit 1
fi

# Release notes, for the GitHub release page and the old installs' update prompt.
# The notes are the changelog's section for THIS version. A release whose version has
# no changelog entry is a mistake, not a release — refuse it, the same way we refuse a
# CFBundleVersion that didn't increase.
CHANGELOG="Sources/ReaderMd/Resources/docs/CHANGELOG.md"
# The heading is Keep a Changelog's "## [1.2.0] - 2026-07-21"; entries written
# before that format was adopted read "## 1.2.0 — 2026-07-21", so accept both.
NOTES="$(awk -v v="${VERSION}" '
  $0 ~ "^## \\[?" v "\\]?( |$|—|-)" { found = 1; next }   # skip the heading itself
  found && /^## / { exit }                                 # stop at the next version
  found { print }
' "${CHANGELOG}")"
if [ -z "$(printf '%s' "${NOTES}" | tr -d '[:space:]')" ]; then
  echo "No '## ${VERSION}' section in ${CHANGELOG}."
  echo "Sparkle's update prompt would show empty release notes, and the app's"
  echo "post-update What's New would show the previous version's. Add the entry first."
  exit 1
fi

STAGE="$(mktemp -d)"
NOTES_FILE="${STAGE}/${APP_NAME}.md"
printf '%s\n' "${NOTES}" > "${NOTES_FILE}"

# Installs from 1.23.0 and earlier still run Sparkle and fetch
# releases/latest/download/appcast.xml, so every release has to carry one for as
# long as those installs are out there. Sparkle's signing key is lost, so the item
# is informational: no enclosure, just a <link>. Sparkle then shows "available"
# with a Learn More button that opens the release page, and needs no signature
# (1.23.0 never set SURequireSignedFeed, so the feed itself isn't checked either).
RELEASE_PAGE="https://github.com/${REPO}/releases/tag/${TAG}"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > build/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${APP_NAME}</title>
    <item>
      <title>${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${NEW_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <link>${RELEASE_PAGE}</link>
      <description sparkle:format="markdown"><![CDATA[**Reader.md no longer updates itself.** Click **Learn More**, download
${APP_NAME}.dmg from the release page and replace the app in Applications. This
is the last time you need to: from then on, Reader.md tells you about new
versions itself.

${NOTES}
]]></description>
    </item>
  </channel>
</rss>
APPCAST
# A stray "]]>" in the notes, or anything else malformed, would make old installs
# fail the check quietly. Catch it here instead.
xmllint --noout build/appcast.xml

# Create the release (or replace assets if the tag already exists). Must be the
# newest, non-prerelease release so releases/latest/download/appcast.xml resolves.
# The body is the changelog section — a release page that summarized itself as
# "Reader.md 1.2.0" told a reader nothing. Re-running against an existing tag
# rewrites it too, since that's when the notes changed.
if ! gh release create "${TAG}" "${DMG}" build/appcast.xml \
       --repo "${REPO}" --title "${TAG}" --notes-file "${NOTES_FILE}"; then
  gh release upload "${TAG}" "${DMG}" build/appcast.xml --repo "${REPO}" --clobber
  gh release edit "${TAG}" --repo "${REPO}" --notes-file "${NOTES_FILE}"
fi

echo "Released ${TAG}: appcast.xml + ${APP_NAME}.dmg uploaded to ${REPO}."

# Point the Homebrew cask at this release. The DMG url is version-templated, so
# only the version and sha256 change per release; rewrite those two lines and
# commit so `brew install --cask` never serves a stale build. The sha256 is of
# the exact DMG we just uploaded, so `brew` verifies the same bytes.
CASK="Casks/reader-md.rb"
DMG_SHA="$(shasum -a 256 "${DMG}" | cut -d' ' -f1)"
sed -i '' \
  -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"${DMG_SHA}\"/" \
  "${CASK}"
if ! git diff --quiet -- "${CASK}"; then
  git add "${CASK}"
  git commit -m "chore: update Homebrew cask to ${TAG}"
  git push
  echo "Updated ${CASK} -> ${VERSION} (${DMG_SHA})."
fi
