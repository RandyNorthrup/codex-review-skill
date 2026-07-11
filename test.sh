#!/usr/bin/env bash
# codex-review skill smoke test (macOS / Linux / Git Bash).
#
#   ./test.sh          quick: CLI present, version, login, probe
#   ./test.sh --full   also: real planted-bug review (slow, minutes) and a
#                      read-only check
set -u

MIN_VERSION="0.144.1"
MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
FULL=0
[ "${1:-}" = "--full" ] && FULL=1

ok()   { printf '  ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

echo "== codex-review smoke test =="

# 1. CLI on PATH
command -v codex >/dev/null 2>&1 || fail "codex not on PATH. Run the installer: ./install.sh"
CODEX="$(command -v codex)"
ok "codex found at $CODEX"

# 2. Version
VER="$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$VER" ] || fail "could not parse codex version"
[ "$(printf '%s\n%s\n' "$MIN_VERSION" "$VER" | sort -V | head -1)" = "$MIN_VERSION" ] || \
  fail "codex $VER is older than $MIN_VERSION. Run: npm install -g @openai/codex@latest"
ok "version $VER >= $MIN_VERSION"

# 3. Login
codex login status >/dev/null 2>&1 || fail "codex is not logged in. Run: codex login"
ok "logged in"

# 4. Skill installed
SKILL="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/codex-review/SKILL.md"
[ -f "$SKILL" ] && ok "skill installed at $SKILL" || echo "  warn: skill not found at $SKILL (run ./install.sh)"

# 5. Probe (auth + model + exec path)
OUT="$(echo "Reply with exactly OK" | codex exec -m "$MODEL" --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 2>&1)"
printf '%s' "$OUT" | grep -q "OK" || { printf '%s\n' "$OUT" | tail -15; fail "probe did not return OK (auth? model? usage limit?)"; }
ok "probe returned OK (model $MODEL)"

# 6. Full: planted-bug review must find the bugs and stay read-only
if [ "$FULL" = 1 ]; then
  echo "running full planted-bug review (xhigh - takes minutes)..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/sample.py" <<'EOF'
def average(items):
    total = 0
    for i in range(len(items) - 1):
        total += items[i]
    return total / len(items)
EOF
  REVIEW="$(echo "Read-only review of sample.py as it stands - there is no diff. Goal: correct arithmetic mean. Report ONLY bugs with file:line. Output ONLY the final findings list. Do NOT modify/create/delete any file; only read and report." | \
    codex -C "$TMP" exec -m "$MODEL" -c model_reasoning_effort=xhigh \
      --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 2>&1)"
  printf '%s' "$REVIEW" | grep -qiE 'off.by.one|last (item|element)|skips|len\(items\) - 1' || \
    { printf '%s\n' "$REVIEW" | tail -20; fail "full review did not flag the planted off-by-one"; }
  printf '%s' "$REVIEW" | grep -qiE 'zero|empty' || \
    { printf '%s\n' "$REVIEW" | tail -20; fail "full review did not flag division by zero on empty input"; }
  [ "$(ls "$TMP" | wc -l)" -eq 1 ] || fail "review created files in the scratch dir (read-only violated)"
  ok "full review found the planted bugs and stayed read-only"
fi

echo ""
echo "PASS: codex-review environment is working"
