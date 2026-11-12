# Specification (SPEC): `agy-code-graph` Antigravity Plugin (v3)

> Single Source of Truth (Disk SSoT) for behavior and acceptance criteria. Lock before invoking `slice-builder`.

## 1. Objective & Problem Statement
- **Goal:** Build `agy-code-graph`, a native Google Antigravity plugin that packages:
  1. **Unrestricted `code-review-graph` MCP Server** (`mcp_config.json`) exposing all upstream CRG tools and prompts via `stdio` (`code-review-graph serve` with `uvx code-review-graph serve` fallback), paired with explicit `repo_root="<workspace_root>"` rule routing to prevent multi-workspace cwd drift;
  2. **All 7 upstream CRG skills** synced verbatim from `https://github.com/tirth8205/code-review-graph/tree/staging/skills` (`build-graph`, `debug-issue`, `explore-codebase`, `refactor-safely`, `review-changes`, `review-delta`, `review-pr`);
  3. **Dedicated `/agy-code-graph:crg-install` CLI installation skill** (`skills/crg-install/SKILL.md` + `install-crg.sh`) responsible solely for checking and globally installing the `code-review-graph` CLI (reading `https://github.com/tirth8205/code-review-graph` and installing via `uv tool` / `pipx` / `pip`, with no persistent daemon);
  4. **Decoupled `/agy-code-graph:crg-init` workspace bootstrap skill** (`skills/crg-init/SKILL.md` + `init-crg.sh`) that assumes `code-review-graph` is installed (prompting to run `/agy-code-graph:crg-install` if missing), injects `.agents/rules/crg.md`, configures `.gitignore` + atomic-locked Git `post-commit` hook, and runs initial `code-review-graph build`;
  5. **Pure-CLI deterministic lifecycle hooks** (`hooks.json` -> `scripts/crg-hook.sh`) automating `PostToolUse` dirty marking and `Stop` (`fullyIdle`) detached incremental graph updates using pure `code-review-graph update` / `code-review-graph build` CLI commands;
  6. **Single `.github/workflows/ci.yml` seamless upstream skill sync on `main` push** (aligned with `innerfire-dev-packages` CI style: no cron, no PR noise — pulls upstream skills on `push` to `main` and commits/pushes `[skip ci]` directly if changed).
- **Tier Classification:** `Tier M`

## 2. Non-Goals (Scope Guardrails)
- Do **not** filter, block, or wrap MCP JSON-RPC tool schemas — expose 100% of `code-review-graph serve` tools natively.
- Do **not** run a persistent background daemon (`watch` or custom server) in `crg-install`; MCP uses `stdio` on demand and Hooks invoke the `code-review-graph` CLI directly.
- Do **not** embed Python `code_review_graph` library imports inside `scripts/crg-hook.sh` for graph updates — use pure CLI commands (`code-review-graph update` / `code-review-graph build`).
- Do **not** use cron schedules or PR-creation bots for upstream skill syncing — sync seamlessly inside `.github/workflows/ci.yml` on `push` to `main`.

## 3. Project Structure & Interface Contracts

