#!/usr/bin/env bash
# End-to-end check that Sparkle can update this (ad-hoc signed, un-notarized) app, without GitHub.
# Builds 0.1.0 and 0.1.1 pointed at a local feed, installs 0.1.0, lets Sparkle find, download and
# install 0.1.1 automatically, then confirms the installed app is 0.1.1 and still launches.
# Needs the Sparkle key from scripts/setup-updates.sh. Usage: scripts/update-smoke-test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/lib.sh
ensure_sparkle_tools

BUNDLE_ID="com.alphero.qa.llmchattester"
PORT=8765
FEED="http://localhost:$PORT/appcast.xml"
WORK="$ROOT/build/update-test"
APP_NAME="LLM Chat Tester.app"
INSTALLED="$WORK/install/$APP_NAME"

cleanup() {
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  osascript -e 'quit app "LLM Chat Tester"' >/dev/null 2>&1 || true
  # Undo the test-only Sparkle preferences.
  for key in SUAutomaticallyUpdate SUEnableAutomaticChecks SUHasLaunchedBefore SULastCheckTime SUSkippedVersion; do
    defaults delete "$BUNDLE_ID" "$key" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

rm -rf "$WORK" && mkdir -p "$WORK/feed" "$WORK/install"
xcodegen generate >/dev/null

build() { # version build-number
  echo "==> Building $1 (build $2) with feed $FEED"
  xcodebuild -project LLMChatTester.xcodeproj -scheme LLMChatTester -configuration Release \
    -derivedDataPath "$WORK/dd-$1" -clonedSourcePackagesDirPath build/DerivedData/SourcePackages \
    MARKETING_VERSION="$1" CURRENT_PROJECT_VERSION="$2" SPARKLE_FEED_URL="$FEED" \
    build > "$WORK/build-$1.log" 2>&1 || { tail -20 "$WORK/build-$1.log"; exit 1; }
  echo "$WORK/dd-$1/Build/Products/Release/$APP_NAME"
}

OLD_APP="$(build 0.1.0 1 | tail -1)"
NEW_APP="$(build 0.1.1 2 | tail -1)"

echo "==> Packaging 0.1.1 and writing the appcast"
ZIP="$WORK/feed/LLM-Chat-Tester-0.1.1.zip"
ditto -c -k --sequesterRsrc --keepParent "$NEW_APP" "$ZIP"
printf -- "- Update smoke test build.\n" > "$WORK/notes.md"
python3 scripts/appcast.py "$WORK/feed/appcast.xml" 0.1.1 2 "http://localhost:$PORT/$(basename "$ZIP")" "$(sign_archive "$ZIP")" "$WORK/notes.md"

echo "==> Serving the feed on http://localhost:$PORT"
(cd "$WORK/feed" && exec python3 -m http.server "$PORT" --bind 127.0.0.1) > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
sleep 1

echo "==> Installing 0.1.0 and enabling silent automatic updates (test only)"
ditto "$OLD_APP" "$INSTALLED"
defaults write "$BUNDLE_ID" SUEnableAutomaticChecks -bool YES
defaults write "$BUNDLE_ID" SUAutomaticallyUpdate -bool YES
defaults write "$BUNDLE_ID" SUHasLaunchedBefore -bool YES
defaults write "$BUNDLE_ID" hasCompletedOnboarding -bool YES
# With no last-check date, Sparkle waits a full interval (a day) before its first check;
# pretend the last check was long ago so it checks right after launch.
defaults write "$BUNDLE_ID" SULastCheckTime -date "2020-01-01 00:00:00 +0000"

open -n "$INSTALLED"
echo "==> Waiting for Sparkle to download the update"
for _ in $(seq 1 120); do
  grep -q "GET /$(basename "$ZIP")" "$WORK/server.log" && break
  sleep 1
done
grep -q "GET /appcast.xml" "$WORK/server.log" || { echo "FAIL: the app never fetched the appcast"; cat "$WORK/server.log"; exit 1; }
grep -q "GET /$(basename "$ZIP")" "$WORK/server.log" || { echo "FAIL: the app fetched the appcast but never downloaded the update"; cat "$WORK/server.log"; exit 1; }
echo "    appcast and update downloaded"
sleep 8 # let Sparkle verify the signature and unpack

echo "==> Quitting the app so Sparkle installs the update"
osascript -e 'quit app "LLM Chat Tester"' >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  VERSION="$(defaults read "$INSTALLED/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  [[ "$VERSION" == "0.1.1" ]] && break
  sleep 1
done
[[ "$VERSION" == "0.1.1" ]] || { echo "FAIL: installed app is still $VERSION"; exit 1; }
echo "    installed app is now $VERSION"

echo "==> Checking the updated app"
codesign --verify --deep --strict "$INSTALLED" && echo "    code signature valid ($(codesign -dv "$INSTALLED" 2>&1 | grep -E '^Signature=' | cut -d= -f2))"
if xattr -p com.apple.quarantine "$INSTALLED" >/dev/null 2>&1; then
  echo "    WARNING: the updated app is quarantined; Gatekeeper may block it"
else
  echo "    not quarantined (Gatekeeper won't re-prompt)"
fi
open -n "$INSTALLED"
sleep 5
if pgrep -f "$INSTALLED/Contents/MacOS" >/dev/null; then
  echo "    0.1.1 launches"
else
  echo "FAIL: the updated app didn't stay running"; exit 1
fi
echo "PASS: Sparkle updated 0.1.0 → 0.1.1 with an ad-hoc signed, un-notarized build."
