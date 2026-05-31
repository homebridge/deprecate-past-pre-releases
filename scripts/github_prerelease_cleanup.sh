#!/usr/bin/env bash

set -uo pipefail


# Defaults to dry run unless --execute flag or EXECUTE=1 env var is set
EXECUTE=${EXECUTE:-0}

# Normalize EXECUTE: accept "true"/"false" as well as "1"/"0"
if [ "${EXECUTE}" = "true" ] || [ "${EXECUTE}" = "1" ]; then
  EXECUTE=1
else
  EXECUTE=0
fi

# Parse command line options
while [ $# -gt 0 ]; do
  case "$1" in
    --execute)
      EXECUTE=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--execute]  (or set EXECUTE=1 to enable execution)" >&2
      exit 1
      ;;
  esac
  shift
done

# Read package version from package.json
LATEST_VERSION=$(jq -r .version package.json)
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
  echo "Error: could not extract version from package.json" >&2
  exit 1
fi
echo "Latest version found in package.json: $LATEST_VERSION"
if [ "$EXECUTE" = "0" ]; then
  echo "*** DRY RUN MODE: delete commands will be printed but not executed ***"
fi
echo ""

DELETED_RELEASES=()
DELETED_TAGS=()

# Helper to write to both stdout and, only when running in a GitHub Actions
# workflow context (GITHUB_STEP_SUMMARY is set), also append to the job summary.
summary() {
  echo "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

echo ""
echo "Finding pre-release GitHub releases..."
# Strip v prefix before sorting to match npm script behavior, then restore
ALL_RELEASE_TAGS=$(gh release list --limit 100 --json tagName --jq '.[] | select(.tagName | test("-alpha\\.|-beta\\."; "i")) | .tagName' \
  | sed 's/^v//' | sort -V -r | sed 's/^/v/')
RELEASE_COUNT=$(echo "$ALL_RELEASE_TAGS" | grep -c . || true)
echo "Found $RELEASE_COUNT pre-release GitHub releases (keeping 5 most recent):"
RELEASE_TAGS_TO_DELETE=$(echo "$ALL_RELEASE_TAGS" | tail -n +6)

while read -r TAG; do
  [ -z "$TAG" ] && continue
  if [ "$EXECUTE" = "0" ]; then
    echo "* [DRY RUN] Would run: gh release delete \"$TAG\" --yes"
    DELETED_RELEASES+=("$TAG")
  else
    echo "* Deleting GitHub release: $TAG"
    gh release delete "$TAG" --yes
    DELETED_RELEASES+=("$TAG")
  fi
done <<< "$RELEASE_TAGS_TO_DELETE"

echo ""
echo "Finding pre-release Git tags..."
git fetch --tags
# Strip v prefix before sorting to match npm script behavior, then restore
ALL_GIT_TAGS=$(git tag -l | grep -E '\-(alpha|beta)\.' \
  | sed 's/^v//' | sort -V -r | sed 's/^/v/')
TAG_COUNT=$(echo "$ALL_GIT_TAGS" | grep -c . || true)
echo "Found $TAG_COUNT pre-release Git tags (keeping 5 most recent):"
GIT_TAGS_TO_DELETE=$(echo "$ALL_GIT_TAGS" | tail -n +6)

while read -r TAG; do
  [ -z "$TAG" ] && continue
  if [ "$EXECUTE" = "0" ]; then
    echo "* [DRY RUN] Would run: git push origin --delete refs/tags/$TAG"
    DELETED_TAGS+=("$TAG")
  else
    echo "* Deleting tag: $TAG"
    git push origin --delete "refs/tags/$TAG"
    DELETED_TAGS+=("$TAG")
  fi
done <<< "$GIT_TAGS_TO_DELETE"

summary ""
summary "## GitHub Pre-release Cleanup Summary"
if [ "$EXECUTE" = "0" ]; then
  summary "> **DRY RUN MODE** - no releases or tags were actually deleted."
fi
summary "* Latest version: \`$LATEST_VERSION\`"
if [ ${#DELETED_RELEASES[@]} -eq 0 ]; then
  summary "* No GitHub releases were deleted."
else
  summary "* Deleted ${#DELETED_RELEASES[@]} GitHub releases:"
  for TAG in "${DELETED_RELEASES[@]}"; do
    summary "  * \`$TAG\`"
  done
fi
if [ ${#DELETED_TAGS[@]} -eq 0 ]; then
  summary "* No Git tags were deleted."
else
  summary "* Deleted ${#DELETED_TAGS[@]} Git tags:"
  for TAG in "${DELETED_TAGS[@]}"; do
    summary "  * \`$TAG\`"
  done
fi
