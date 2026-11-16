#!/usr/bin/env bash
# Generate a signed Sparkle appcast for one already notarized release archive.
# The EdDSA private key stays in the login Keychain (account BUNDLE_ID from version.env).
# Never export, print, commit or upload it.
#
#   scripts/make-appcast.sh          sign dist/Halodeck-<version>.zip
#   scripts/make-appcast.sh --check  only check the tools, the Keychain key and the release notes
#
# The release app sets SURequireSignedFeed, so generate_appcast also signs the appcast itself (an
# EdDSA signature in a trailing `<!-- sparkle-signatures: … -->` comment); the script refuses an
# appcast without a valid one. DIST_DIR (default dist/) is where the archive is read and the appcast
# written.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
SPARKLE_BIN=${SPARKLE_BIN:-"$ROOT/.build/artifacts/sparkle/Sparkle/bin"}
DIST_DIR=${DIST_DIR:-"$ROOT/dist"}
ARCHIVE="$DIST_DIR/Halodeck-${MARKETING_VERSION}.zip"
NOTES="$ROOT/docs/releases/v${MARKETING_VERSION}.md"
ACCOUNT=$BUNDLE_ID

[[ -x "$SPARKLE_BIN/generate_appcast" && -x "$SPARKLE_BIN/generate_keys" && -x "$SPARKLE_BIN/sign_update" ]] || {
  echo "Sparkle tools missing: run swift build first, or set SPARKLE_BIN to Sparkle 2.10.1's bin directory." >&2
  exit 1
}
ACTUAL=$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)
[[ "$ACTUAL" == "$SPARKLE_PUBLIC_KEY" ]] || { echo "Sparkle Keychain public key mismatch; refusing to create an unusable appcast." >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "Missing release notes $NOTES" >&2; exit 1; }
if [[ ${1:-} == --check ]]; then
  echo "APPCAST_TOOLS_READY"
  exit 0
fi
[[ -f "$ARCHIVE" ]] || { echo "Missing $ARCHIVE" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/halodeck-appcast.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cp "$ARCHIVE" "$TMP/"
# Sparkle shows Markdown notes that share the archive's base name.
cp "$NOTES" "$TMP/$(basename "$ARCHIVE" .zip).md"
"$SPARKLE_BIN/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/${GITHUB_REPOSITORY}/releases/download/v${MARKETING_VERSION}/" \
  --link "https://github.com/${GITHUB_REPOSITORY}" "$TMP"
[[ -f "$TMP/appcast.xml" ]] || { echo "No appcast was generated." >&2; exit 1; }
grep -q "sparkle:version>${BUILD_NUMBER}<" "$TMP/appcast.xml" || { echo "The appcast does not contain build ${BUILD_NUMBER}." >&2; exit 1; }
# The app accepts only a signed feed: an unsigned one would strand every installed copy.
grep -q '<!-- sparkle-signatures:' "$TMP/appcast.xml" ||
  { echo "The appcast is not signed: does the archived app set SURequireSignedFeed (RELEASE=1 build)?" >&2; exit 1; }
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$TMP/appcast.xml" >/dev/null ||
  { echo "The appcast's signature does not verify with the Keychain key." >&2; exit 1; }
cp "$TMP/appcast.xml" "$DIST_DIR/appcast.xml"
echo "APPCAST_READY (signed): $DIST_DIR/appcast.xml"
