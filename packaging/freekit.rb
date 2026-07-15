# Homebrew cask for FreeKit. Lives in the tap repo cifyr/homebrew-freekit
# (path Casks/freekit.rb). See HOMEBREW.md for the release + tap workflow.
#
# The app is signed with a self-signed identity, NOT notarized, so a normal
# `brew install --cask freekit` would quarantine it and Gatekeeper would block
# first launch. Until the app is notarized, install with:
#   brew install --cask --no-quarantine freekit
cask "freekit" do
  version "0.1.0"
  sha256 "8921d45278425d945f449eab197c8c890012adc5597856bc0e6a9fb3dd686f12"

  url "https://github.com/cifyr/FreeKit/releases/download/v#{version}/FreeKit.dmg"
  name "FreeKit"
  desc "Local-first macOS menu bar utility suite: dictation, conversion, compression, and more"
  homepage "https://github.com/cifyr/FreeKit"

  # Apple Silicon + macOS 26 only (on-device FoundationModels + whisper.cpp/Metal).
  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "FreeKit.app"

  # Remove everything FreeKit writes when the user runs `brew uninstall --zap`.
  zap trash: [
    "~/Library/Application Support/FreeKit",
    "~/Library/Preferences/com.cadenwarren.freekit.plist",
    "~/Library/Caches/com.cadenwarren.freekit",
    "~/Library/Saved Application State/com.cadenwarren.freekit.savedState",
  ]
end
