#!/usr/bin/env bash
# Builds, signs and publishes a release of the Mac app as a GitHub Release (tag v<version>) on this repo,
# with two files attached:
#   - LLM-Chat-Tester.zip  the app
#   - appcast.xml          the Sparkle update feed, listing every version (installed apps read the newest copy via
#                          https://github.com/<repo>/releases/latest/download/appcast.xml)
#
# Usage:
#   RELEASES_REPO=alpheroltd/llm-chat-tester scripts/release.sh 0.2.1
# Options:
#   DRY_RUN=1        build, sign, zip and write the feed into dist/; publish nothing and leave project.yml untouched
#   SIGN_IDENTITY=…  code-signing identity (default "-" = ad-hoc)
#
# Release notes come from the "## <version>" section of macos/CHANGELOG.md.
# After a real release, commit the version bump in project.yml.
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version, e.g. 0.2.1>}"
: "${RELEASES_REPO:?Set RELEASES_REPO, e.g. RELEASES_REPO=alpheroltd/llm-chat-tester}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DRY_RUN="${DRY_RUN:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/lib.sh

# ---- Checks ----
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
[[ -n "$(yml_value SPARKLE_PUBLIC_KEY)" ]] || { echo "SPARKLE_PUBLIC_KEY is empty. Run scripts/setup-updates.sh first." >&2; exit 1; }
[[ "$(yml_value SPARKLE_FEED_URL)" == "$(feed_url)" ]] || { echo "SPARKLE_FEED_URL in project.yml doesn't match RELEASES_REPO ($(feed_url)). Run: RELEASES_REPO=$RELEASES_REPO scripts/setup-updates.sh" >&2; exit 1; }
grep -q "^## $VERSION\$" CHANGELOG.md || { echo "Add a '## $VERSION' section to macos/CHANGELOG.md first." >&2; exit 1; }
if [[ "$DRY_RUN" != 1 ]]; then
  command -v gh >/dev/null || { echo "Install the GitHub CLI: brew install gh && gh auth login" >&2; exit 1; }
  if gh release view "v$VERSION" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists on $RELEASES_REPO. Pick a higher version." >&2; exit 1
  fi
  if [[ -n "$(git -C .. status --porcelain)" ]]; then
    echo "You have uncommitted changes. Commit and push them first, so the release matches the code on GitHub:" >&2
    git -C .. status --short >&2
    exit 1
  fi
fi
ensure_sparkle_tools

# In a dry run, put project.yml back exactly as it was when we finish.
mkdir -p build
if [[ "$DRY_RUN" == 1 ]]; then
  cp project.yml build/project.yml.before-dry-run
  trap 'mv build/project.yml.before-dry-run project.yml; xcodegen generate >/dev/null' EXIT
fi

# ---- Version bump (the build number always increases; Sparkle compares it) ----
BUILD_NUMBER=$(( $(yml_value CURRENT_PROJECT_VERSION) + 1 ))
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$BUILD_NUMBER\"/" project.yml
echo "==> Building $VERSION (build $BUILD_NUMBER)"

# ---- Build ----
xcodegen generate >/dev/null
rm -rf build/release
xcodebuild -project LLMChatTester.xcodeproj -scheme LLMChatTester -configuration Release \
  -derivedDataPath build/release -clonedSourcePackagesDirPath build/DerivedData/SourcePackages \
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

# ---- Package: a fixed file name per release, so .../releases/latest/download/LLM-Chat-Tester.zip always works ----
OUT="dist/$VERSION"
rm -rf "$OUT" && mkdir -p "$OUT"
ZIP="$OUT/LLM-Chat-Tester.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # sparkle:edSignature="..." length="..."
echo "    $ZIP ($(du -h "$ZIP" | cut -f1))"

NOTES_MD="$OUT/notes.md"
awk -v v="## $VERSION" '$0 == v {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$NOTES_MD"

# ---- Feed: the previous release's appcast plus this version (older entries keep their own download URLs) ----
APPCAST="$OUT/appcast.xml"
if curl -fsSL "$(feed_url)" -o "$APPCAST" 2>/dev/null; then
  echo "    continuing the published feed ($(grep -c '<item>' "$APPCAST") earlier release(s))"
else
  rm -f "$APPCAST" # first release: start a new feed
fi
DOWNLOAD_URL="https://github.com/$RELEASES_REPO/releases/download/v$VERSION/LLM-Chat-Tester.zip"
python3 scripts/appcast.py "$APPCAST" "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_URL" "$SIGNATURE_ATTRS" "$NOTES_MD"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "==> DRY RUN: nothing published. See $OUT/ (LLM-Chat-Tester.zip, appcast.xml). project.yml restored."
  exit 0
fi

# ---- Publish ----
echo "==> Creating GitHub release v$VERSION on $RELEASES_REPO"
gh release create "v$VERSION" "$ZIP" "$APPCAST" --repo "$RELEASES_REPO" --target main --latest \
  --title "LLM Chat Tester $VERSION" --notes-file "$NOTES_MD"
sleep 3
if ! curl -fsSL "$(feed_url)" | grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>"; then
  echo "WARNING: $(feed_url) doesn't list build $BUILD_NUMBER yet. Check the release on GitHub." >&2
fi
echo "==> Released $VERSION."
echo "    Release page (send this to testers): https://github.com/$RELEASES_REPO/releases/latest"
echo "    Direct download:                     https://github.com/$RELEASES_REPO/releases/latest/download/LLM-Chat-Tester.zip"
echo "    Now commit the version bump:         git add macos/project.yml && git commit -m \"Release $VERSION\" && git push"
