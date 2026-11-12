#!/usr/bin/env bash
set -euo pipefail

# Deterministic Software 1.0 integration test suite for agy-code-graph (v3)
# Verifies AC-1 through AC-6 in an isolated temporary directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME:-}/.local/bin:${HOME:-}/.cargo/bin:/Library/Frameworks/Python.framework/Versions/3.13/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:/Library/Frameworks/Python.framework/Versions/3.11/bin:/Library/Frameworks/Python.framework/Versions/3.10/bin:$PATH"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agy-code-graph-test.XXXXXX")"
cleanup() {
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

pass() {
  printf '  [PASS] %s\n' "$1"
}

fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  exit 1
}

echo "=== Test 1 (AC-1 & AC-6): Strict Plugin Manifest (9 Skills) & Single CI Workflow Contracts ==="
if command -v agy >/dev/null 2>&1; then
  VALIDATE_OUT="$(agy plugin validate "$REPO_ROOT" --strict --json)"
  python3 - "$VALIDATE_OUT" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("findings") == [], f"Expected 0 findings, got: {data.get('findings')}"
comp = data.get("components", {})
assert comp.get("skills") == 9, f"Expected 9 skills (7 upstream + crg-install + crg-init), got: {comp.get('skills')}"
assert comp.get("rules") == 1, f"Expected 1 rule, got: {comp.get('rules')}"
assert comp.get("hooks") == 1, f"Expected 1 hook file, got: {comp.get('hooks')}"
assert comp.get("mcpServers") == 1, f"Expected 1 mcpServer, got: {comp.get('mcpServers')}"
PY
  pass "agy plugin validate --strict --json returned 0 findings (skills: 9, rules: 1, hooks: 1, mcpServers: 1)"
else
  fail "agy CLI not found on PATH"
fi

SYNC_WF="$REPO_ROOT/.github/workflows/sync-upstream-skills.yml"
CI_WF="$REPO_ROOT/.github/workflows/ci.yml"
[ ! -f "$SYNC_WF" ] || fail "Deprecated $SYNC_WF should not exist"
[ -f "$CI_WF" ] || fail "Missing $CI_WF"
grep -q "contents: write" "$CI_WF" || fail "ci.yml missing contents: write permission"
grep -q "scripts/sync-upstream-skills.sh" "$CI_WF" || fail "ci.yml missing sync-upstream-skills.sh call"
grep -q "\[skip ci\]" "$CI_WF" || fail "ci.yml missing [skip ci] seamless auto-commit step"
pass "Single .github/workflows/ci.yml verified (seamless [skip ci] sync on main push, no separate cron workflow)"

echo "=== Test 2 (AC-2): Verbatim Upstream Skills & Full Unfiltered MCP Tool Surface ==="
bash "$REPO_ROOT/scripts/sync-upstream-skills.sh" --check-local >/dev/null
pass "All 7 upstream skills verified via sync-upstream-skills.sh --check-local"

python3 - "$REPO_ROOT/mcp_config.json" <<'PY'
import json, subprocess, sys

cfg_path = sys.argv[1]
cfg = json.load(open(cfg_path, encoding="utf-8"))
srv = cfg["mcpServers"]["agy-code-graph"]
cmd = [srv["command"]] + list(srv["args"])

proc = subprocess.Popen(
    cmd,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
try:
    init_req = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "agy-test", "version": "0.1.0"},
        },
    }
    notif = {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}
    list_req = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
    proc.stdin.write(json.dumps(init_req) + "\n")
    proc.stdin.flush()
    init_resp = proc.stdout.readline()
    assert init_resp, "No initialize response from MCP server"
    proc.stdin.write(json.dumps(notif) + "\n")
    proc.stdin.write(json.dumps(list_req) + "\n")
    proc.stdin.flush()
    list_resp = proc.stdout.readline()
    out = init_resp + "\n" + list_resp
finally:
    if proc.poll() is None:
        proc.kill()

tools = []
for line in out.splitlines():
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    if msg.get("id") == 2 and "result" in msg:
        tools = [t["name"] for t in msg["result"].get("tools", [])]

