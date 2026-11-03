cask "murmur" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/@REPOSITORY@/releases/download/v#{version}/Murmur-#{version}.zip"
  name "Murmur"
  desc "Local-first push-to-talk dictation"
  homepage "https://github.com/@REPOSITORY@"

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "Murmur.app"

  zap trash: [
    "~/Library/Application Support/Murmur",
    "~/Library/Preferences/io.github.austin-wiechman.murmur.plist",
  ]

  caveats <<~EOS
    Apple hasn't notarized Murmur, so macOS blocks its first launch. Open
    Murmur once, then go to System Settings > Privacy & Security and click
    "Open Anyway" next to the message about Murmur.
  EOS
end
