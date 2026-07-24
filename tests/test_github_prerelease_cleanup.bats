#!/usr/bin/env bats
# tests/test_github_prerelease_cleanup.bats
# Unit tests for scripts/github_prerelease_cleanup.sh

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

setup() {
  WORK_DIR="$(mktemp -d)"
  MOCK_BIN_DIR="$(mktemp -d)"

  # Default gh mock: returns two pre-release tags older than 2.0.0
  cat > "$MOCK_BIN_DIR/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "release list")
    printf 'v1.0.0-alpha.1\nv1.0.0-beta.1\n'
    ;;
  "release delete")
    # silent success
    ;;
  *)
    echo "Unexpected gh call: $*" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/gh"

  # Default git mock: fetch is a no-op; tag -l returns pre-release tags
  cat > "$MOCK_BIN_DIR/git" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  fetch)
    ;;
  tag)
    printf 'v1.0.0-alpha.1\nv1.0.0-beta.1\n'
    ;;
  push)
    # silent success
    ;;
  *)
    echo "Unexpected git call: $*" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/git"

  export PATH="$MOCK_BIN_DIR:$PATH"
  export WORK_DIR MOCK_BIN_DIR
  cd "$WORK_DIR"
}

teardown() {
  rm -rf "$WORK_DIR" "$MOCK_BIN_DIR"
}

# Helper: write a minimal package.json in the current working directory
write_package_json() {
  local version="${1:-2.0.0}"
  printf '{"name":"test-package","version":"%s"}\n' "$version" > package.json
}

# ---------------------------------------------------------------------------
# Error-condition tests
# ---------------------------------------------------------------------------

@test "exits with error when package.json is missing" {
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -ne 0 ]
}

@test "exits with error when package version is missing from package.json" {
  echo '{"name":"test-package"}' > package.json
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
}

@test "exits with error for unknown command-line option" {
  write_package_json
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh" --unknown-flag
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Dry-run mode tests
# ---------------------------------------------------------------------------

@test "dry run is the default mode" {
  write_package_json
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN MODE"* ]]
}

@test "dry run does not call gh release delete" {
  write_package_json
  # Replace gh mock so that 'release delete' fails loudly
  cat > "$MOCK_BIN_DIR/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "release list")
    printf 'v1.0.0-alpha.1\n'
    ;;
  "release delete")
    echo "Error: gh release delete must not be called in dry-run mode" >&2
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/gh"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
}

@test "dry run does not call git push to delete tags" {
  write_package_json
  # Replace git mock so that 'push' fails loudly
  cat > "$MOCK_BIN_DIR/git" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  fetch) ;;
  tag) printf 'v1.0.0-alpha.1\n' ;;
  push)
    echo "Error: git push must not be called in dry-run mode" >&2
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/git"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
}

@test "dry run keeps every pre-release when fewer than the keep count exist" {
  # The two mocked pre-releases are within the default keep of 5, so neither
  # is a deletion candidate
  write_package_json "2.0.0"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No GitHub releases were deleted"* ]]
}

@test "keep 0 lists every pre-release release and tag" {
  write_package_json "2.0.0"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh" --keep 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1.0.0-alpha.1"* ]]
  [[ "$output" == *"v1.0.0-beta.1"* ]]
}

@test "KEEP env var of 0 lists every pre-release release and tag" {
  write_package_json "2.0.0"
  KEEP=0 run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1.0.0-alpha.1"* ]]
  [[ "$output" == *"v1.0.0-beta.1"* ]]
}

@test "keep 1 retains only the most recent pre-release" {
  write_package_json "2.0.0"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh" --keep 1
  [ "$status" -eq 0 ]
  # v1.0.0-beta.1 sorts above v1.0.0-alpha.1, so alpha.1 is the one dropped
  [[ "$output" == *"v1.0.0-alpha.1"* ]]
  [[ "$output" != *"Would run: gh release delete \"v1.0.0-beta.1\""* ]]
}

@test "exits with error for a non-numeric keep value" {
  write_package_json "2.0.0"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh" --keep abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
}

@test "dry run keeps a single pre-release regardless of the package version" {
  # Selection is by recency, not by comparison against the package version, so
  # a lone pre-release is kept even though its base version is newer
  write_package_json "1.0.0"
  # Override gh mock to return a tag that is newer
  cat > "$MOCK_BIN_DIR/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "release list")
    printf 'v2.0.0-alpha.1\n'
    ;;
  *)
    exit 0
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/gh"
  cat > "$MOCK_BIN_DIR/git" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  fetch) ;;
  tag) printf 'v2.0.0-alpha.1\n' ;;
  *) ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/git"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No GitHub releases were deleted"* ]]
  # Must NOT appear as a candidate to delete
  [[ "$output" != *"Would run: gh release delete"* ]]
}

@test "dry run summary shows correct latest version" {
  write_package_json "2.0.0"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Latest version: \`2.0.0\`"* ]]
}

@test "dry run succeeds when there are no pre-release releases or tags" {
  write_package_json
  cat > "$MOCK_BIN_DIR/gh" <<'MOCK'
#!/usr/bin/env bash
# release list returns nothing
MOCK
  chmod +x "$MOCK_BIN_DIR/gh"
  cat > "$MOCK_BIN_DIR/git" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  fetch) ;;
  tag)   ;;
  *)     ;;
esac
MOCK
  chmod +x "$MOCK_BIN_DIR/git"
  run bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No GitHub releases were deleted"* ]]
  [[ "$output" == *"No Git tags were deleted"* ]]
}

@test "EXECUTE env var set to 'false' triggers dry run" {
  write_package_json
  run env EXECUTE=false bash "$SCRIPTS_DIR/github_prerelease_cleanup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN MODE"* ]]
}