assert len(tools) >= 20, f"Expected >= 20 MCP tools, got {len(tools)}: {tools}"
required_tools = {
    "build_or_update_graph_tool",
    "get_minimal_context_tool",
    "semantic_search_nodes_tool",
    "query_graph_tool",
    "get_impact_radius_tool",
    "get_review_context_tool",
    "detect_changes_tool",
    "get_flow_tool",
    "refactor_tool",
}
missing = required_tools - set(tools)
assert not missing, f"Missing required upstream MCP tools: {missing}"
PY
pass "mcp_config.json exposes full upstream MCP toolset (>= 20 tools including build_or_update_graph_tool)"

echo "=== Test 3 (AC-3): Decoupled crg-install & crg-init Skills, Idempotent post-commit, Hooks Merge & Initial Build ==="
INSTALL_CHECK_JSON="$(bash "$REPO_ROOT/scripts/install-crg.sh" --check)"
python3 - "$INSTALL_CHECK_JSON" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["crgInstalled"] is True, f"Expected crgInstalled=True, got {d}"
assert d["crgBin"], f"Expected non-empty crgBin, got {d}"
assert d["upstreamRepoUrl"] == "https://github.com/tirth8205/code-review-graph"
PY
pass "install-crg.sh --check reported global code-review-graph CLI readiness"

TMP_REPO="$TMP_ROOT/sample-repo"
mkdir -p "$TMP_REPO"
git -C "$TMP_REPO" init -q
git -C "$TMP_REPO" config user.name "Test User"
git -C "$TMP_REPO" config user.email "test@example.com"

cat > "$TMP_REPO/app.py" <<'PY'
def calculate_total(items):
    return sum(items)

def checkout_order(items):
    return calculate_total(items)
PY

git -C "$TMP_REPO" add app.py
git -C "$TMP_REPO" commit -q -m "initial commit"

# Pre-seed an existing custom post-commit hook and an existing .agents/hooks.json entry
mkdir -p "$TMP_REPO/.git/hooks" "$TMP_REPO/.agents"
cat > "$TMP_REPO/.git/hooks/post-commit" <<'SH'
#!/usr/bin/env sh
echo "existing-user-post-commit-hook" >/dev/null
SH
chmod +x "$TMP_REPO/.git/hooks/post-commit"

cat > "$TMP_REPO/.agents/hooks.json" <<'JSON'
{
  "existing-custom-gate": {
    "PreToolUse": [
      {
        "matcher": "write_file",
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/custom-gate.sh"
          }
        ]
      }
    ]
  }
}
JSON

CHECK_JSON="$(bash "$REPO_ROOT/scripts/init-crg.sh" --check "$TMP_REPO")"
python3 - "$CHECK_JSON" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["crgInstalled"] is True, f"Expected crgInstalled=True, got {d}"
assert d["isGitRepo"] is True, f"Expected isGitRepo=True, got {d}"
assert d["ruleInstalled"] is False, f"Expected ruleInstalled=False before init, got {d}"
assert d["gitHookInstalled"] is False, f"Expected gitHookInstalled=False before init, got {d}"
assert d["graphDbExists"] is False, f"Expected graphDbExists=False before init, got {d}"
assert d["installSkill"] == "/agy-code-graph:crg-install"
PY
pass "init-crg.sh --check accurately reported pre-initialization state and /agy-code-graph:crg-install pointer"

INIT_JSON="$(bash "$REPO_ROOT/scripts/init-crg.sh" "$TMP_REPO" --with-local-hooks)"
python3 - "$INIT_JSON" "$TMP_REPO" <<'PY'
import json, pathlib, sqlite3, sys

d = json.loads(sys.argv[1])
repo = pathlib.Path(sys.argv[2])

assert d["ruleInstalled"] is True
assert d["gitHookInstalled"] is True
assert d["graphDbExists"] is True

rule_text = (repo / ".agents/rules/crg.md").read_text(encoding="utf-8")
assert "Zero Double-Read Policy" in rule_text
assert "repo_root" in rule_text

gitignore_text = (repo / ".gitignore").read_text(encoding="utf-8")
assert ".code-review-graph/" in gitignore_text
assert (repo / ".code-review-graph/.gitignore").read_text(encoding="utf-8").strip() == "*"

hook_text = (repo / ".git/hooks/post-commit").read_text(encoding="utf-8")
assert "existing-user-post-commit-hook" in hook_text, "Pre-existing post-commit hook was overwritten!"
assert hook_text.count("agy-code-graph post-commit") == 2  # start + end markers

