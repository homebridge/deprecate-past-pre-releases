#!/usr/bin/env bats
# tests/test_deprecate_npm_prereleases.bats
# Unit tests for scripts/deprecate_npm_prereleases.sh

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

# Registry response with 6 alpha versions (should deprecate 1, keep 5)
SIX_ALPHA_VERSIONS='{
  "versions": {
    "1.0.0-alpha.1": {"version": "1.0.0-alpha.1"},
    "1.0.0-alpha.2": {"version": "1.0.0-alpha.2"},
    "1.0.0-alpha.3": {"version": "1.0.0-alpha.3"},
    "1.0.0-alpha.4": {"version": "1.0.0-alpha.4"},
    "1.0.0-alpha.5": {"version": "1.0.0-alpha.5"},
    "1.0.0-alpha.6": {"version": "1.0.0-alpha.6"},
    "2.0.0":         {"version": "2.0.0"}
  }
}'

# Registry response with only 4 alpha versions (all should be kept)
FOUR_ALPHA_VERSIONS='{
  "versions": {
    "1.0.0-alpha.1": {"version": "1.0.0-alpha.1"},
    "1.0.0-alpha.2": {"version": "1.0.0-alpha.2"},
    "1.0.0-alpha.3": {"version": "1.0.0-alpha.3"},
    "1.0.0-alpha.4": {"version": "1.0.0-alpha.4"},
    "2.0.0":         {"version": "2.0.0"}
  }
}'

# Registry response with a mix of alpha, beta, and already-deprecated versions
MIXED_VERSIONS='{
  "versions": {
    "1.0.0-alpha.1": {"version": "1.0.0-alpha.1", "deprecated": "old"},
    "1.0.0-alpha.2": {"version": "1.0.0-alpha.2"},
    "1.0.0-beta.1":  {"version": "1.0.0-beta.1"},
    "1.0.0-beta.2":  {"version": "1.0.0-beta.2"},
    "1.0.0-beta.3":  {"version": "1.0.0-beta.3"},
    "1.0.0-beta.4":  {"version": "1.0.0-beta.4"},
    "1.0.0-beta.5":  {"version": "1.0.0-beta.5"},
    "2.0.0":         {"version": "2.0.0"}
  }
}'

setup() {
  WORK_DIR="$(mktemp -d)"
  MOCK_BIN_DIR="$(mktemp -d)"

  # npm mock - must NOT be called in dry-run; fails loudly if it is
  cat > "$MOCK_BIN_DIR/npm" <<'MOCK'
#!/usr/bin/env bash
echo "Error: npm was called unexpectedly in dry-run mode: $*" >&2
exit 1
MOCK
  chmod +x "$MOCK_BIN_DIR/npm"

  export PATH="$MOCK_BIN_DIR:$PATH"
  export WORK_DIR MOCK_BIN_DIR
  cd "$WORK_DIR"
}

teardown() {
  rm -rf "$WORK_DIR" "$MOCK_BIN_DIR"
}

# Helper: write a curl mock that outputs a fixed JSON response
write_curl_mock() {
  local response="$1"
  cat > "$MOCK_BIN_DIR/curl" <<MOCK
#!/usr/bin/env bash
cat <<'RESPONSE'
${response}
RESPONSE
MOCK
  chmod +x "$MOCK_BIN_DIR/curl"
}

# Helper: write a minimal package.json in the current working directory
write_package_json() {
  local name="${1:-test-package}"
  local version="${2:-2.0.0}"
  printf '{"name":"%s","version":"%s"}\n' "$name" "$version" > package.json
}

# ---------------------------------------------------------------------------
# Error-condition tests
# ---------------------------------------------------------------------------

@test "exits with error when package.json is missing" {
  # No package.json in WORK_DIR
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -ne 0 ]
}

@test "exits with error when package name is missing from package.json" {
  echo '{"version":"1.0.0"}' > package.json
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
}

@test "exits with error when package version is missing from package.json" {
  echo '{"name":"test-package"}' > package.json
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
}

@test "exits with error for unknown command-line option" {
  write_package_json
  write_curl_mock "$SIX_ALPHA_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh" --unknown-flag
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Dry-run mode tests
# ---------------------------------------------------------------------------

@test "dry run is the default mode" {
  write_package_json
  write_curl_mock "$SIX_ALPHA_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN MODE"* ]]
}

@test "dry run does not call npm deprecate" {
  write_package_json
  write_curl_mock "$SIX_ALPHA_VERSIONS"
  # npm mock exits 1 if called; the test would fail if npm were invoked
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
}

@test "dry run with 6 alpha versions deprecates only the oldest (alpha.1)" {
  write_package_json
  write_curl_mock "$SIX_ALPHA_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0-alpha.1"* ]]
}

@test "dry run with 6 alpha versions keeps the 5 most recent" {
  write_package_json
  write_curl_mock "$SIX_ALPHA_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  # alpha.2 through alpha.6 must NOT appear as candidates to deprecate
  [[ "$output" != *'Would run: npm deprecate test-package@"1.0.0-alpha.2"'* ]]
  [[ "$output" != *'Would run: npm deprecate test-package@"1.0.0-alpha.6"'* ]]
}

@test "dry run with 4 alpha versions deprecates nothing" {
  write_package_json
  write_curl_mock "$FOUR_ALPHA_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No versions were deprecated"* ]]
}

@test "dry run skips already-deprecated versions from registry" {
  write_package_json
  write_curl_mock "$MIXED_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  # alpha.1 is already deprecated in the registry mock - must not be listed
  [[ "$output" != *"1.0.0-alpha.1"* ]]
}

@test "dry run summary reports DRY RUN MODE" {
  write_package_json
  write_curl_mock "$FOUR_ALPHA_VERSIONS"
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN MODE"* ]]
}

@test "dry run succeeds when registry returns no pre-release versions" {
  write_package_json
  write_curl_mock '{"versions":{"1.0.0":{"version":"1.0.0"}}}'
  run bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No versions were deprecated"* ]]
}

@test "EXECUTE env var set to 'false' triggers dry run" {
  write_package_json
  write_curl_mock "$FOUR_ALPHA_VERSIONS"
  run env EXECUTE=false bash "$SCRIPTS_DIR/deprecate_npm_prereleases.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN MODE"* ]]
}
