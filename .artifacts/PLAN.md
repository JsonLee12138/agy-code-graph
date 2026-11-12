# Implementation Plan & Vertical Slices (PLAN v3)

> Ordered vertical slices executed by `slice-builder`. Every slice ends with `bash scripts/gate-check.sh` passing.

## Slice 1: Decouple `/agy-code-graph:crg-install` & `/agy-code-graph:crg-init`, Pure-CLI Hook & Single `ci.yml` Seamless Sync
- **Owned files / subtree:** `plugin.json`, `rules/AGENTS.md`, `skills/crg-install/SKILL.md`, `skills/crg-install/scripts/install-crg.sh`, `scripts/install-crg.sh`, `skills/crg-init/SKILL.md`, `skills/crg-init/scripts/init-crg.sh`, `scripts/crg-hook.sh`, `.github/workflows/ci.yml` (and remove `.github/workflows/sync-upstream-skills.yml`), `tests/run-tests.sh`, `scripts/gate-check.sh`, `README.md`
- **Dependencies:** None
- **Acceptance criteria:** Refs AC-1, AC-2, AC-3, AC-4, AC-5, AC-6 —
  1. Add `skills/crg-install/SKILL.md` + `skills/crg-install/scripts/install-crg.sh` + `scripts/install-crg.sh` wrapper solely for global `code-review-graph` CLI detection and installation (reading `https://github.com/tirth8205/code-review-graph`, no daemon).
  2. Simplify `skills/crg-init/SKILL.md` + `skills/crg-init/scripts/init-crg.sh` to focus solely on workspace initialization (prompting `/agy-code-graph:crg-install` if CLI is missing).
  3. Refactor `scripts/crg-hook.sh` `sync-now` to use 100% pure CLI (`code-review-graph update --base HEAD --repo "$WORKSPACE_ROOT"`, `code-review-graph update --repo "$WORKSPACE_ROOT"`, `code-review-graph build --repo "$WORKSPACE_ROOT"`) with zero inline Python `code_review_graph` library calls.
  4. Remove `.github/workflows/sync-upstream-skills.yml` and update `.github/workflows/ci.yml` to pull upstream skills on `push` to `main` and seamlessly commit & push `chore(skills): sync upstream skills [skip ci]` directly to `main`.
  5. Update `plugin.json`, `rules/AGENTS.md`, `README.md`, `tests/run-tests.sh` (verifying `skills: 9`, pure-CLI `crg-hook.sh`, `crg-install` + `crg-init` decoupling, and single `ci.yml`), and `scripts/gate-check.sh`.
- **Verification:** `agy plugin validate . --strict --json && bash scripts/gate-check.sh`
- **Status:** `[x] Completed`
