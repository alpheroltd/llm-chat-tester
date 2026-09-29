# Shared helpers for the release scripts. Source this file; don't run it.

SPARKLE_BIN="$ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

# Sparkle's command-line tools come with the Swift package; resolve it if they aren't there yet.
ensure_sparkle_tools() {
  if [[ ! -x "$SPARKLE_BIN/sign_update" || ! -x "$SPARKLE_BIN/generate_keys" ]]; then
    rm -rf "$ROOT/build/DerivedData/SourcePackages" # re-download a damaged copy
    echo "==> Resolving Swift packages to get Sparkle's tools"
    xcodegen generate >/dev/null
    xcodebuild -resolvePackageDependencies -project LLMChatTester.xcodeproj -scheme LLMChatTester -derivedDataPath build/DerivedData >/dev/null
  fi
  [[ -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_keys" ]] || { echo "Sparkle tools not found in $SPARKLE_BIN" >&2; exit 1; }
}

# The update feed is attached to every GitHub Release; this URL always serves the newest release's copy.
feed_url() {
  echo "https://github.com/${RELEASES_REPO}/releases/latest/download/appcast.xml"
}

yml_value() { grep -E "^\s*$1:" project.yml | head -1 | sed -E 's/^[^:]+: *"?([^"]*)"?.*/\1/'; }
