#!/usr/bin/env bash
# One-time setup for Sparkle updates, run by the release maintainer on their Mac.
#   - creates (or reuses) the EdDSA signing key pair; the private key goes into your login Keychain
#   - writes the public key, and the feed URL if RELEASES_REPO is set, into project.yml
# Usage:
#   scripts/setup-updates.sh                                              # key only
#   RELEASES_REPO=owner/llm-chat-tester-releases scripts/setup-updates.sh  # key + feed URL
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/lib.sh

ensure_sparkle_tools

EXISTING_KEY="$(yml_value SPARKLE_PUBLIC_KEY)"
KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"

if [[ -n "$EXISTING_KEY" ]]; then
  # The app already trusts a key. Never create a different one: installed apps would reject every future update.
  if [[ "$KEYCHAIN_KEY" != "$EXISTING_KEY" ]]; then
    cat >&2 <<MSG
The app is signed for key $EXISTING_KEY, but this Mac's Keychain has ${KEYCHAIN_KEY:-no Sparkle key}.
Import the backed-up private key first:
  "$SPARKLE_BIN/generate_keys" -f <backup-file>
Refusing to continue, so no new key is created by mistake.
MSG
    exit 1
  fi
  PUBLIC_KEY="$EXISTING_KEY"
  echo "==> Using the existing signing key (found in this Mac's Keychain)"
else
  echo "==> Creating the Sparkle signing key in your login Keychain"
  "$SPARKLE_BIN/generate_keys" >/dev/null
  PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
  [[ -n "$PUBLIC_KEY" ]] || { echo "Could not read the public key from generate_keys" >&2; exit 1; }
  sed -i '' -E "s#(SPARKLE_PUBLIC_KEY: ).*#\1\"$PUBLIC_KEY\"#" project.yml
fi
echo "    Public key: $PUBLIC_KEY"

if [[ -n "${RELEASES_REPO:-}" ]]; then
  FEED_URL="$(feed_url)"
  sed -i '' -E "s#(SPARKLE_FEED_URL: ).*#\1\"$FEED_URL\"#" project.yml
  echo "    Feed URL:   $FEED_URL (written to project.yml)"
else
  echo "    Feed URL:   not set yet. Re-run with RELEASES_REPO=owner/repo once the releases repo exists."
fi

cat <<EOF

IMPORTANT: back up the private key. Without it you can never ship another update:
  "$SPARKLE_BIN/generate_keys" -x ~/Desktop/llm-chat-tester-sparkle-private-key.txt
Store that file in the team's password manager, then delete it from the Desktop.
EOF
