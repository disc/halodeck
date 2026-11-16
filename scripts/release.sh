#!/usr/bin/env bash
# Build, sign, notarize, staple and check a Halodeck release; write the ZIP, SHA256SUMS.txt and the
# signed Sparkle appcast to dist/. With --publish, also publish it to GitHub Releases, update the
# Homebrew cask in the tap, install it at /Applications/Halodeck.app and restart it.
#
#   scripts/release.sh <x.y.z>            dry run: everything up to and including dist/
#   scripts/release.sh <x.y.z> --publish  release, update the tap, install
#
# A new <x.y.z> is written to version.env and HalodeckVersion.swift, BUILD_NUMBER goes up by one,
# and the script stops: write docs/releases/v<x.y.z>.md, commit, push and run it again.
#
# Environment:
#   HALODECK_SIGN_IDENTITY   codesigning identity (default: the first "Developer ID Application"
#                            identity in the Keychain; with none the build is ad hoc, not notarized,
#                            and can only be a dry run)
#   HALODECK_NOTARY_PROFILE  notarytool Keychain profile (default: halodeck)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

usage() { sed -n '6,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
step() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

VERSION=${1:-}
PUBLISH=0
case "${2:-}" in
  "") ;;
  --publish) PUBLISH=1 ;;
  *) usage ;;
