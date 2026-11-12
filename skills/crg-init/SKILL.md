---
name: crg-init
description: Bootstraps code-review-graph in the current repository: injects .agents/rules/crg.md, configures .gitignore and atomic-locked Git post-commit hooks, and runs initial code-review-graph build. Requires code-review-graph to be installed (directs to /agy-code-graph:crg-install if missing). Use when initializing a repository or running /agy-code-graph:crg-init.
---

# `/agy-code-graph:crg-init` — Workspace Rule, Hook & AST Graph Initializer

Follow this deterministic 3-step workflow to initialize the active repository for AST graph-assisted coding, review, and refactoring.

> **Prerequisite**: This skill requires `code-review-graph` to be installed. It does **not** install the CLI itself — if `crgInstalled` is `false` (and `uvx` is unavailable), instruct the user or invoke **`/agy-code-graph:crg-install`** first.

## Step 1: Check Workspace & CLI Readiness

Run this skill's `init-crg.sh --check` against the active workspace root:

```bash
bash "<path-to-crg-init-skill>/scripts/init-crg.sh" --check "<workspace_root>"
```

Inspect the JSON output fields:
- `crgInstalled` / `uvxAvailable`: If both are `false`, stop and run **`/agy-code-graph:crg-install`** first.
- `ruleInstalled`: Whether `.agents/rules/crg.md` is already present.
- `gitHookInstalled`: Whether the idempotent `post-commit` hook is installed.
- `graphDbExists`: Whether `.code-review-graph/graph.db` has been built.

## Step 2: Initialize Workspace Rule, Git Hook & AST Knowledge Graph

Run `init-crg.sh` on the target workspace:

```bash
bash "<path-to-crg-init-skill>/scripts/init-crg.sh" "<workspace_root>"
```

### Supported Flags
- `--with-local-hooks`: Copies `scripts/crg-hook.sh` into the workspace and non-destructively merges `crg-transaction-sync` (`PostToolUse` + `Stop`) into `<workspace_root>/.agents/hooks.json` (preserving any existing hooks such as `agy-harness`).
- `--force`: Overwrites an existing `<workspace_root>/.agents/rules/crg.md` with the latest template.
- `--skip-build`: Scaffolds `.agents/rules/crg.md`, `.gitignore`, and the `post-commit` hook without running `code-review-graph build`.

### What `init-crg.sh` Configures Automatically
1. **Workspace Rule (`.agents/rules/crg.md`)**: Enforces Graph-First MCP queries (`get_minimal_context_tool`, `semantic_search_nodes_tool(include_source=true)`, `query_graph_tool`, `get_impact_radius_tool`, `get_review_context_tool`), explicit `repo_root="<workspace_root>"` routing, and the Zero Double-Read Policy.
2. **Git Ignore Hygiene**: Appends `.code-review-graph/` to `<workspace_root>/.gitignore` and writes `*` to `<workspace_root>/.code-review-graph/.gitignore`.
3. **Idempotent Atomic-Locked `post-commit` Hook**: Installs a background `post-commit` hook in `.husky/post-commit` (if `.husky/` exists) or `.git/hooks/post-commit` (preserving pre-existing hook commands) that shares `.code-review-graph/update.lock.d` with the Antigravity `Stop` hook and closes all stdio pipes (`>/dev/null 2>&1 </dev/null &`).
4. **Initial Full Graph Build**: Acquires `.code-review-graph/update.lock.d` and runs `code-review-graph build --repo "<workspace_root>"` to generate `.code-review-graph/graph.db`.

## Step 3: Verify & Report Summary

Confirm that the JSON output from `init-crg.sh` reports:
- `"ruleInstalled": true`
- `"gitHookInstalled": true` (when inside a Git repository)
- `"graphDbExists": true`

Report the initialization status to the user and suggest next graph-powered workflows such as `/agy-code-graph:explore-codebase` or `/agy-code-graph:review-changes`.
