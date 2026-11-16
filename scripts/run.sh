#!/usr/bin/env bash
# Builds Halodeck, installs it and (re)launches it. Installs over the copy in /Applications if there is
# one, otherwise to ~/Applications: one stable path keeps the Accessibility grant.
# A release copy in /Applications (one with an update feed) is never replaced unless FORCE=1.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /Applications/Halodeck.app ]; then
    DEST=/Applications
    if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' /Applications/Halodeck.app/Contents/Info.plist >/dev/null 2>&1 \
        && [ "${FORCE:-0}" != 1 ]; then
        echo "ERROR: /Applications/Halodeck.app is a release build (it has an update feed); a development" >&2
        echo "build would replace a notarized copy. Remove it first, or run FORCE=1 scripts/run.sh." >&2
        exit 1
    fi
else
    DEST="$HOME/Applications"
fi

scripts/build-app.sh
pkill -x Halodeck || true
sleep 0.5
mkdir -p "$DEST"
rm -rf "$DEST/Halodeck.app"
cp -R build/Halodeck.app "$DEST/Halodeck.app"
echo "Installed $DEST/Halodeck.app"
open "$DEST/Halodeck.app"