esac
[[ $# -le 2 ]] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

source version.env
VERSION_SWIFT=Sources/HalodeckCore/HalodeckVersion.swift
SOURCE_VERSION=$(sed -nE 's/.*static let marketing = "([^"]*)".*/\1/p' "$VERSION_SWIFT")

if [[ "$MARKETING_VERSION" != "$VERSION" || "$SOURCE_VERSION" != "$VERSION" ]]; then
  step "bumping to $VERSION"
  if [[ "$MARKETING_VERSION" != "$VERSION" ]]; then
    sed -i '' -E "s/^MARKETING_VERSION=.*/MARKETING_VERSION=${VERSION}/" version.env
    sed -i '' -E "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$((BUILD_NUMBER + 1))/" version.env
  fi
  sed -i '' -E "s/(static let marketing = \")[^\"]*\"/\1${VERSION}\"/" "$VERSION_SWIFT"
  git --no-pager diff -- version.env "$VERSION_SWIFT"
  echo "Version bumped. Write docs/releases/v${VERSION}.md, commit, push and run scripts/release.sh ${VERSION} again." >&2
  exit 1
fi
NOTES="docs/releases/v${VERSION}.md"
[[ -f "$NOTES" ]] || die "missing release notes $NOTES"
TAG="v${VERSION}"
step "Halodeck $VERSION (build $BUILD_NUMBER)$([[ $PUBLISH == 1 ]] && echo ', publishing' || echo ', dry run')"

# Signing and credentials (checked before the expensive build)
IDENTITY=${HALODECK_SIGN_IDENTITY:-}
if [[ -z "$IDENTITY" ]]; then
  IDENTITIES=$(security find-identity -v -p codesigning)
  IDENTITY=$(awk -F'"' '/"Developer ID Application: / { print $2; exit }' <<<"$IDENTITIES")
fi
NOTARY_PROFILE=${HALODECK_NOTARY_PROFILE:-halodeck}
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  IDENTITY="-"
  SIGNED=0
  step "identity: none (ad hoc; not notarized)"
  [[ $PUBLISH == 0 ]] || die "--publish needs a Developer ID Application identity"
else
  SIGNED=1
  step "identity: $IDENTITY"
  step "notary profile: $NOTARY_PROFILE"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null ||
    die "notary profile '$NOTARY_PROFILE' does not work (xcrun notarytool store-credentials $NOTARY_PROFILE)"
fi
step "checking the Sparkle tools and key"
scripts/make-appcast.sh --check

if [[ $PUBLISH == 1 ]]; then
  command -v gh >/dev/null || die "the GitHub CLI (gh) is required"
  [[ -z "$(git status --porcelain)" ]] || die "the git tree has uncommitted changes"
  git fetch -q origin main
  COMMIT=$(git rev-parse HEAD)
  [[ "$COMMIT" == "$(git rev-parse origin/main)" ]] || die "HEAD is not origin/main; push the release commit first"
  # The build number must grow past the published feed. The first release has none yet.
  FEED=$(curl -fsSL --max-time 30 "$SPARKLE_FEED_URL" 2>/dev/null || true)
  PUBLISHED=$(printf '%s' "$FEED" | grep -o 'sparkle:version>[0-9]*<' | head -1 | tr -dc '0-9' || true)
  PUBLISHED=${PUBLISHED:-0}
  if [[ "$PUBLISHED" -eq 0 ]] && gh release view --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    die "cannot read the published build number from $SPARKLE_FEED_URL"
  fi
  [[ "$BUILD_NUMBER" -gt "$PUBLISHED" ]] || die "BUILD_NUMBER=$BUILD_NUMBER must be greater than the published $PUBLISHED"
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || [[ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]] ||
    gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    die "tag or release $TAG already exists"
  fi
fi

OUTPUT_DIR="$ROOT/dist"
APP="$OUTPUT_DIR/Halodeck.app"
ZIP="$OUTPUT_DIR/Halodeck-${VERSION}.zip"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/Halodeck-*.zip "$OUTPUT_DIR/SHA256SUMS.txt" "$OUTPUT_DIR/appcast.xml" \
  "$OUTPUT_DIR"/notarization*.json "$OUTPUT_DIR/COMMIT"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/halodeck-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

step "swift test"
swift test
step "building $APP"
RELEASE=1 SIGNING_IDENTITY="$IDENTITY" APP_OUTPUT_DIR="$OUTPUT_DIR" scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 "$APP"
step "checking the bundle"
swift scripts/check-bundle.swift "$APP"
swift scripts/check-release-privacy.swift "$APP"

if [[ $SIGNED == 1 ]]; then
  step "notarizing (this takes a few minutes)"
  /usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$WORK/Notarize.zip"
  # notarytool exits non-zero for Invalid or Rejected; keep going so the log is fetched.
  SUBMIT_EXIT=0
  xcrun notarytool submit "$WORK/Notarize.zip" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json >"$OUTPUT_DIR/notarization.json" || SUBMIT_EXIT=$?
  STATUS=$(/usr/bin/plutil -extract status raw -o - "$OUTPUT_DIR/notarization.json" 2>/dev/null || echo unknown)
  if [[ "$STATUS" != "Accepted" || "$SUBMIT_EXIT" -ne 0 ]]; then
    ID=$(/usr/bin/plutil -extract id raw -o - "$OUTPUT_DIR/notarization.json" 2>/dev/null || true)
    if [[ -n "$ID" ]]; then
      xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >"$OUTPUT_DIR/notarization-log.json" || true
      die "notarization was not accepted ($STATUS, exit $SUBMIT_EXIT); see dist/notarization-log.json"
    fi
    die "notarization failed before a submission ID was returned (exit $SUBMIT_EXIT); see dist/notarization.json"
  fi
  step "notarization: $STATUS"
  step "stapling"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  swift scripts/check-release-privacy.swift "$APP"
fi

step "archiving"
/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$ZIP"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP")" >SHA256SUMS.txt)
if [[ $SIGNED == 1 ]]; then
  # Sign the final archive for Sparkle. Never modify the ZIP after this point.
  step "writing the appcast"
  scripts/make-appcast.sh
else
  step "skipping the appcast: an ad-hoc build is never offered as an update"
fi
step "built: $ZIP"

if [[ $PUBLISH == 0 ]]; then
  step "dry run complete (pass --publish to release $TAG, update the tap and install)"
  exit 0
fi

[[ -z "$(git status --porcelain)" && "$(git rev-parse HEAD)" == "$COMMIT" ]] ||
  die "the git tree changed during the build; dist/ does not match $COMMIT"
grep -q "sparkle:version>${BUILD_NUMBER}<" "$OUTPUT_DIR/appcast.xml" || die "the appcast is not for build $BUILD_NUMBER"
(cd "$OUTPUT_DIR" && shasum -a 256 -c SHA256SUMS.txt)

# Create a draft, upload every asset, then publish, so the feed never points at a missing archive.
step "publishing $TAG to $GITHUB_REPOSITORY"
gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --target "$COMMIT" --draft \
  --title "Halodeck ${VERSION}" --notes-file "$NOTES" \
  "$ZIP" "$OUTPUT_DIR/SHA256SUMS.txt" "$OUTPUT_DIR/appcast.xml"
gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --latest

# packaging/halodeck.rb is the cask's source of truth; the tap gets only a new version and sha256.
step "updating the cask in $TAP_REPOSITORY"
SHA=$(awk -v f="$(basename "$ZIP")" '$2 == f { print $1 }' "$OUTPUT_DIR/SHA256SUMS.txt")
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || die "no SHA-256 for $(basename "$ZIP")"
TAP="$WORK/tap"
gh repo clone "$TAP_REPOSITORY" "$TAP" -- --quiet
CASK="$TAP/Casks/halodeck.rb"
mkdir -p "$TAP/Casks"
# A first copy drops the template's leading comment; the all-zero placeholder sha256 is replaced below.
[[ -f "$CASK" ]] || grep -v '^#' packaging/halodeck.rb >"$CASK"
sed -i '' -E "s/^  version \".*\"$/  version \"${VERSION}\"/; s/^  sha256 .*/  sha256 \"${SHA}\"/" "$CASK"
grep -qx "  version \"${VERSION}\"" "$CASK" && grep -qx "  sha256 \"${SHA}\"" "$CASK" ||
  die "could not set version and sha256 in Casks/halodeck.rb"
git -C "$TAP" add Casks/halodeck.rb
if git -C "$TAP" diff --cached --quiet; then
  step "the cask is already at $VERSION"
else
  git -C "$TAP" --no-pager diff --cached
  git -C "$TAP" commit -q -m "halodeck ${VERSION}"
  git -C "$TAP" push -q origin HEAD
fi

step "installing at /Applications/Halodeck.app"
scripts/install.sh "$APP"
RUNNING=$(pgrep -x Halodeck | while read -r pid; do ps -o comm= -p "$pid"; done || true)
step "running: ${RUNNING:-nothing}"
[[ "$RUNNING" == /Applications/Halodeck.app/* ]] || die "the running Halodeck is not the one in /Applications"
step "released $TAG"
