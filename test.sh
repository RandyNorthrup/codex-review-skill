#!/usr/bin/env bash
# codex-review skill smoke test for macOS and Linux.
#
#   bash ./test.sh          quick CLI, version, login, and live probe
#   bash ./test.sh --full   planted-bug review plus read-only checks
set -u -o pipefail

# Match the installer in macOS non-interactive shells, where path_helper may
# not have added standard Homebrew or Node package locations.
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  export PATH
fi

MIN_VERSION="0.149.0"
MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
FULL=0

ok()   { printf '  ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

case "$#" in
  0) ;;
  1) [ "$1" = "--full" ] || fail "unknown argument: $1 (usage: bash ./test.sh [--full])"; FULL=1 ;;
  *) fail "too many arguments (usage: bash ./test.sh [--full])" ;;
esac

version_at_least() {
  local have="$1" minimum="$2" index have_part minimum_part
  local -a have_parts minimum_parts
  IFS=. read -r -a have_parts <<<"$have"
  IFS=. read -r -a minimum_parts <<<"$minimum"
  for index in 0 1 2; do
    have_part="${have_parts[$index]:-0}"
    minimum_part="${minimum_parts[$index]:-0}"
    ((10#$have_part > 10#$minimum_part)) && return 0
    ((10#$have_part < 10#$minimum_part)) && return 1
  done
  return 0
}

show_log_tail() {
  local path="$1"
  [ -f "$path" ] && tail -20 "$path" >&2
}

echo "== codex-review smoke test =="

# 1. CLI on PATH
command -v codex >/dev/null 2>&1 || fail "codex not on PATH. Run the installer: bash ./install.sh"
CODEX="$(command -v codex)"
ok "codex found at $CODEX"

# 2. Version
VER="$("$CODEX" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$VER" ] || fail "could not parse codex version"
version_at_least "$VER" "$MIN_VERSION" || \
  fail "codex $VER is older than $MIN_VERSION. Install the current Codex CLI."
ok "version $VER >= $MIN_VERSION"

# 3. Login
"$CODEX" login status >/dev/null 2>&1 || fail "codex is not logged in. Run: codex login"
ok "logged in"

# 4. Skill installed
SKILL="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/codex-review/SKILL.md"
[ -f "$SKILL" ] || fail "skill not found at $SKILL. Run bash ./install.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/SKILL.md" ] && ! cmp -s "$SCRIPT_DIR/SKILL.md" "$SKILL"; then
  fail "installed skill differs from repository SKILL.md. Rerun bash ./install.sh"
fi
ok "current skill installed at $SKILL"

WORK_DIR="$(mktemp -d)" || fail "could not create temporary directory"
TEST_SUCCEEDED=0
cleanup() {
  if [ "$TEST_SUCCEEDED" = 1 ]; then
    rm -rf -- "$WORK_DIR"
  else
    printf '  debug artifacts preserved at %s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# 5. Exact live probe using the enforced read-only sandbox
PROBE_RESULT="$WORK_DIR/probe-result.md"
PROBE_LOG="$WORK_DIR/probe.log"
if ! printf '%s\n' "Reply with exactly OK" | \
  "$CODEX" -s read-only -a never \
    --disable plugins --disable apps --disable hooks \
    -c 'mcp_servers={}' exec -m "$MODEL" \
    --skip-git-repo-check --ephemeral -o "$PROBE_RESULT" \
    >"$PROBE_LOG" 2>&1; then
  show_log_tail "$PROBE_LOG"
  fail "probe failed (authentication, model access, usage limit, or sandbox startup)"
fi
[ -f "$PROBE_RESULT" ] || { show_log_tail "$PROBE_LOG"; fail "probe produced no final-answer file"; }
PROBE_ANSWER="$(tr -d '\r\n' <"$PROBE_RESULT")"
[ "$PROBE_ANSWER" = "OK" ] || { show_log_tail "$PROBE_LOG"; fail "probe response was not exactly OK"; }
ok "probe returned exactly OK (model $MODEL, read-only sandbox)"

# 6. Full: planted-bug review must find both bugs and preserve target state
if [ "$FULL" = 1 ]; then
  echo "running full planted-bug review (xhigh; may take minutes)..."
  TARGET="$WORK_DIR/target"
  mkdir -p "$TARGET"
  cat >"$TARGET/sample.py" <<'EOF'
def average(items):
    total = 0
    for i in range(len(items) - 1):
        total += items[i]
    return total / len(items)
EOF

  BEFORE_HASH="$(cksum "$TARGET/sample.py")"
  BEFORE_TREE="$(find "$TARGET" -print | LC_ALL=C sort)"
  REVIEW_RESULT="$WORK_DIR/review-result.md"
  REVIEW_LOG="$WORK_DIR/review.log"
  PROMPT="Read-only review of sample.py as it stands; there is no diff. Read the actual local working tree. Goal: correct arithmetic mean. Report only: (1) bugs and correctness defects, (2) anything missing from the goal, and (3) quality issues. Cite file:line, rank by severity, and output only the final findings list. Do not modify, create, or delete files."

  if ! printf '%s\n' "$PROMPT" | \
    "$CODEX" -C "$TARGET" -s read-only -a never \
      --disable plugins --disable apps --disable hooks \
      -c 'mcp_servers={}' exec \
      -m "$MODEL" -c model_reasoning_effort=xhigh \
      --skip-git-repo-check --ephemeral -o "$REVIEW_RESULT" \
      >"$REVIEW_LOG" 2>&1; then
    show_log_tail "$REVIEW_LOG"
    fail "full review command failed"
  fi
  [ -f "$REVIEW_RESULT" ] || { show_log_tail "$REVIEW_LOG"; fail "full review produced no final-answer file"; }
  REVIEW="$(cat "$REVIEW_RESULT")"
  printf '%s' "$REVIEW" | grep -qiE 'off.by.one|skip(s|ped|ping)?|omit(s|ted|ting)?|exclud(e|es|ed|ing)?|(last|final) (item|element|value)' || \
    { printf '%s\n' "$REVIEW" >&2; fail "full review did not flag the planted off-by-one"; }
  printf '%s' "$REVIEW" | grep -qiE 'division by zero|zero|empty' || \
    { printf '%s\n' "$REVIEW" >&2; fail "full review did not flag empty-input division by zero"; }

  AFTER_HASH="$(cksum "$TARGET/sample.py")"
  AFTER_TREE="$(find "$TARGET" -print | LC_ALL=C sort)"
  [ "$BEFORE_HASH" = "$AFTER_HASH" ] || fail "review modified sample.py (read-only violated)"
  [ "$BEFORE_TREE" = "$AFTER_TREE" ] || fail "review changed target directory inventory (read-only violated)"
  ok "full review found planted bugs and preserved target hash and inventory"
fi

TEST_SUCCEEDED=1
echo ""
echo "PASS: codex-review environment is working"
