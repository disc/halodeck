# TEMPLATE: scripts/release.sh copies this file into the tap (disc/homebrew-tap) and fills in the
# real version and sha256 of the release ZIP. Never copy it into a tap by hand: the all-zero sha256
# below is a placeholder, and Homebrew rejects the download until the release script replaces it.
cask "halodeck" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/disc/halodeck/releases/download/v#{version}/Halodeck-#{version}.zip"
  name "Halodeck"
  desc "Turns the trackpad's sides into sliders and its corners into buttons"
  homepage "https://github.com/disc/halodeck"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Halodeck.app"

  uninstall quit: "io.github.disc.halodeck"

  zap trash: [
    "~/Library/Caches/io.github.disc.halodeck",
    "~/Library/HTTPStorages/io.github.disc.halodeck",
    "~/Library/Preferences/io.github.disc.halodeck.plist",
  ]
end
