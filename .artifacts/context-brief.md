# Context Brief: `agy-code-graph` Native Antigravity Plugin (v2 Redesigned)

## 1. Repository & Upstream Facts
- **Plugin Repository**: `/Users/jsonlee/Projects/agy-code-graph` (`https://github.com/JsonLee12138/agy-code-graph.git`, branch `main`).
- **Active Workspace Harness**: `agy-harness` enabled (`.agents/rules/agy-harness.md`, `.agents/hooks.json`, `scripts/gate-check.sh`, `.artifacts/*`).
- **Upstream `code-review-graph` Repository (`staging` branch)**:
  - URL: `https://github.com/tirth8205/code-review-graph`
  - Upstream `skills/` (`https://github.com/tirth8205/code-review-graph/tree/staging/skills`) contains **7 official skill directories**:
    1. `skills/build-graph/SKILL.md`
    2. `skills/debug-issue/SKILL.md`
    3. `skills/explore-codebase/SKILL.md`
    4. `skills/refactor-safely/SKILL.md`
    5. `skills/review-changes/SKILL.md`
    6. `skills/review-delta/SKILL.md`
    7. `skills/review-pr/SKILL.md`
  - Verified with `agy plugin validate --strict --json`: upstream `SKILL.md` files (including `argument-hint:` frontmatter) pass strict validation with **0 errors and 0 warnings** when `logo` is configured in `plugin.json` and plugin rules live in `rules/AGENTS.md`.
- **Sibling Architectural Pattern (`agy-harness`)**:
  - Uses a lightweight **Global Workspace Detector** in plugin `rules/AGENTS.md` + an explicit bootstrap skill (`skills/harness-init/SKILL.md` + `scripts/init-harness.sh`) that injects workspace rules into `<target>/.agents/rules/`, Leaving uninitialized workspaces clean.

## 2. Key Architectural Decisions (Aligned with User Feedback)
1. **No MCP Tool Filtering — Full Native `code-review-graph serve` Access**:
   - Upstream skills (`explore-codebase`, `refactor-safely`, `debug-issue`, `build-graph`, `review-delta`, `review-pr`) rely on the full suite of CRG MCP tools (`get_minimal_context_tool`, `list_graph_stats_tool`, `build_or_update_graph_tool`, `get_architecture_overview_tool`, `list_communities_tool`, `get_community_tool`, `get_flow_tool`, `get_affected_flows_tool`, `refactor_tool`, `apply_refactor_tool`, `semantic_search_nodes_tool`, `query_graph_tool`, `get_impact_radius_tool`, `get_review_context_tool`, `detect_changes_tool`, etc.).
   - `mcp_config.json` mounts `code-review-graph serve` directly (with macOS/Linux GUI `PATH` discovery for Homebrew / `~/.local/bin` / Python.framework + `uvx code-review-graph serve` fallback via `exec`), exposing 100% of upstream tools and prompts untouched.
2. **Dedicated Bootstrap Skill (`skills/crg-init/SKILL.md` -> `/agy-code-graph:crg-init`)**:
   - Checks whether `code-review-graph` is installed (`init-crg.sh --check`).
   - **When missing**: `SKILL.md` explicitly instructs the agent to fetch/read `https://github.com/tirth8205/code-review-graph` (`README.md` / official install guide), choose the right installation method for the user's Python 3.10+ / `uv` / `pipx` / `pip` environment, install `code-review-graph`, and verify `code-review-graph --version`.
   - **Workspace initialization (`init-crg.sh <target>`)**:
     1. Injects `.agents/rules/crg.md` (Graph-First retrieval, explicit `repo_root`, Zero Double-Read Policy, Hook-managed sync);
     2. Configures `.gitignore` (`.code-review-graph/`) + `.code-review-graph/.gitignore` (`*`);
     3. Installs atomic-locked Git `post-commit` hook (`.husky/post-commit` if `.husky/` exists, else `.git/hooks/post-commit`, preserving existing hook content) sharing `.code-review-graph/update.lock.d`;
     4. Supports optional `--with-local-hooks` to merge `crg-transaction-sync` into `<target>/.agents/hooks.json` for standalone repo usage;
     5. Runs initial `code-review-graph build --repo <target>` under atomic lock to populate `.code-review-graph/graph.db`.
3. **Hook-Driven Automatic Sync (`hooks.json` + `scripts/crg-hook.sh`)**:
   - `PostToolUse` (`mark-dirty`): Only triggers in CRG-initialized workspaces (`.code-review-graph/` or `.agents/rules/crg.md` exists) and ignores edits outside `workspacePaths[0]` (e.g. `<ArtifactDir>`) or inside `.git/` / `.code-review-graph/`; writes `.code-review-graph/.dirty` in ~1ms and outputs `{}`.
   - `Stop` (`sync-on-stop`): Checks `fullyIdle != false`, acquires POSIX atomic `mkdir .code-review-graph/update.lock.d` (with 10-min stale crash lock cleanup), detaches completely (`>/dev/null 2>&1 </dev/null &`) so AGY's stdout pipe never blocks, runs `build` if `graph.db` is missing or incremental update (including untracked/unstaged modified files alongside `git diff`), and outputs `{"decision":"allow"}`.
