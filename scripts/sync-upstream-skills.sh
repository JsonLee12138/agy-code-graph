#!/usr/bin/env bash
set -euo pipefail

# Synchronizes the 7 official upstream skills from tirth8205/code-review-graph
# into skills/<skill>/SKILL.md without touching skills/crg-init/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-tirth8205/code-review-graph}"
UPSTREAM_REF="${UPSTREAM_REF:-staging}"

UPSTREAM_SKILLS=(
  "build-graph"
  "debug-issue"
  "explore-codebase"
  "refactor-safely"
  "review-changes"
  "review-delta"
  "review-pr"
)

MODE="sync"
if [ "${1:-}" = "--check-local" ]; then
  MODE="check-local"
elif [ "${1:-}" = "--from-local-package" ]; then
  MODE="local-package"
fi

validate_skill_file() {
  local file="$1"
  local skill_name="$2"
  if [ ! -s "$file" ]; then
    echo "ERROR: Missing or empty skill file: $file" >&2
    return 1
  fi
  if ! head -n 1 "$file" | grep -q '^---$'; then
    echo "ERROR: Missing YAML frontmatter opening delimiter in $file" >&2
    return 1
  fi
  if ! awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {exit 0} in_fm {print}' "$file" | grep -q '^name:[[:space:]]*'"$skill_name"'$'; then
    echo "ERROR: Frontmatter in $file does not declare name: $skill_name" >&2
    return 1
  fi
  if ! awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {exit 0} in_fm {print}' "$file" | grep -q '^description:'; then
    echo "ERROR: Frontmatter in $file does not declare description:" >&2
    return 1
  fi
  return 0
}

if [ "$MODE" = "check-local" ]; then
  for skill in "${UPSTREAM_SKILLS[@]}"; do
    target="$REPO_ROOT/skills/$skill/SKILL.md"
    validate_skill_file "$target" "$skill"
  done
  echo "OK: All ${#UPSTREAM_SKILLS[@]} upstream skills verified locally."
  exit 0
fi

fetch_from_github() {
  local skill="$1"
  local dest="$2"
  local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_REF}/skills/${skill}/SKILL.md"
  local tmp="${dest}.tmp"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --retry 2 --connect-timeout 10 "$url" -o "$tmp"; then
      if validate_skill_file "$tmp" "$skill"; then
        mv "$tmp" "$dest"
        return 0
      fi
    fi
  fi
  rm -f "$tmp"
  return 1
}

fetch_from_local_package() {
  local skill="$1"
  local dest="$2"
  local py_bin=""
  for candidate in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c "import code_review_graph" >/dev/null 2>&1; then
        py_bin="$candidate"
        break
      fi
    fi
  done
  if [ -z "$py_bin" ]; then
    return 1
  fi
  local pkg_skill
  pkg_skill="$("$py_bin" - "$skill" <<'PY'
import pathlib, sys
import code_review_graph
skill = sys.argv[1]
pkg_root = pathlib.Path(code_review_graph.__file__).resolve().parent
candidates = [
    pkg_root / "skills" / skill / "SKILL.md",
    pkg_root.parent / "skills" / skill / "SKILL.md",
]
for c in candidates:
    if c.is_file():
        print(c)
        break
PY
)"
  if [ -n "$pkg_skill" ] && [ -f "$pkg_skill" ]; then
    cp "$pkg_skill" "$dest"
    validate_skill_file "$dest" "$skill"
    return $?
  fi
  return 1
}

for skill in "${UPSTREAM_SKILLS[@]}"; do
  skill_dir="$REPO_ROOT/skills/$skill"
  mkdir -p "$skill_dir"
  dest="$skill_dir/SKILL.md"

  if [ "$MODE" = "local-package" ]; then
    if fetch_from_local_package "$skill" "$dest"; then
      echo "Synced $skill from local code_review_graph package."
      continue
    fi
  else
    if fetch_from_github "$skill" "$dest"; then
      echo "Synced $skill from https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_REF}/skills/${skill}/SKILL.md"
      continue
    elif fetch_from_local_package "$skill" "$dest"; then
      echo "Synced $skill from local code_review_graph package fallback."
      continue
    elif [ -f "$dest" ] && validate_skill_file "$dest" "$skill"; then
      echo "WARN: Network unreachable; keeping valid existing $dest"
      continue
    fi
  fi

  echo "ERROR: Failed to sync upstream skill: $skill" >&2
  exit 1
done

echo "Successfully synchronized ${#UPSTREAM_SKILLS[@]} upstream skills (ref: ${UPSTREAM_REF})."
