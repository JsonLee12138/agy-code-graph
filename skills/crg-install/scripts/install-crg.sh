#!/usr/bin/env bash
set -euo pipefail

# Global CLI installer & environment checker for code-review-graph (/agy-code-graph:crg-install)
# Usage:
#   install-crg.sh --check
#   install-crg.sh [--upgrade]

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME:-}/.local/bin:${HOME:-}/.cargo/bin:/Library/Frameworks/Python.framework/Versions/3.13/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:/Library/Frameworks/Python.framework/Versions/3.11/bin:/Library/Frameworks/Python.framework/Versions/3.10/bin:$PATH"

CHECK_ONLY=0
UPGRADE=0

for arg in "$@"; do
  case "$arg" in
    --check)
      CHECK_ONLY=1
      ;;
    --upgrade|-U)
      UPGRADE=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: install-crg.sh [--check] [--upgrade]
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

find_python310_plus() {
  for cand in \
    /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    python3; do
    if command -v "$cand" >/dev/null 2>&1; then
      if "$cand" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
        command -v "$cand"
        return 0
      fi
    fi
  done
  return 1
}

refresh_state() {
  CRG_BIN=""
  CRG_VERSION=""
  CRG_INSTALLED="false"
  if command -v code-review-graph >/dev/null 2>&1; then
    CRG_BIN="$(command -v code-review-graph)"
    CRG_VERSION="$("$CRG_BIN" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
    CRG_INSTALLED="true"
  fi

  UV_AVAILABLE="false"
  if command -v uv >/dev/null 2>&1; then
    UV_AVAILABLE="true"
  fi

  PIPX_AVAILABLE="false"
  if command -v pipx >/dev/null 2>&1; then
    PIPX_AVAILABLE="true"
  fi

  PY_BIN=""
  PYTHON3_AVAILABLE="false"
  PYTHON_VERSION=""
  if PY_BIN="$(find_python310_plus 2>/dev/null)"; then
    PYTHON3_AVAILABLE="true"
    PYTHON_VERSION="$("$PY_BIN" -c 'import platform; print(platform.python_version())' 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION="$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || true)"
  fi
}

emit_json() {
  local method="${1:-none}"
  python3 - "$CRG_INSTALLED" "$CRG_BIN" "$CRG_VERSION" "$UV_AVAILABLE" "$PIPX_AVAILABLE" "$PYTHON3_AVAILABLE" "$PYTHON_VERSION" "$method" <<'PY'
import json, sys
crg_inst, crg_bin, crg_ver, uv_avail, pipx_avail, py_avail, py_ver, method = sys.argv[1:9]
print(json.dumps({
    "crgInstalled": crg_inst == "true",
    "crgBin": crg_bin,
    "crgVersion": crg_ver,
    "uvAvailable": uv_avail == "true",
    "pipxAvailable": pipx_avail == "true",
    "python3Available": py_avail == "true",
    "pythonVersion": py_ver,
    "installMethod": method,
    "upstreamRepoUrl": "https://github.com/tirth8205/code-review-graph",
}, indent=2))
PY
}

refresh_state

if [ "$CHECK_ONLY" -eq 1 ]; then
  emit_json "check"
  exit 0
fi

if [ "$CRG_INSTALLED" = "true" ] && [ "$UPGRADE" -eq 0 ]; then
  emit_json "already-installed"
  exit 0
fi

INSTALL_METHOD=""
if [ "$UV_AVAILABLE" = "true" ]; then
  if [ "$UPGRADE" -eq 1 ]; then
    uv tool install --upgrade code-review-graph >/dev/null 2>&1 || uv tool install code-review-graph >/dev/null 2>&1
  else
    uv tool install code-review-graph >/dev/null 2>&1
  fi
  INSTALL_METHOD="uv"
elif [ "$PIPX_AVAILABLE" = "true" ]; then
  if [ "$UPGRADE" -eq 1 ]; then
    pipx upgrade code-review-graph >/dev/null 2>&1 || pipx install code-review-graph >/dev/null 2>&1
  else
    pipx install code-review-graph >/dev/null 2>&1
  fi
  INSTALL_METHOD="pipx"
elif [ "$PYTHON3_AVAILABLE" = "true" ] && [ -n "$PY_BIN" ]; then
  if [ "$UPGRADE" -eq 1 ]; then
    "$PY_BIN" -m pip install --user --upgrade code-review-graph >/dev/null 2>&1 || "$PY_BIN" -m pip install --upgrade code-review-graph >/dev/null 2>&1
  else
    "$PY_BIN" -m pip install --user code-review-graph >/dev/null 2>&1 || "$PY_BIN" -m pip install code-review-graph >/dev/null 2>&1
  fi
  INSTALL_METHOD="pip"
else
  echo "ERROR: Neither uv, pipx, nor Python 3.10+ is available to install code-review-graph." >&2
  echo "See https://github.com/tirth8205/code-review-graph for prerequisites." >&2
  emit_json "failed"
  exit 1
fi

refresh_state
if [ "$CRG_INSTALLED" != "true" ]; then
  echo "ERROR: Installation completed via $INSTALL_METHOD, but code-review-graph binary was not found on PATH." >&2
  emit_json "$INSTALL_METHOD"
  exit 1
fi

emit_json "$INSTALL_METHOD"
