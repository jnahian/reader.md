cask "reader-md" do
  version "1.21.0"
  sha256 "bf0c7c6ef2bbafec5d4e5e6dc42ac31e025828b63bf25d2b93f3c1fbb7942402"

  url "https://github.com/jnahian/reader.md/releases/download/v#{version}/Reader.md.dmg"
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

  # Annotations and remote caches are under the app's *name*, not its bundle id
  # (MarkStore and RemoteSpec both build "Reader.md/…"), so zapping only the
  # bundle-id paths left every highlight and note behind.
  zap trash: [
    "~/Library/Application Support/Reader.md",
    "~/Library/Application Support/com.nahian.reader-md",
    "~/Library/Caches/com.nahian.reader-md",
    "~/Library/HTTPStorages/com.nahian.reader-md",
    "~/Library/Preferences/com.nahian.reader-md.plist",
  ]
end
