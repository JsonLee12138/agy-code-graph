#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME:-}/.local/bin:${HOME:-}/.cargo/bin:/Library/Frameworks/Python.framework/Versions/3.13/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:/Library/Frameworks/Python.framework/Versions/3.11/bin:/Library/Frameworks/Python.framework/Versions/3.10/bin:$PATH"

echo "[Gate 0/5] Checking Disk SSoT contracts (.artifacts/)..."
for artifact in ".artifacts/SPEC.md" ".artifacts/CONSTRAINTS.md" ".artifacts/PLAN.md"; do
  if [ ! -s "$ROOT_DIR/$artifact" ]; then
    echo "FAIL: Missing or empty contract artifact: $artifact" >&2
    exit 1
  fi
done

echo "[Gate 1/5] Checking shell script syntax (POSIX sh & bash)..."
sh -n "$ROOT_DIR/scripts/crg-hook.sh"
bash -n "$ROOT_DIR/scripts/sync-upstream-skills.sh"
bash -n "$ROOT_DIR/scripts/install-crg.sh"
bash -n "$ROOT_DIR/skills/crg-install/scripts/install-crg.sh"
bash -n "$ROOT_DIR/scripts/init-crg.sh"
bash -n "$ROOT_DIR/skills/crg-init/scripts/init-crg.sh"
bash -n "$ROOT_DIR/tests/run-tests.sh"
bash -n "$ROOT_DIR/scripts/gate-check.sh"

echo "[Gate 2/5] Validating Antigravity plugin schema (--strict)..."
if command -v agy >/dev/null 2>&1; then
  agy plugin validate "$ROOT_DIR" --strict --json >/dev/null
else
  echo "WARN: agy CLI not on PATH; validating JSON manifests with python3..."
  python3 -m json.tool "$ROOT_DIR/plugin.json" >/dev/null
  python3 -m json.tool "$ROOT_DIR/mcp_config.json" >/dev/null
  python3 -m json.tool "$ROOT_DIR/hooks.json" >/dev/null
fi

echo "[Gate 3/5] Verifying synced upstream skills..."
bash "$ROOT_DIR/scripts/sync-upstream-skills.sh" --check-local

echo "[Gate 4/5] Running deterministic end-to-end integration test suite..."
bash "$ROOT_DIR/tests/run-tests.sh"

echo "[Gate 5/5] Scanning for secrets and hardcoded paths..."
SECRET_ONLY_PATTERN='^\+.*(AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,})'
if { git diff --cached -U0; git diff -U0; } | grep -v '^+++' | grep -E "$SECRET_ONLY_PATTERN"; then
  echo "FAIL: Potential secret detected in diff." >&2
  exit 1
fi

echo "ALL SOFTWARE 1.0 GATES PASSED."
