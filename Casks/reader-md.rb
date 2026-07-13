cask "reader-md" do
  version "1.8.0"
  sha256 "8decdd5c4b7d97d25430fd147f2539883bd434e781f6bebe2e52302340497703"

  url "https://github.com/jnahian/reader.md/releases/download/v#{version}/Reader.md.dmg",
      verified: "github.com/jnahian/reader.md/"
  name "Reader.md"
  desc "Native Markdown viewer for macOS"
  homepage "https://github.com/jnahian/reader.md"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The packaged app updates itself through Sparkle, so let it manage upgrades
  # rather than having Homebrew replace a Sparkle-updated build underneath it.
  auto_updates true
  depends_on macos: :ventura

  app "Reader.md.app"
  binary "#{appdir}/Reader.md.app/Contents/MacOS/reader"

  zap trash: [
    "~/Library/Application Support/com.nahian.reader-md",
    "~/Library/Caches/com.nahian.reader-md",
    "~/Library/HTTPStorages/com.nahian.reader-md",
    "~/Library/Preferences/com.nahian.reader-md.plist",
  ]
end
