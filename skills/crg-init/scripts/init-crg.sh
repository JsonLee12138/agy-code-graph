#!/usr/bin/env bash
set -euo pipefail

# Deterministic workspace bootstrapper for agy-code-graph (/agy-code-graph:crg-init)
# Usage:
#   init-crg.sh --check [target-dir]
#   init-crg.sh [target-dir] [--with-local-hooks] [--skip-build] [--force]

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME:-}/.local/bin:${HOME:-}/.cargo/bin:/Library/Frameworks/Python.framework/Versions/3.13/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:/Library/Frameworks/Python.framework/Versions/3.11/bin:/Library/Frameworks/Python.framework/Versions/3.10/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"

RULE_TEMPLATE="$SKILL_DIR/references/crg-rule-template.md"
HOOKS_TEMPLATE="$SKILL_DIR/references/hooks-template.json"
HOOK_SCRIPT_SRC="$PLUGIN_ROOT/scripts/crg-hook.sh"

CHECK_ONLY=0
WITH_LOCAL_HOOKS=0
SKIP_BUILD=0
FORCE=0
TARGET_DIR=""

for arg in "$@"; do
  case "$arg" in
    --check)
      CHECK_ONLY=1
      ;;
    --with-local-hooks)
      WITH_LOCAL_HOOKS=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: init-crg.sh [target-dir] [--check] [--with-local-hooks] [--skip-build] [--force]
EOF
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$arg"
      fi
      ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  TARGET_DIR="."
fi
mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

CRG_BIN=""
if command -v code-review-graph >/dev/null 2>&1; then
  CRG_BIN="$(command -v code-review-graph)"
fi

UVX_BIN=""
if command -v uvx >/dev/null 2>&1; then
  UVX_BIN="$(command -v uvx)"
fi

CRG_INSTALLED="false"
if [ -n "$CRG_BIN" ]; then
  CRG_INSTALLED="true"
fi

UVX_AVAILABLE="false"
if [ -n "$UVX_BIN" ]; then
  UVX_AVAILABLE="true"
fi

PYTHON_VERSION="$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || echo "")"

IS_GIT_REPO="false"
if [ -d "$TARGET_DIR/.git" ] || git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  IS_GIT_REPO="true"
fi

RULE_FILE="$TARGET_DIR/.agents/rules/crg.md"
RULE_INSTALLED="false"
if [ -s "$RULE_FILE" ]; then
  RULE_INSTALLED="true"
