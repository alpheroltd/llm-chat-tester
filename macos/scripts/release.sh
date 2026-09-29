#!/usr/bin/env bash
# Builds, signs and publishes the Mac app as the GitHub Release for tag v<version>, with two files attached:
#   - LLM-Chat-Tester.zip  the app
#   - appcast.xml          the Sparkle update feed, listing every version (installed apps read the newest copy via
#                          https://github.com/<repo>/releases/latest/download/appcast.xml)
#
# Normally run by .github/workflows/release.yml when a v* tag is pushed; use the /release skill to cut one.
# Usage: scripts/release.sh 0.2.1
# Environment:
#   RELEASES_REPO        owner/repo (default: $GITHUB_REPOSITORY)
#   SPARKLE_PRIVATE_KEY  EdDSA private key; without it, sign_update reads this Mac's Keychain
#   DRY_RUN=1            build, sign, zip and write the feed into dist/; publish nothing
#   SIGN_IDENTITY=…      code-signing identity (default "-" = ad-hoc)
#
# Release notes come from the "## <version>" section of macos/CHANGELOG.md.
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version, e.g. 0.2.1>}"
RELEASES_REPO="${RELEASES_REPO:-${GITHUB_REPOSITORY:-}}"
: "${RELEASES_REPO:?Set RELEASES_REPO, e.g. RELEASES_REPO=alpheroltd/llm-chat-tester}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DRY_RUN="${DRY_RUN:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/lib.sh

# ---- Checks ----
PUBLIC_KEY="$(yml_value SPARKLE_PUBLIC_KEY)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
[[ -n "$PUBLIC_KEY" ]] || { echo "SPARKLE_PUBLIC_KEY is empty. Run scripts/setup-updates.sh first." >&2; exit 1; }
[[ "$(yml_value SPARKLE_FEED_URL)" == "$(feed_url)" ]] || { echo "SPARKLE_FEED_URL in project.yml doesn't match RELEASES_REPO ($(feed_url)). Run: RELEASES_REPO=$RELEASES_REPO scripts/setup-updates.sh" >&2; exit 1; }
grep -q "^## $VERSION\$" CHANGELOG.md || { echo "Add a '## $VERSION' section to macos/CHANGELOG.md first." >&2; exit 1; }
if [[ "$DRY_RUN" != 1 ]]; then
  command -v gh >/dev/null || { echo "Install the GitHub CLI: brew install gh && gh auth login" >&2; exit 1; }
  if gh release view "v$VERSION" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists on $RELEASES_REPO. Pick a higher version." >&2; exit 1
  fi
fi
ensure_sparkle_tools

# ---- Feed so far: the previous release's appcast (older entries keep their own download URLs) ----
OUT="dist/$VERSION"
rm -rf "$OUT" && mkdir -p "$OUT"
APPCAST="$OUT/appcast.xml"
if curl -fsSL "$(feed_url)" -o "$APPCAST" 2>/dev/null; then
  echo "==> Continuing the published feed ($(grep -c '<item>' "$APPCAST") earlier release(s))"
else
  rm -f "$APPCAST" # first release: start a new feed
fi

# ---- Build number: Sparkle compares it, so it must beat every build in the feed ----
LAST_BUILD="$( { yml_value CURRENT_PROJECT_VERSION; [[ -f "$APPCAST" ]] && grep -oE '<sparkle:version>[0-9]+' "$APPCAST" | grep -oE '[0-9]+$'; } | sort -n | tail -1)"
BUILD_NUMBER=$(( LAST_BUILD + 1 ))
echo "==> Building $VERSION (build $BUILD_NUMBER)"

# ---- Build ----
xcodegen generate >/dev/null
rm -rf build/release
xcodebuild -project LLMChatTester.xcodeproj -scheme LLMChatTester -configuration Release \
  -derivedDataPath build/release -clonedSourcePackagesDirPath build/DerivedData/SourcePackages \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build > build/release.log 2>&1 || { tail -30 build/release.log; echo "Build failed (full log: build/release.log)" >&2; exit 1; }
APP="build/release/Build/Products/Release/LLM Chat Tester.app"

# ---- Sign (inside-out: Sparkle's helpers, the framework, then the app). No --options runtime: see the
# ENABLE_HARDENED_RUNTIME note in project.yml. ----
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "==> Signing with \"$SIGN_IDENTITY\""
  SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for item in "$SPK/XPCServices/Installer.xpc" "$SPK/XPCServices/Downloader.xpc" "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    [[ -e "$item" ]] && codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$item"
  done
  codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" == "$(feed_url)" ]] || { echo "Built app has the wrong update feed" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_NUMBER" ]] || { echo "Built app has the wrong build number" >&2; exit 1; }

# ---- Package: a fixed file name per release, so .../releases/latest/download/LLM-Chat-Tester.zip always works ----
ZIP="$OUT/LLM-Chat-Tester.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGNATURE_ATTRS="$(sign_archive "$ZIP")"   # sparkle:edSignature="..." length="..."
SIGNATURE="$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$SIGNATURE_ATTRS")"
check_signature "$ZIP" "$SIGNATURE" "$PUBLIC_KEY" || { echo "The update is signed with a key that doesn't match SPARKLE_PUBLIC_KEY in project.yml. Installed apps would reject it." >&2; exit 1; }
echo "    $ZIP ($(du -h "$ZIP" | cut -f1)), signature matches the app's public key"

NOTES_MD="$OUT/notes.md"
awk -v v="## $VERSION" '$0 == v {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$NOTES_MD"

DOWNLOAD_URL="https://github.com/$RELEASES_REPO/releases/download/v$VERSION/LLM-Chat-Tester.zip"
python3 scripts/appcast.py "$APPCAST" "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_URL" "$SIGNATURE_ATTRS" "$NOTES_MD"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "==> DRY RUN: nothing published. See $OUT/ (LLM-Chat-Tester.zip, appcast.xml)."
  exit 0
fi

# ---- Publish (the tag must already be on GitHub; the workflow runs because it was pushed) ----
echo "==> Creating GitHub release v$VERSION on $RELEASES_REPO"
gh release create "v$VERSION" "$ZIP" "$APPCAST" --repo "$RELEASES_REPO" --verify-tag --latest \
  --title "LLM Chat Tester $VERSION" --notes-file "$NOTES_MD"
sleep 3
if ! curl -fsSL "$(feed_url)" | grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>"; then
  echo "WARNING: $(feed_url) doesn't list build $BUILD_NUMBER yet. Check the release on GitHub." >&2
fi
echo "==> Released $VERSION (build $BUILD_NUMBER): https://github.com/$RELEASES_REPO/releases/tag/v$VERSION"
