# Deprecate Past Pre-Releases

A reusable GitHub Action that:

1. **Deprecates old npm pre-release versions** – keeps the 5 most recent alpha/beta versions on npm and deprecates everything older.
2. **Cleans up GitHub pre-release releases and Git tags** – deletes GitHub releases and associated Git tags for pre-release versions that are older than the current stable release recorded in `package.json`.

Both operations default to **dry-run mode**, which prints exactly what _would_ happen without making any actual changes.

---

## Usage

Create the file `.github/workflows/deprecate-past-pre-releases.yml` in your repository with the following content:

```yaml
name: Deprecate Past Pre-Releases
run-name: Deprecate Past Pre-Releases - ${{ inputs.execute && 'Execute' || 'Dry Run' }}

on:
  workflow_dispatch:
    inputs:
      execute:
        description: Execute the deprecation and cleanup actions. Default is dry run (false).
        type: boolean
        default: false

permissions:
  contents: write

concurrency:
  group: deprecate-previous-pre-release-data
  cancel-in-progress: true

jobs:
  deprecate-previous-pre-release-data:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Deprecate Past Pre-Releases
        uses: homebridge/Deprecate-Past-Pre-Releases@v1
        with:
          execute: ${{ inputs.execute }}
          npm-token: ${{ secrets.NPM_DEPRECATION_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Then add the following secret to your repository (**Settings → Secrets and variables → Actions**):

| Secret | Description |
|--------|-------------|
| `NPM_DEPRECATION_TOKEN` | An npm access token with `read-write` permission on the package, used to mark old pre-release versions as deprecated. Only required when running in execute mode. |

> **Tip:** Run the workflow without ticking the *Execute* checkbox first to preview exactly which npm versions would be deprecated and which GitHub releases/tags would be deleted — no changes are made in dry-run mode.

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `execute` | No | `false` | Set to `true` to execute deprecation and cleanup. Defaults to dry-run mode. |
| `npm-token` | No* | — | NPM authentication token used to deprecate packages. *Required when `execute` is `true`. |
| `github-token` | No | Built-in `GITHUB_TOKEN` | GitHub token used to delete pre-release GitHub releases and Git tags. |
| `node-version` | No | `lts/*` | Node.js version to use when running npm commands. |

---

## How it works

### npm pre-release deprecation (`scripts/deprecate_npm_prereleases.sh`)

- Reads the package name and current stable version from `package.json`.
- Fetches all non-deprecated `alpha` and `beta` versions from the npm registry.
- Sorts versions in descending semver order and keeps the **5 most recent** as active.
- All older pre-release versions are deprecated with the message:  
  _"This pre-release version is deprecated in favor of the latest release."_
- Handles npm `429` rate-limit responses gracefully.

### GitHub pre-release cleanup (`scripts/github_prerelease_cleanup.sh`)

- Reads the current stable version from `package.json`.
- Lists all GitHub releases whose tag names contain a pre-release segment (`-`).
- Deletes any such release whose base version is **older than or equal to** the current stable version.
- Performs the same check for Git tags and deletes matching ones.

Both scripts can also be run locally:

```bash
# Dry run (default)
bash scripts/deprecate_npm_prereleases.sh
bash scripts/github_prerelease_cleanup.sh

# Execute
bash scripts/deprecate_npm_prereleases.sh --execute
bash scripts/github_prerelease_cleanup.sh --execute

# Or via environment variable
EXECUTE=1 bash scripts/deprecate_npm_prereleases.sh
```

---

## Development

### Running tests

Tests use [bats-core](https://github.com/bats-core/bats-core).

```bash
# Install bats (Ubuntu/Debian)
sudo apt-get install bats

# Run all tests
bats tests/

# Run a specific test file
bats tests/test_deprecate_npm_prereleases.bats
bats tests/test_github_prerelease_cleanup.bats
```

### CI

The CI workflow (`.github/workflows/ci.yml`) runs automatically on every push and pull request to `main`. It:

1. Runs the bats unit test suite.
2. Exercises the composite action itself in dry-run mode.

### Dependabot

Dependabot is configured (`.github/dependabot.yml`) to keep all GitHub Actions dependencies up to date on a weekly schedule.