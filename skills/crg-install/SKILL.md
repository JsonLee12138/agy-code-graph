---
name: crg-install
description: Installs or upgrades the code-review-graph CLI globally for Google Antigravity by reading https://github.com/tirth8205/code-review-graph and running install-crg.sh (uv tool / pipx / pip, Python 3.10+). Use when code-review-graph is not installed or when running /agy-code-graph:crg-install.
---

# `/agy-code-graph:crg-install` — Global `code-review-graph` CLI Installer

Follow this deterministic 3-step workflow to check, install, or upgrade the `code-review-graph` CLI globally on the user's machine.

> **Scope Note**: This skill **only** installs the global `code-review-graph` CLI binary (no persistent background daemon is started, and `code-review-graph install` is not used because `agy-code-graph` natively provides the MCP config, skills, rules, and hooks). To initialize a specific repository after installing the CLI, use `/agy-code-graph:crg-init`.

## Step 1: Check Current CLI & Environment Status

Run this skill's `install-crg.sh --check` script:

```bash
bash "<path-to-crg-install-skill>/scripts/install-crg.sh" --check
```

Inspect the JSON output fields:
- `crgInstalled`: Whether `code-review-graph` is currently available on `PATH`.
- `crgBin`: Resolved binary path of `code-review-graph`.
- `crgVersion`: Installed version string (if installed).
- `uvAvailable`: Whether `uv` (`uv tool install`) is available.
- `pipxAvailable`: Whether `pipx` (`pipx install`) is available.
- `python3Available` / `pythonVersion`: Available Python 3.10+ interpreter.

If `crgInstalled` is `true` and the user did not ask to upgrade, report the installed version and binary path, and let the user know they can run `/agy-code-graph:crg-init` inside any Git repository.

## Step 2: Read Official Repository & Install `code-review-graph` CLI

When `crgInstalled` is `false` (or when upgrading):
1. **Read the official upstream repository** at **`https://github.com/tirth8205/code-review-graph`** (e.g., fetch `https://raw.githubusercontent.com/tirth8205/code-review-graph/staging/README.md`) to review the latest upstream requirements and installation options (such as optional `[embeddings]` extras).
2. Run `install-crg.sh` (pass `--upgrade` if upgrading an existing installation):

```bash
bash "<path-to-crg-install-skill>/scripts/install-crg.sh"
```

`install-crg.sh` automatically selects the cleanest isolated global installer available on the system:
1. `uv tool install code-review-graph` (if `uv` is installed)
2. `pipx install code-review-graph` (if `pipx` is installed)
3. `python3 -m pip install --user code-review-graph` (using a detected Python 3.10+ interpreter)

*(Do **not** run `code-review-graph install` or `code-review-graph watch` daemon processes.)*

## Step 3: Verify Installation & Next Steps

1. Confirm that the JSON output from `install-crg.sh` reports `"crgInstalled": true` and a non-empty `"crgVersion"`.
2. Inform the user that `code-review-graph` is globally installed and ready, and suggest running **`/agy-code-graph:crg-init`** in their project workspace to inject `.agents/rules/crg.md`, configure the Git `post-commit` hook, and build `.code-review-graph/graph.db`.
