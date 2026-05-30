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

# ── Configuration ─────────────────────────────────────────
NPM_ORG="homebridge"
SECRET_NAME="NPM_TOKEN"
TOKEN_NAME="Homebridge CI Token"
EXPIRES=90
VISIBILITY="all"

PACKAGES=(
  homebridge
  homebridge-config-ui-x
  homebridge-plugin-ui-utils
)
# ──────────────────────────────────────────────────────────

# ── Step 1: Revoke any existing npm tokens with the same name
echo "🔍 Checking for existing npm tokens named '$TOKEN_NAME'..."

EXISTING_TOKENS=$(npm token list --json 2>/dev/null | jq -r \
  --arg name "$TOKEN_NAME" \
  '.[] | select(.name == $name) | .id')

if [[ -n "$EXISTING_TOKENS" ]]; then
  while IFS= read -r TOKEN_ID; do
    echo "🗑  Revoking existing token ID: $TOKEN_ID"
    npm token revoke "$TOKEN_ID"
  done <<< "$EXISTING_TOKENS"
  echo "✅ Existing tokens revoked"
else
  echo "ℹ️  No existing tokens found with that name"
fi

# ── Step 2: Build repeated --packages flags
PACKAGE_FLAGS=""
for pkg in "${PACKAGES[@]}"; do
  PACKAGE_FLAGS="$PACKAGE_FLAGS --packages=$pkg"
done

# ── Step 3: Create new npm token
echo "🔑 Creating new npm token..."
NPM_TOKEN=$(npm token create \
  --name="$TOKEN_NAME" \
  $PACKAGE_FLAGS \
  --packages-and-scopes-permission=read-write \
  --bypass-2fa \
  --expires=$EXPIRES \
  --json | jq -r '.token')

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
