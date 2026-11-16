# Working on Halodeck

Halodeck is a macOS 14+ menu-bar app for Apple silicon that turns the trackpad's sides into sliders
and its corners into click actions. It's a Swift package in Swift 6 language mode with strict
concurrency.

## Build and test

- `swift test` runs the tests. They must pass, and the build must have no warnings.
- `scripts/run.sh` builds a development copy, installs it and launches it. Sign development builds
  with a stable identity ("Apple Development"), not ad hoc: an ad-hoc build gets a new identity
  each time and macOS forgets its Accessibility permission.
- `pkill -x Halodeck` releases the pointer if a development build leaves it stuck.
- There is no hosted CI; tests and release checks run locally.

## Code

- `Sources/HalodeckCore` holds the pure logic: no AppKit and no private APIs. Write its tests
  first, with Swift Testing.
- The app's `Engine` reaches the system only through the protocols in
  `Sources/Halodeck/System/Services.swift`. Test it with the fakes in `Tests/HalodeckTests`.
- Halodeck uses private frameworks (MultitouchSupport, DisplayServices, CoreBrightness) and a
  global event tap, so it can't ship on the Mac App Store.
- The haptic actuator's two undocumented float arguments are always `0, 0`; other values make the
  trackpad produce an odd sound.
- Tests never write to the app's real `io.github.disc.halodeck` defaults; use a throwaway
  `UserDefaults` suite and remove it afterwards.
- New identifiers use the `io.github.disc.halodeck` prefix.

## Repository

- Docs are in English. `docs/` holds only what ships or is published: `docs/releases/v<version>.md`
  (the GitHub release text and the update notes) and `docs/screenshots/` (the README images).
  Design material stays out of the repository.
- Halodeck is MIT licensed (`LICENSE`); Sparkle's license is in `THIRD_PARTY_NOTICES.md`. Both
  ship inside the app.

## Releases

- `scripts/release.sh <x.y.z>` is a dry run: it tests, builds, signs with Developer ID, notarizes,
  staples, checks and writes `dist/` (the ZIP, `SHA256SUMS.txt` and the signed appcast).
  `--publish` also publishes the GitHub release, updates the Homebrew cask and installs the app.
- A new version makes the script bump `version.env`, `HalodeckVersion.marketing` and `BUILD_NUMBER`
  and stop: write `docs/releases/v<version>.md`, commit and run it again. Every release needs a
  higher `BUILD_NUMBER` and its release notes.
- Release artifacts must pass `scripts/check-bundle.swift` and `scripts/check-release-privacy.swift`
  and contain no local home or build paths. Never modify a ZIP after `scripts/make-appcast.sh`
  signed it.
- `packaging/halodeck.rb` is the source of truth for the cask; the release script copies it into
  the tap and rewrites only `version` and `sha256`. Keep the cask without `auto_updates`: Homebrew
  copies update through `brew`, downloaded copies through Sparkle (`UpdateChannel`).
