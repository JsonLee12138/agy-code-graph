# Project Quality & Anti-Bloat Constraints (CONSTRAINTS)

> Enforced by `scripts/gate-check.sh`, `staff-gatekeeper`, and `risk-specialist`.

## 1. Hard Quality Bars (Software 1.0)
- Diff per vertical slice should stay focused (`<= 400` changed lines recommended per slice).
- Zero new linter/typecheck suppressions (`# noqa`, `# type: ignore`, `shellcheck disable`) without documented justification.
- Zero skipped or tautological mock-only tests; deleting core lock, EOF pipe-closure, or `init-crg.sh` merge logic must make `bash tests/run-tests.sh` fail.
- Zero hardcoded user home paths (e.g., `/Users/jsonlee`), credentials, tokens, or leftover `debugger;` statements.

## 2. Enforced Verification Matrix

| Dimension | Rule | Checked by | Runs at |
|-----------|------|------------|---------|
| AGY Plugin Strict Schema | `0` errors, `0` warnings, `0` notes; `skills: 9, rules: 1, hooks: 1, mcpServers: 1` | `agy plugin validate . --strict --json` | `gate-check.sh` |
| Shell Syntax | Clean POSIX `sh -n` / `bash -n` across all scripts | `sh -n scripts/crg-hook.sh && bash -n skills/crg-init/scripts/init-crg.sh scripts/init-crg.sh scripts/sync-upstream-skills.sh tests/run-tests.sh` | `gate-check.sh` |
| Full MCP Surface | `mcp_config.json` spawns `code-review-graph serve` returning full upstream toolset (`>= 20` tools) | `bash tests/run-tests.sh` | `gate-check.sh` |
| Hook Pipe & Lock Safety | `Stop` hook exits `< 1s` without hanging stdout pipe; `mkdir update.lock.d` prevents concurrent updates | `bash tests/run-tests.sh` | `gate-check.sh` |
| Init & Git Hook Idempotency | `init-crg.sh` preserves existing `post-commit` & `.agents/hooks.json` entries and builds `graph.db` | `bash tests/run-tests.sh` | `gate-check.sh` |

## 3. Anti-Overengineering Contract (Software 2.0 Guardrail)
- Do **not** add custom MCP proxy servers or custom daemon processes — `mcp_config.json` `exec`s `code-review-graph serve` directly, and `hooks.json` invokes POSIX `sh` lifecycle scripts.
- Keep the 7 upstream `skills/*/SKILL.md` files untouched from `tirth8205/code-review-graph@staging`.
- Reviewers (`staff-gatekeeper`, `risk-specialist`) MUST NOT demand extra middleware, distributed locks, or speculative abstractions beyond `.artifacts/SPEC.md` unless proving a deterministic crash, hang, security exploit, or data-loss path.