hooks_cfg = json.loads((repo / ".agents/hooks.json").read_text(encoding="utf-8"))
assert "existing-custom-gate" in hooks_cfg, "Existing .agents/hooks.json group was clobbered!"
assert "crg-transaction-sync" in hooks_cfg, "crg-transaction-sync was not merged into .agents/hooks.json!"

db_path = repo / ".code-review-graph/graph.db"
assert db_path.is_file()
conn = sqlite3.connect(str(db_path))
rows = conn.execute("SELECT name FROM nodes WHERE name = 'calculate_total'").fetchall()
conn.close()
assert len(rows) >= 1, f"Expected calculate_total in graph.db nodes, got {rows}"
PY

# Run init-crg.sh a second time to verify post-commit idempotency
bash "$REPO_ROOT/scripts/init-crg.sh" "$TMP_REPO" --skip-build >/dev/null
MARKER_COUNT="$(grep -c ">>> agy-code-graph post-commit >>>" "$TMP_REPO/.git/hooks/post-commit")"
[ "$MARKER_COUNT" -eq 1 ] || fail "Expected post-commit marker count 1 after second init, got $MARKER_COUNT"
pass "init-crg.sh initialized rules, preserved existing post-commit & .agents/hooks.json, and built graph.db"

echo "=== Test 4 (AC-4): crg-hook.sh mark-dirty Workspace & Artifact Boundary Guards ==="
UNINIT_DIR="$TMP_ROOT/uninitialized-folder"
mkdir -p "$UNINIT_DIR"

OUT_UNINIT="$(printf '{"workspacePaths":["%s"],"toolCall":{"name":"write_file","args":{"Path":"%s/foo.py"}}}' "$UNINIT_DIR" "$UNINIT_DIR" | sh "$REPO_ROOT/scripts/crg-hook.sh" mark-dirty)"
[ "$OUT_UNINIT" = "{}" ] || fail "Expected {} from mark-dirty on uninitialized dir, got $OUT_UNINIT"
[ ! -d "$UNINIT_DIR/.code-review-graph" ] || fail "mark-dirty polluted uninitialized folder with .code-review-graph!"
pass "mark-dirty leaves uninitialized directories completely untouched"

rm -f "$TMP_REPO/.code-review-graph/.dirty"

OUT_ERR="$(printf '{"workspacePaths":["%s"],"error":"tool execution failed","toolCall":{"name":"edit_file","args":{"Path":"%s/app.py"}}}' "$TMP_REPO" "$TMP_REPO" | sh "$REPO_ROOT/scripts/crg-hook.sh" mark-dirty)"
[ "$OUT_ERR" = "{}" ] || fail "Expected {} on error payload"
[ ! -f "$TMP_REPO/.code-review-graph/.dirty" ] || fail "mark-dirty created .dirty despite tool error!"
pass "mark-dirty ignores failed tool calls (error != empty)"

OUT_ART="$(printf '{"workspacePaths":["%s"],"toolCall":{"name":"write_file","args":{"Path":"%s/outside-artifact.md"}}}' "$TMP_REPO" "$TMP_ROOT" | sh "$REPO_ROOT/scripts/crg-hook.sh" mark-dirty)"
[ "$OUT_ART" = "{}" ] || fail "Expected {} on external artifact edit"
[ ! -f "$TMP_REPO/.code-review-graph/.dirty" ] || fail "mark-dirty created .dirty for file outside workspacePaths[0]!"
pass "mark-dirty ignores <ArtifactDir> edits outside workspacePaths[0]"

OUT_VALID="$(printf '{"workspacePaths":["%s"],"toolCall":{"name":"edit_file","args":{"Path":"%s/app.py"}}}' "$TMP_REPO" "$TMP_REPO" | sh "$REPO_ROOT/scripts/crg-hook.sh" mark-dirty)"
[ "$OUT_VALID" = "{}" ] || fail "Expected {} on valid workspace edit"
[ -f "$TMP_REPO/.code-review-graph/.dirty" ] || fail "mark-dirty did not create .dirty for valid workspace file edit"
pass "mark-dirty creates .code-review-graph/.dirty on valid workspace file edit"

echo "=== Test 5 (AC-5): Pure-CLI sync-on-stop Non-Blocking Pipe EOF, fullyIdle Guard & Incremental Indexing ==="
if grep -q "from code_review_graph" "$REPO_ROOT/scripts/crg-hook.sh"; then
  fail "scripts/crg-hook.sh must use 100% pure CLI commands without inline code_review_graph Python imports"
