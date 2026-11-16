#!/usr/bin/env bash
# Install a verified (notarized) release at /Applications/Halodeck.app and restart it.
# The previous copy is kept until the new one is copied, checked and running.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
SOURCE=${1:-"$ROOT/dist/Halodeck.app"}
DEST=/Applications/Halodeck.app

[[ -f "$SOURCE/Contents/Info.plist" && ! -L "$DEST" ]] || { echo "ERROR: Missing source app, or the destination is a symlink." >&2; exit 1; }
SOURCE=$(cd "$SOURCE" && pwd -P)
[[ "$SOURCE" != "$DEST" ]] || { echo "ERROR: Source and destination must differ." >&2; exit 1; }
[[ -w /Applications ]] || { echo "ERROR: /Applications is not writable; nothing changed." >&2; exit 1; }
ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")
[[ "$ID" == "$BUNDLE_ID" ]] || { echo "ERROR: Refusing to install an unexpected bundle identifier: $ID" >&2; exit 1; }
if [[ -e "$DEST" ]]; then
  OLD_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
  [[ "$OLD_ID" == "$BUNDLE_ID" ]] || { echo "ERROR: $DEST belongs to another app; nothing changed." >&2; exit 1; }
fi
codesign --verify --deep --strict "$SOURCE"
xcrun stapler validate "$SOURCE"
spctl --assess --type execute "$SOURCE"
swift "$ROOT/scripts/check-bundle.swift" "$SOURCE"
swift "$ROOT/scripts/check-release-privacy.swift" "$SOURCE"

WORK=$(mktemp -d /Applications/.Halodeck-install.XXXXXX)
INSTALLED=0
cleanup() {
  result=$?
  trap - EXIT
  if [[ "$result" -ne 0 ]]; then
    [[ "$INSTALLED" == 1 && -d "$DEST" ]] && mv "$DEST" "$WORK/failed.app" || true
    if [[ -d "$WORK/previous.app" ]]; then
      mv "$WORK/previous.app" "$DEST"
      open -g "$DEST" || true
      echo "Restored the previous installation." >&2
    fi
  fi
  rm -rf "$WORK"
  exit "$result"
}
trap cleanup EXIT
ditto "$SOURCE" "$WORK/Halodeck.app"
codesign --verify --deep --strict "$WORK/Halodeck.app"

# Ask running copies to quit normally (by bundle identifier); never force-kill.
BUNDLE_ID="$BUNDLE_ID" swift -e '
import AppKit
let id = ProcessInfo.processInfo.environment["BUNDLE_ID"]
let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == id }
for app in apps { _ = app.terminate() }
for _ in 0..<100 {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    if apps.allSatisfy({ $0.isTerminated }) { exit(0) }
}
fputs("Halodeck did not quit; installation aborted.\n", stderr)
exit(1)
'
[[ -d "$DEST" ]] && mv "$DEST" "$WORK/previous.app"
mv "$WORK/Halodeck.app" "$DEST"
INSTALLED=1
open -g "$DEST"

swift -e '
import AppKit
let target = URL(fileURLWithPath: "/Applications/Halodeck.app").standardizedFileURL
for _ in 0..<100 {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == target && !$0.isTerminated }) { exit(0) }
}
fputs("The installed Halodeck did not start.\n", stderr)
exit(1)
'
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")
echo "INSTALLED_AND_RUNNING: $DEST ($VERSION)"
