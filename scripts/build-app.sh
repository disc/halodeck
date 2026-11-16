#!/usr/bin/env bash
# Builds and signs Halodeck.app with Sparkle embedded.
#
#   scripts/build-app.sh             development copy in build/, signed with "Apple Development"
#                                    (a stable identity keeps the Accessibility grant across rebuilds);
#                                    it never reads the update feed, so it never replaces itself, and
#                                    it can render its UI to PNGs (`Halodeck --snapshot <dir>`).
#   RELEASE=1 scripts/build-app.sh   release copy: adds the update feed and key (signed feed and
#                                    verification before extraction required), signs with
#                                    SIGNING_IDENTITY (Developer ID) and the hardened runtime.
#
# Environment: SIGNING_IDENTITY (default "Apple Development"; "-" signs ad hoc), APP_OUTPUT_DIR
# (default build/).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env

RELEASE=${RELEASE:-0}
IDENTITY=${SIGNING_IDENTITY:-${CODESIGN_IDENTITY:-Apple Development}}
OUTPUT_DIR=${APP_OUTPUT_DIR:-"$ROOT/build"}

# Development copies compile in the --snapshot mode (HALODECK_SNAPSHOT); releases leave it out.
BUILD=(swift build -c release --arch arm64)
if [[ "$RELEASE" != 1 ]]; then
  BUILD+=(-Xswiftc -DHALODECK_SNAPSHOT)
fi
"${BUILD[@]}"
BIN_DIR="$("${BUILD[@]}" --show-bin-path)"

mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/Halodeck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Halodeck" "$APP/Contents/MacOS/Halodeck"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with scripts/make-icon.swift
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
# Release binaries keep no debug-map paths of this machine.
xcrun strip -S "$APP/Contents/MacOS/Halodeck"
# SwiftPM links Sparkle from the build folder; the app finds it in Contents/Frameworks. Drop the
# toolchain's absolute rpaths: they name this machine's Xcode and nothing the app loads lives there.
BIN="$APP/Contents/MacOS/Halodeck"
RPATHS=$(otool -l "$BIN" | awk '$1 == "cmd" { cmd = $2 }
  cmd == "LC_RPATH" && $1 == "path" { sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }')
while IFS= read -r rpath; do
  case "$rpath" in
    /Applications/Xcode*|/Library/Developer/*) install_name_tool -delete_rpath "$rpath" "$BIN" ;;
  esac
done <<<"$RPATHS"
if ! grep -qxF '@executable_path/../Frameworks' <<<"$RPATHS"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN"
fi

PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
if [[ "$RELEASE" == 1 ]]; then
  plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$PLIST"
  plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$PLIST"
  plutil -replace SUEnableAutomaticChecks -bool YES "$PLIST"
  plutil -replace SUAllowsAutomaticUpdates -bool NO "$PLIST"   # never install without a click
  # Sparkle accepts only an appcast signed with the update key (generate_appcast signs it when the
  # archived app asks for this), and checks the archive's EdDSA signature before extracting it.
  plutil -replace SURequireSignedFeed -bool YES "$PLIST"
  plutil -replace SUVerifyUpdateBeforeExtraction -bool YES "$PLIST"
fi

chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ "$IDENTITY" == "-" ]]; then
  SIGN=(codesign --force --sign -)
elif [[ "$RELEASE" == 1 ]]; then
  SIGN=(codesign --force --timestamp --options runtime --sign "$IDENTITY")
else
  SIGN=(codesign --force --sign "$IDENTITY")
fi

# Halodeck is not sandboxed, so Sparkle needs none of its XPC services (Sparkle's sandboxing
# guide); drop them rather than ship unused signed code.
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
# Inside out, as Sparkle's code-signing guide orders it: its helpers, the framework, then the app.
for item in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app"; do
  [[ -e "$item" ]] || { echo "ERROR: Sparkle helper missing: ${item#"$APP/"}" >&2; exit 1; }
  "${SIGN[@]}" "$item"
done
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"
echo "Built $APP ($MARKETING_VERSION, build $BUILD_NUMBER)"