fi

 detect_git_hook_path() {
  if [ -d "$TARGET_DIR/.husky" ]; then
    printf '%s\n' "$TARGET_DIR/.husky/post-commit"
    return 0
  fi
  if [ -d "$TARGET_DIR/.git" ]; then
    printf '%s\n' "$TARGET_DIR/.git/hooks/post-commit"
    return 0
  fi
  local git_dir
  git_dir="$(git -C "$TARGET_DIR" rev-parse --git-dir 2>/dev/null || true)"
  if [ -n "$git_dir" ]; then
    case "$git_dir" in
      /*) printf '%s\n' "$git_dir/hooks/post-commit" ;;
      *) printf '%s\n' "$TARGET_DIR/$git_dir/hooks/post-commit" ;;
    esac
    return 0
  fi
  printf '%s\n' ""
}

HOOK_PATH="$(detect_git_hook_path)"
GIT_HOOK_INSTALLED="false"
if [ -n "$HOOK_PATH" ] && [ -f "$HOOK_PATH" ] && grep -q "agy-code-graph post-commit" "$HOOK_PATH" 2>/dev/null; then
  GIT_HOOK_INSTALLED="true"
fi

GRAPH_DB="$TARGET_DIR/.code-review-graph/graph.db"
GRAPH_DB_EXISTS="false"
if [ -f "$GRAPH_DB" ]; then
  GRAPH_DB_EXISTS="true"
fi

emit_status_json() {
  python3 - "$TARGET_DIR" "$CRG_INSTALLED" "$CRG_BIN" "$UVX_AVAILABLE" "$PYTHON_VERSION" "$IS_GIT_REPO" "$RULE_INSTALLED" "$GIT_HOOK_INSTALLED" "$GRAPH_DB_EXISTS" <<'PY'
import json, sys
ws, crg_inst, crg_bin, uvx_avail, py_ver, is_git, rule_inst, hook_inst, db_exists = sys.argv[1:10]
print(json.dumps({
    "workspace": ws,
    "crgInstalled": crg_inst == "true",
    "crgBin": crg_bin,
    "uvxAvailable": uvx_avail == "true",
    "pythonVersion": py_ver,
    "isGitRepo": is_git == "true",
    "ruleInstalled": rule_inst == "true",
    "gitHookInstalled": hook_inst == "true",
    "graphDbExists": db_exists == "true",
    "installSkill": "/agy-code-graph:crg-install",
}, indent=2))
PY
}

if [ "$CHECK_ONLY" -eq 1 ]; then
  emit_status_json
  exit 0
fi

# 1. Verify code-review-graph availability when building
if [ "$SKIP_BUILD" -eq 0 ] && [ "$CRG_INSTALLED" != "true" ] && [ "$UVX_AVAILABLE" != "true" ]; then
  echo "code-review-graph is not installed. Please run /agy-code-graph:crg-install first." >&2
  emit_status_json
  exit 2
fi

# 2. Inject workspace rule .agents/rules/crg.md
mkdir -p "$TARGET_DIR/.agents/rules"
if [ ! -s "$RULE_FILE" ] || [ "$FORCE" -eq 1 ]; then
  cp "$RULE_TEMPLATE" "$RULE_FILE"
fi
RULE_INSTALLED="true"

# 3. Ensure .gitignore ignores .code-review-graph/ and inner .gitignore has *
GITIGNORE_FILE="$TARGET_DIR/.gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
  if ! grep -Eq '(^|/)\.code-review-graph/?$' "$GITIGNORE_FILE"; then
    printf '\n# code-review-graph AST database\n.code-review-graph/\n' >> "$GITIGNORE_FILE"
  fi
else
  printf '# code-review-graph AST database\n.code-review-graph/\n' > "$GITIGNORE_FILE"
fi

mkdir -p "$TARGET_DIR/.code-review-graph"
if [ ! -f "$TARGET_DIR/.code-review-graph/.gitignore" ]; then
  printf '*\n' > "$TARGET_DIR/.code-review-graph/.gitignore"
fi

# 4. Install idempotent atomic-locked Git post-commit hook
if [ "$IS_GIT_REPO" = "true" ] && [ -n "$HOOK_PATH" ]; then
  mkdir -p "$(dirname "$HOOK_PATH")"
  if [ ! -f "$HOOK_PATH" ]; then
    printf '#!/usr/bin/env sh\n' > "$HOOK_PATH"
  fi
  if ! grep -q "agy-code-graph post-commit" "$HOOK_PATH" 2>/dev/null; then
    cat >> "$HOOK_PATH" <<'EOF'

# >>> agy-code-graph post-commit >>>
(
  export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME:-}/.local/bin:${HOME:-}/.cargo/bin:/Library/Frameworks/Python.framework/Versions/3.13/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:/Library/Frameworks/Python.framework/Versions/3.11/bin:/Library/Frameworks/Python.framework/Versions/3.10/bin:$PATH"
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  CRG_DIR="$REPO_ROOT/.code-review-graph"
  LOCK_DIR="$CRG_DIR/update.lock.d"
  if [ -d "$CRG_DIR" ]; then
    if [ -d "$LOCK_DIR" ]; then
      STALE="$(find "$CRG_DIR" -maxdepth 1 -name "update.lock.d" -mmin +10 2>/dev/null || true)"
      [ -n "$STALE" ] && rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
      rm -f "$CRG_DIR/.dirty" 2>/dev/null || true
      if command -v code-review-graph >/dev/null 2>&1; then
        code-review-graph update --repo "$REPO_ROOT" >/dev/null 2>&1 || true
      elif command -v uvx >/dev/null 2>&1; then
        uvx code-review-graph update --repo "$REPO_ROOT" >/dev/null 2>&1 || true
      fi
    fi
  fi
) >/dev/null 2>&1 </dev/null &
# <<< agy-code-graph post-commit <<<
EOF
  fi
  chmod +x "$HOOK_PATH"
  GIT_HOOK_INSTALLED="true"
fi

# 5. Optional --with-local-hooks: copy crg-hook.sh and non-destructively merge .agents/hooks.json
if [ "$WITH_LOCAL_HOOKS" -eq 1 ]; then
  mkdir -p "$TARGET_DIR/scripts" "$TARGET_DIR/.agents/scripts"
  if [ "$HOOK_SCRIPT_SRC" != "$TARGET_DIR/scripts/crg-hook.sh" ]; then
    cp "$HOOK_SCRIPT_SRC" "$TARGET_DIR/scripts/crg-hook.sh"
  fi
  chmod +x "$TARGET_DIR/scripts/crg-hook.sh"
  cp "$HOOK_SCRIPT_SRC" "$TARGET_DIR/.agents/scripts/crg-hook.sh"
  chmod +x "$TARGET_DIR/.agents/scripts/crg-hook.sh"

  TARGET_HOOKS_JSON="$TARGET_DIR/.agents/hooks.json"
  python3 - "$TARGET_HOOKS_JSON" "$HOOKS_TEMPLATE" <<'PY'
import json, pathlib, sys

target_path = pathlib.Path(sys.argv[1])
template_path = pathlib.Path(sys.argv[2])

template_data = json.loads(template_path.read_text(encoding="utf-8"))
existing_data = {}
if target_path.is_file():
    try:
        loaded = json.loads(target_path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            existing_data = loaded
    except Exception:
        existing_data = {}

for key, val in template_data.items():
    existing_data[key] = val

target_path.parent.mkdir(parents=True, exist_ok=True)
target_path.write_text(json.dumps(existing_data, indent=2) + "\n", encoding="utf-8")
PY
fi

# 6. Initial code-review-graph build under atomic lock
if [ "$SKIP_BUILD" -eq 0 ]; then
  LOCK_DIR="$TARGET_DIR/.code-review-graph/update.lock.d"
  if [ -d "$LOCK_DIR" ]; then
    STALE="$(find "$TARGET_DIR/.code-review-graph" -maxdepth 1 -name "update.lock.d" -mmin +10 2>/dev/null || true)"
    [ -n "$STALE" ] && rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  LOCK_ACQUIRED="false"
  WAIT_TRIES=0
  while :; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      LOCK_ACQUIRED="true"
      break
    fi
    WAIT_TRIES=$((WAIT_TRIES + 1))
    if [ "$WAIT_TRIES" -ge 20 ]; then
      break
    fi
    sleep 0.2
  done
  rm -f "$TARGET_DIR/.code-review-graph/.dirty" 2>/dev/null || true
  if [ -n "$CRG_BIN" ]; then
    "$CRG_BIN" build --repo "$TARGET_DIR" >/dev/null
  elif [ -n "$UVX_BIN" ]; then
    "$UVX_BIN" code-review-graph build --repo "$TARGET_DIR" >/dev/null
  fi
  if [ "$LOCK_ACQUIRED" = "true" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
fi

if [ -f "$GRAPH_DB" ]; then
  GRAPH_DB_EXISTS="true"
fi

emit_status_json
