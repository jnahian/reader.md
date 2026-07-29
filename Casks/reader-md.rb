cask "reader-md" do
  version "1.14.1"
  sha256 "049cf0a2239e134660e3a5e97c909d7ca680f9e97ee9cd4d11b8e40f7326e78b"

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