### 3.1 Target Plugin Repository Layout
```text
/Users/jsonlee/Projects/agy-code-graph/
├── plugin.json                                     # Native AGY plugin manifest (name: "agy-code-graph")
├── assets/
│   └── logo.svg                                    # Square SVG graph icon with ~10% margin, high contrast
├── mcp_config.json                                 # Stdio MCP server "agy-code-graph" -> `code-review-graph serve` (with uvx fallback)
├── hooks.json                                      # Plugin root hooks: PostToolUse (mark-dirty) + Stop (sync-on-stop)
├── rules/
│   └── AGENTS.md                                   # Lightweight Global Workspace Detector rule (< 1.5 KB)
├── skills/
│   ├── crg-install/                                # Dedicated CLI installer skill (/agy-code-graph:crg-install)
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       └── install-crg.sh                      # Global CLI installer & checker (--check / uv tool / pipx / pip)
│   ├── crg-init/                                   # Workspace bootstrap skill (/agy-code-graph:crg-init)
│   │   ├── SKILL.md
│   │   ├── references/
│   │   │   ├── crg-rule-template.md                # Template written to <workspace>/.agents/rules/crg.md
│   │   │   └── hooks-template.json                 # Optional workspace hooks template for --with-local-hooks
│   │   └── scripts/
│   │       └── init-crg.sh                         # Deterministic workspace initializer (requires CLI installed; prompts crg-install if missing)
│   ├── build-graph/SKILL.md                        # Upstream verbatim from tirth8205/code-review-graph@staging
│   ├── debug-issue/SKILL.md                        # Upstream verbatim
│   ├── explore-codebase/SKILL.md                   # Upstream verbatim
│   ├── refactor-safely/SKILL.md                    # Upstream verbatim
│   ├── review-changes/SKILL.md                     # Upstream verbatim
│   ├── review-delta/SKILL.md                       # Upstream verbatim
│   └── review-pr/SKILL.md                          # Upstream verbatim
├── scripts/
│   ├── crg-hook.sh                                 # Pure-CLI POSIX sh lifecycle & git hook runner (mark-dirty | sync-on-stop | sync-now)
│   ├── install-crg.sh                              # Convenience wrapper delegating to skills/crg-install/scripts/install-crg.sh
│   ├── init-crg.sh                                 # Convenience wrapper delegating to skills/crg-init/scripts/init-crg.sh
│   ├── sync-upstream-skills.sh                     # Script to pull latest 7 skills from tirth8205/code-review-graph@staging
│   ├── gate-check.sh                               # Software 1.0 gate (`agy plugin validate . --strict` + syntax + `tests/run-tests.sh`)
│   └── harness-approval-gate.sh                    # Existing Harness PreToolUse gate (preserved untouched)
├── .github/
│   └── workflows/
│       └── ci.yml                                  # Push/PR verification + seamless upstream skills sync & commit on push to `main`
├── tests/
│   └── run-tests.sh                                # Deterministic Software 1.0 integration test suite
├── .gitignore                                      # Ignores `.code-review-graph/`, `__pycache__/`, temp files
└── README.md                                       # Usage guide for AGY CLI / IDE / 2.0 + Python SDK
```

### 3.2 Component Contracts

1. **Manifest (`plugin.json`) & Logo (`assets/logo.svg`)**:
   - `name`: `"agy-code-graph"`, `displayName`: `"AGY Code Graph"`, `version`: `"0.1.0"`, `logo`: `"assets/logo.svg"`, `suggestedPrompts` featuring `/agy-code-graph:crg-install`, `/agy-code-graph:crg-init`, `/agy-code-graph:review-changes`.
   - Passes `agy plugin validate . --strict --json` with `findings: []` and `components: { skills: 9, rules: 1, hooks: 1, mcpServers: 1 }`.

2. **Full-Access MCP Config (`mcp_config.json`)**:
   - Server key: `"agy-code-graph"`.
   - Runs `exec code-review-graph serve` if `code-review-graph` is on `PATH`, else falls back to `exec uvx code-review-graph serve` (if neither is found, prints a clear message to run `/agy-code-graph:crg-install`).
   - Zero tool filtering: all upstream CRG tools and prompts remain available.

3. **Dedicated Install Skill (`skills/crg-install/SKILL.md` + `skills/crg-install/scripts/install-crg.sh`)**:
   - `install-crg.sh --check`: Outputs JSON with `crgInstalled`, `crgBin`, `crgVersion`, `uvAvailable`, `pipxAvailable`, `python3Available`, `pythonVersion` and exits `0`.
   - `install-crg.sh`: Installs `code-review-graph` globally using `uv tool install code-review-graph` -> `pipx install code-review-graph` -> `python3 -m pip install --user code-review-graph` (Python 3.10+), and verifies `code-review-graph --version`.
   - `SKILL.md`: Instructs the agent to run `install-crg.sh --check`, read `https://github.com/tirth8205/code-review-graph` (`README.md`) when installing or troubleshooting, run `install-crg.sh`, and then suggest `/agy-code-graph:crg-init` to initialize a repository.

4. **Decoupled Init Skill (`skills/crg-init/SKILL.md` + `skills/crg-init/scripts/init-crg.sh`)**:
   - Does **not** perform CLI installation. If `code-review-graph` is not installed (and `uvx` is unavailable), `init-crg.sh` exits with code `2` and instructs the agent/user to run `/agy-code-graph:crg-install` first.
   - Injects `<target>/.agents/rules/crg.md`, configures `.gitignore`, installs idempotent atomic-locked `post-commit` hook, merges `.agents/hooks.json` when `--with-local-hooks` is passed, and runs `code-review-graph build --repo <target>`.

