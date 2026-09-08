# typed: strict
# frozen_string_literal: true

# Template for the Surf cask. release.yml fills in the version and sha256
# from the built .dmg and pushes the result to fcjr/homebrew-fcjr.
cask "surf" do
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"

  url "https://github.com/fcjr/surf/releases/download/v#{version}/Surf-#{version}.dmg"
  name "Surf"
  desc "Pair an Apple TV Siri Remote with your Mac: pointer, dictation, and more"
  homepage "https://github.com/fcjr/surf"

  auto_updates true
  depends_on macos: :sonoma

  app "Surf.app"

  zap trash: [
    "~/Library/Caches/com.leftshift.surf",
    "~/Library/HTTPStorages/com.leftshift.surf",
    "~/Library/Preferences/com.leftshift.surf.plist",
  ]
end
