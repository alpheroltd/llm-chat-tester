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

echo "==> Creating (or reusing) the Sparkle signing key in your login Keychain"
"$SPARKLE_BIN/generate_keys" >/dev/null
PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
[[ -n "$PUBLIC_KEY" ]] || { echo "Could not read the public key from generate_keys" >&2; exit 1; }
sed -i '' -E "s#(SPARKLE_PUBLIC_KEY: ).*#\1\"$PUBLIC_KEY\"#" project.yml
echo "    Public key: $PUBLIC_KEY (written to project.yml)"

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