5. **Pure-CLI Lifecycle Hook Script (`hooks.json` + `scripts/crg-hook.sh`)**:
   - **`mark-dirty`**: Emits `{}`. Writes `<workspace>/.code-review-graph/.dirty` only when `error` is empty, `<workspace>` is initialized, and edited file is inside `<workspace>`.
   - **`sync-on-stop`**: Emits `{"decision":"allow"}` in `< 500ms`. When `fullyIdle` is not `false` and `.dirty` exists, acquires `mkdir "$CRG_DIR/update.lock.d"`, deletes `.dirty`, and spawns a detached background process (`>/dev/null 2>&1 </dev/null &`).
   - **`sync-now` (100% Pure CLI)**:
     - If `graph.db` does not exist: runs `code-review-graph build --repo "$WORKSPACE_ROOT"`.
     - If `graph.db` exists: runs `code-review-graph update --base HEAD --repo "$WORKSPACE_ROOT"` (to index working-tree changes against `HEAD`) and `code-review-graph update --repo "$WORKSPACE_ROOT"` (to index committed changes against `HEAD~1`), falling back to `code-review-graph build --repo "$WORKSPACE_ROOT"` if `update` fails. Zero inline Python `code_review_graph` library calls.

6. **Single `.github/workflows/ci.yml` Seamless Upstream Sync**:
   - Triggers on `push: branches: [main]` and `pull_request: branches: [main]`.
   - Permissions: `contents: write`.
   - Steps:
     1. Checkout repository (`actions/checkout@v4` with `fetch-depth: 0`);
     2. Validate shell scripts (`sh -n` / `bash -n`) and JSON manifests;
     3. Run `bash scripts/sync-upstream-skills.sh` and `bash scripts/sync-upstream-skills.sh --check-local`;
     4. On `push` to `main` (`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`), if `git status --porcelain -- skills/` is non-empty, commit as `github-actions[bot]` with message `"chore(skills): sync upstream skills [skip ci]"` and `git push origin HEAD:main`.

## 4. Boundaries
- **Always:** Keep the 7 upstream skills byte-for-byte identical to `tirth8205/code-review-graph@staging`; pass `agy plugin validate . --strict` with zero findings; use pure CLI commands in `crg-hook.sh` `sync-now`; close `stdin`/`stdout`/`stderr` (`>/dev/null 2>&1 </dev/null &`) on backgrounded hook processes.
- **Ask first:** Modifying `.agents/hooks.json` or `scripts/harness-approval-gate.sh` in this repository.
- **Never:** Restrict MCP tools in `mcp_config.json`, run a persistent background daemon in `crg-install`, or create noisy sync PRs in CI.

## 5. Verifiable Acceptance Criteria
- [x] AC-1: `agy plugin validate /Users/jsonlee/Projects/agy-code-graph --strict --json` exits `0` with `findings: []` and reports `skills: 9` (7 upstream + `crg-install` + `crg-init`), `rules: 1`, `hooks: 1`, `mcpServers: 1`.
- [x] AC-2: All 7 upstream skill files match `tirth8205/code-review-graph@staging`, and `mcp_config.json` launches `code-review-graph serve` (with `uvx` fallback) exposing `>= 20` tools.
- [x] AC-3: `skills/crg-install/SKILL.md` + `install-crg.sh` handle global `code-review-graph` detection and installation (referencing `https://github.com/tirth8205/code-review-graph`); `skills/crg-init/SKILL.md` + `init-crg.sh` decouple installation (directing to `/agy-code-graph:crg-install` when missing) and initialize `.agents/rules/crg.md`, `.gitignore`, idempotent `post-commit` hook, optional `--with-local-hooks`, and initial `code-review-graph build`.
- [x] AC-4: `scripts/crg-hook.sh mark-dirty` leaves uninitialized folders untouched, ignores `<ArtifactDir>` edits outside `workspacePaths[0]`, marks `.code-review-graph/.dirty` in initialized repos, and outputs `{}`.
- [x] AC-5: `scripts/crg-hook.sh sync-on-stop` and `sync-now` use pure `code-review-graph` CLI commands (`update --base HEAD`, `update`, `build`), output `{"decision":"allow"}` and close `stdout` in `< 1s`, defer sync when `fullyIdle: false`, share `update.lock.d` atomically with Git `post-commit`, and index modified tracked files into `graph.db`.
- [x] AC-6: `.github/workflows/sync-upstream-skills.yml` is removed, and `.github/workflows/ci.yml` runs on `push`/`pull_request` to `main` and seamlessly commits & pushes updated upstream skills with `[skip ci]` on `main` pushes; `bash scripts/gate-check.sh` exits `0`.
