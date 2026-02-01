# This file is a reference for the Homebrew cask formula.
# It belongs in a separate repo: github.com/rajish/homebrew-tap
#
# To set up the tap:
#   1. Create repo: github.com/rajish/homebrew-tap
#   2. Place this file at: Casks/cc-hdrm.rb
#   3. Update the version and sha256 after each release
#
# Users install with:
#   brew tap rajish/tap
#   brew install --cask cc-hdrm

cask "cc-hdrm" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_DMG"

  url "https://github.com/rajish/cc-hdrm/releases/download/v#{version}/cc-hdrm-v#{version}.dmg"
  name "cc-hdrm"
  desc "macOS menu bar utility showing Claude usage at a glance"
  homepage "https://github.com/rajish/cc-hdrm"

  depends_on macos: ">= :sonoma"

  app "cc-hdrm.app"

  zap trash: [
    "~/Library/Preferences/com.cc-hdrm.app.plist",
    "~/Library/Caches/com.cc-hdrm.app",
  ]
end
