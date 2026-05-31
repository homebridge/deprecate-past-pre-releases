#!/bin/bash
# scripts/create_npm_token.sh
#
# Creates (or rotates) the npm deprecation token for the Homebridge org and
# stores it as a GitHub organisation secret.
#
# Prerequisites:
#   - npm CLI authenticated as a user with access to the packages listed below
#   - gh CLI authenticated as a user with org:secrets write permission
#
# Usage:
#   bash scripts/create_npm_token.sh

set -euo pipefail

# ── macOS only ─────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ This script must be run on macOS." >&2
  exit 1
fi
# ──────────────────────────────────────────────────────────

# ── Pre-flight check ───────────────────────────────────────
echo "⚠️  Before running this script, ensure you have refreshed your GitHub CLI auth with:"
echo ""
echo "    gh auth refresh -h github.com -s admin:org"
echo ""
read -r -p "Have you run the above command? (y/N): " CONFIRMED < /dev/tty
if [[ ! "$CONFIRMED" =~ ^[Yy]$ ]]; then
  echo "❌ Aborted. Please run 'gh auth refresh -h github.com -s admin:org' first."
  exit 1
fi
echo ""
# ──────────────────────────────────────────────────────────

# ── Configuration ─────────────────────────────────────────
NPM_ORG="homebridge"
SECRET_NAME="NPM_DEPRECATION_TOKEN"
TOKEN_DATE=$(date +'%Y-%m-%d')
TOKEN_NAME="Homebridge CI Deprecation Token ${TOKEN_DATE}"
EXPIRES=90
VISIBILITY="all"

PACKAGES=(
  homebridge
  homebridge-config-ui-x
  @homebridge/hap-client
)
# ──────────────────────────────────────────────────────────

# ── Step 1: Revoke any existing npm tokens with the same name
# NOTE: Revocation by name is not currently possible via the npm CLI.
# npm token list --json masks the key field with "***" and the plain text
# output does not reliably expose a usable token id for revocation.
# See: https://github.com/npm/cli/issues/9443
# Tokens must be manually revoked at: https://www.npmjs.com/settings/~/tokens
echo "ℹ️  Skipping token revocation (see https://github.com/npm/cli/issues/9443)"
echo "ℹ️  Old tokens named 'Homebridge CI Deprecation Token *' can be manually revoked at:"
echo "ℹ️  https://www.npmjs.com/settings/~/tokens"
echo ""

# ── Step 2: Build repeated --packages flags
PACKAGE_FLAGS=""
for pkg in "${PACKAGES[@]}"; do
  PACKAGE_FLAGS="$PACKAGE_FLAGS --packages=$pkg"
done

# ── Step 3: Create new npm token
# Collect password and OTP interactively before starting npm (which redirects stdout)
read -r -s -p "🔑 Enter your npm password: " NPM_PASSWORD < /dev/tty
echo ""
read -r -p "🔑 Enter your npm OTP code: " NPM_OTP < /dev/tty
echo ""

echo "Creating new npm token with name '$TOKEN_NAME' for packages: ${PACKAGES[*]}"
echo ""
echo "🔑 Creating new npm token..."
TMPFILE=$(mktemp)
printf '\n' | npm token create \
  --name="$TOKEN_NAME" \
  $PACKAGE_FLAGS \
  --packages-and-scopes-permission=read-write \
  --bypass-2fa \
  --expires=$EXPIRES \
  --password "$NPM_PASSWORD" \
  --otp="$NPM_OTP" > "$TMPFILE"

unset NPM_PASSWORD
unset NPM_OTP

echo "📄 npm output:"
cat "$TMPFILE"
echo ""

# Extract token from "Created token npm_XXXX" line
NPM_TOKEN=$(grep -oE 'npm_[A-Za-z0-9]+' "$TMPFILE" || true)
rm -f "$TMPFILE"

if [[ -z "$NPM_TOKEN" || "$NPM_TOKEN" == "null" ]]; then
  echo "❌ Failed to extract token from npm output"
  exit 1
fi

echo "✅ npm token created"

# ── Step 4: Upsert GitHub org secret (set handles both create and update)
echo "🔄 Upserting GitHub org secret '$SECRET_NAME' on org '$NPM_ORG'..."

gh secret set "$SECRET_NAME" \
  --body "$NPM_TOKEN" \
  --org "$NPM_ORG" \
  --visibility "$VISIBILITY"

echo "✅ Secret '$SECRET_NAME' set on org '$NPM_ORG' (visibility: $VISIBILITY)"

# ── Cleanup
unset NPM_TOKEN
echo "🎉 Done"