fi
pass "Verified scripts/crg-hook.sh contains zero inline code_review_graph Python library imports"

OUT_NOT_IDLE="$(printf '{"workspacePaths":["%s"],"fullyIdle":false}' "$TMP_REPO" | sh "$REPO_ROOT/scripts/crg-hook.sh" sync-on-stop)"
[ "$OUT_NOT_IDLE" = '{"decision":"allow"}' ] || fail "Expected allow decision when fullyIdle=false, got $OUT_NOT_IDLE"
[ -f "$TMP_REPO/.code-review-graph/.dirty" ] || fail "sync-on-stop consumed .dirty even though fullyIdle was false!"
pass "sync-on-stop defers sync and preserves .dirty when fullyIdle: false"

# Modify tracked file app.py (uncommitted working-tree edit)
cat >> "$TMP_REPO/app.py" <<'PY'

def newly_edited_tracked_fn(x):
    return x + 99
PY

# Launch sync-on-stop with a 2-second background sleep delay and assert stdout pipe closes in < 1.0s
python3 - "$REPO_ROOT/scripts/crg-hook.sh" "$TMP_REPO" <<'PY'
import json, os, pathlib, subprocess, sys, time

hook_script = sys.argv[1]
repo = pathlib.Path(sys.argv[2])
env = os.environ.copy()
env["CRG_HOOK_TEST_DELAY_SEC"] = "2"

t0 = time.monotonic()
res = subprocess.run(
    ["sh", hook_script, "sync-on-stop"],
    input=json.dumps({"workspacePaths": [str(repo)], "fullyIdle": True}),
    capture_output=True,
    text=True,
    env=env,
    timeout=1.2,
)
elapsed = time.monotonic() - t0
assert res.returncode == 0, f"sync-on-stop exited with {res.returncode}: {res.stderr}"
assert res.stdout.strip() == '{"decision":"allow"}', f"Unexpected stdout: {res.stdout}"
assert elapsed < 1.0, f"sync-on-stop blocked stdout pipe for {elapsed:.2f}s (expected < 1.0s)!"
assert (repo / ".code-review-graph/update.lock.d").is_dir(), "Expected update.lock.d to be held by background worker"
PY
pass "sync-on-stop returned {\"decision\":\"allow\"} and closed stdout pipe in < 1.0s while background child slept"

# Verify atomic lock prevents duplicate concurrent sync while lock is held
: > "$TMP_REPO/.code-review-graph/.dirty"
OUT_LOCKED="$(printf '{"workspacePaths":["%s"],"fullyIdle":true}' "$TMP_REPO" | sh "$REPO_ROOT/scripts/crg-hook.sh" sync-on-stop)"
[ "$OUT_LOCKED" = '{"decision":"allow"}' ] || fail "Expected allow while locked"
[ -f "$TMP_REPO/.code-review-graph/.dirty" ] || fail ".dirty should remain untouched when update.lock.d is already held by another process"
rm -f "$TMP_REPO/.code-review-graph/.dirty"
pass "Atomic mkdir update.lock.d prevented concurrent duplicate sync and preserved .dirty"

# Wait for detached background sync-now worker to finish and release update.lock.d
WAIT_SEC=0
while [ -d "$TMP_REPO/.code-review-graph/update.lock.d" ]; do
  sleep 0.5
  WAIT_SEC=$((WAIT_SEC + 1))
  if [ "$WAIT_SEC" -ge 24 ]; then
    fail "Background sync-now worker did not release update.lock.d within 12 seconds"
  fi
done

python3 - "$TMP_REPO" <<'PY'
import pathlib, sqlite3, sys

repo = pathlib.Path(sys.argv[1])
db_path = repo / ".code-review-graph/graph.db"
conn = sqlite3.connect(str(db_path))
rows = conn.execute("SELECT name, file_path FROM nodes WHERE name = 'newly_edited_tracked_fn'").fetchall()
conn.close()
assert len(rows) >= 1, f"Expected modified symbol newly_edited_tracked_fn in graph.db via pure CLI update --base HEAD, got {rows}"
PY
pass "Detached pure-CLI Stop worker released update.lock.d and indexed uncommitted edit (newly_edited_tracked_fn) into graph.db"

echo "ALL 5 INTEGRATION TEST SUITES PASSED."
