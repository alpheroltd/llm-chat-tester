#!/usr/bin/env bash
# Builds, signs and publishes a release through GitHub Releases + a Sparkle appcast on GitHub Pages.
#
# Usage:
#   RELEASES_REPO=owner/llm-chat-tester-releases scripts/release.sh 0.1.1
# Optional:
#   SIGN_IDENTITY="Alphero QA Internal Signing"   code-signing identity (default "-" = ad-hoc)
#   DRY_RUN=1                                     build, sign, zip and write the appcast locally; publish nothing
#
# Release notes come from the "## <version>" section of CHANGELOG.md.
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version, e.g. 0.1.1>}"
: "${RELEASES_REPO:?Set RELEASES_REPO, e.g. RELEASES_REPO=alphero/llm-chat-tester-releases}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DRY_RUN="${DRY_RUN:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/lib.sh

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
[[ -n "$(yml_value SPARKLE_PUBLIC_KEY)" ]] || { echo "SPARKLE_PUBLIC_KEY is empty. Run scripts/setup-updates.sh first." >&2; exit 1; }
[[ "$(yml_value SPARKLE_FEED_URL)" == "$(feed_url)" ]] || { echo "SPARKLE_FEED_URL in project.yml doesn't match RELEASES_REPO ($(feed_url))." >&2; exit 1; }
grep -q "^## $VERSION\$" CHANGELOG.md || { echo "Add a '## $VERSION' section to macos/CHANGELOG.md first." >&2; exit 1; }
if [[ "$DRY_RUN" != 1 ]]; then
  command -v gh >/dev/null || { echo "Install the GitHub CLI: brew install gh && gh auth login" >&2; exit 1; }
fi
ensure_sparkle_tools

# ---- Version bump (build number always increases; Sparkle compares it) ----
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
echo "    signature: $(codesign -dv "$APP" 2>&1 | grep -E '^Signature=' | cut -d= -f2)"

# ---- Package ----
mkdir -p dist
ZIP="dist/LLM-Chat-Tester-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # sparkle:edSignature="..." length="..."
echo "    $ZIP ($(du -h "$ZIP" | cut -f1))"

# ---- Release notes (from CHANGELOG.md) ----
NOTES_MD="dist/notes-$VERSION.md"
awk -v v="## $VERSION" '$0 ~ "^"v {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$NOTES_MD"

# ---- Appcast: prepend this version to the published appcast ----
PAGES="build/pages"
rm -rf "$PAGES"
if [[ "$DRY_RUN" == 1 ]]; then
  mkdir -p "$PAGES"
else
  git clone --quiet --branch gh-pages "https://github.com/$RELEASES_REPO.git" "$PAGES" 2>/dev/null \
    || { mkdir -p "$PAGES" && git -C "$PAGES" init --quiet -b gh-pages && git -C "$PAGES" remote add origin "https://github.com/$RELEASES_REPO.git"; }
fi
DOWNLOAD_URL="https://github.com/$RELEASES_REPO/releases/download/v$VERSION/$(basename "$ZIP")"
python3 scripts/appcast.py "$PAGES/appcast.xml" "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_URL" "$SIGNATURE_ATTRS" "$NOTES_MD"
cp "$PAGES/appcast.xml" dist/appcast.xml

if [[ "$DRY_RUN" == 1 ]]; then
  echo "==> DRY RUN: nothing published. Built: $ZIP, appcast: dist/appcast.xml"
  exit 0
fi

# ---- Publish ----
echo "==> Publishing GitHub release v$VERSION to $RELEASES_REPO"
gh release create "v$VERSION" "$ZIP" --repo "$RELEASES_REPO" --title "LLM Chat Tester $VERSION" --notes-file "$NOTES_MD"
echo "==> Updating the appcast on GitHub Pages"
git -C "$PAGES" add appcast.xml
git -C "$PAGES" commit --quiet -m "Release $VERSION"
git -C "$PAGES" push --quiet origin gh-pages
echo "==> Released $VERSION. Testers get it via Check for Updates (or within a day automatically)."
