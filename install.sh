#!/usr/bin/env bash
# codex-review installer for macOS and Linux.
#
# Checks or installs Node.js/npm and Codex CLI, verifies Codex login, installs
# the Claude Code skill, and runs an exact live probe in the read-only sandbox.
set -u -o pipefail

# macOS GUI shells normally add these through path_helper; non-interactive SSH
# sessions may not. Include both Apple Silicon Homebrew and Intel/pkg paths.
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  export PATH
fi

REPO="RandyNorthrup/codex-review-skill"
RAW="https://raw.githubusercontent.com/$REPO/main"
MIN_VERSION="0.149.0"
MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
SKILL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/codex-review"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

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

codex_version() {
  "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

show_log_tail() {
  local path="$1"
  [ -f "$path" ] && tail -20 "$path" >&2
}

say "== codex-review skill installer =="

# --- 1. Node / npm -----------------------------------------------------------
if ! command -v npm >/dev/null 2>&1; then
  say "npm not found - trying to install Node.js..."
  if command -v brew >/dev/null 2>&1; then
    brew install node
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y nodejs npm
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y nodejs npm
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm nodejs npm
  fi
  command -v npm >/dev/null 2>&1 || \
    fail "could not install Node.js automatically. Install it from https://nodejs.org, open a new terminal, and rerun this installer."
fi
ok "npm $(npm --version)"

# --- 2. Codex CLI ------------------------------------------------------------
NEED_CODEX=0
CODEX=""
if command -v codex >/dev/null 2>&1; then
  CODEX="$(command -v codex)"
  VERSION="$(codex_version "$CODEX")"
  if [ -z "$VERSION" ]; then
    NEED_CODEX=1
  elif ! version_at_least "$VERSION" "$MIN_VERSION"; then
    say "codex $VERSION is older than $MIN_VERSION - updating..."
    NEED_CODEX=1
  fi
else
  say "codex not found - installing..."
  NEED_CODEX=1
fi

if [ "$NEED_CODEX" = 1 ]; then
  npm install -g @openai/codex@latest || fail "npm install -g @openai/codex@latest failed"
  hash -r 2>/dev/null || true
  command -v codex >/dev/null 2>&1 || \
    fail "codex is still not on PATH after installation. Open a new terminal and rerun this installer."
  CODEX="$(command -v codex)"
fi

VERSION="$(codex_version "$CODEX")"
[ -n "$VERSION" ] || fail "could not parse Codex CLI version from $CODEX"
version_at_least "$VERSION" "$MIN_VERSION" || \
  fail "codex on PATH is $VERSION (< $MIN_VERSION) at $CODEX. Remove or reorder stale installations, then rerun."
ok "codex $VERSION at $CODEX"

# --- 3. Codex login ----------------------------------------------------------
if "$CODEX" login status >/dev/null 2>&1; then
  ok "codex is logged in"
else
  if [ -e /dev/tty ]; then
    say "codex is not logged in - launching 'codex login' in your browser..."
    "$CODEX" login </dev/tty || \
      fail "codex login failed. Run 'codex login' manually, then rerun this installer."
    ok "codex login complete"
  else
    fail "codex is not logged in. Run 'codex login' once, then rerun this installer."
  fi
fi

WORK_DIR="$(mktemp -d)" || fail "could not create temporary directory"
cleanup() { rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# --- 4. Install the skill ----------------------------------------------------
mkdir -p "$SKILL_DIR" || fail "could not create $SKILL_DIR"
SOURCE_DIR=""
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
  CANDIDATE_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  [ -f "$CANDIDATE_DIR/SKILL.md" ] && SOURCE_DIR="$CANDIDATE_DIR"
fi

TEMP_SKILL="$WORK_DIR/SKILL.md"
if [ -n "$SOURCE_DIR" ]; then
  cp "$SOURCE_DIR/SKILL.md" "$TEMP_SKILL" || fail "could not read local SKILL.md"
else
  command -v curl >/dev/null 2>&1 || fail "curl is required to download SKILL.md"
  curl -fsSL "$RAW/SKILL.md" -o "$TEMP_SKILL" || fail "could not download SKILL.md from $RAW"
fi

if [ -f "$SKILL_DIR/SKILL.md" ] && ! cmp -s "$TEMP_SKILL" "$SKILL_DIR/SKILL.md"; then
  cp "$SKILL_DIR/SKILL.md" "$SKILL_DIR/SKILL.md.bak" || fail "could not back up existing SKILL.md"
  say "  note: existing SKILL.md differed; backed up to SKILL.md.bak"
fi
mv "$TEMP_SKILL" "$SKILL_DIR/SKILL.md" || fail "could not install SKILL.md"
ok "skill installed at $SKILL_DIR/SKILL.md"

# --- 5. Exact live probe -----------------------------------------------------
say "running a quick end-to-end probe..."
PROBE_RESULT="$WORK_DIR/probe-result.md"
PROBE_LOG="$WORK_DIR/probe.log"
if ! printf '%s\n' "Reply with exactly OK" | \
  "$CODEX" -s read-only -a never \
    --disable plugins --disable apps --disable hooks \
    -c 'mcp_servers={}' exec -m "$MODEL" \
    --skip-git-repo-check --ephemeral -o "$PROBE_RESULT" \
    >"$PROBE_LOG" 2>&1; then
  show_log_tail "$PROBE_LOG"
  fail "probe failed (authentication, model access, usage limit, or sandbox startup). The skill was installed."
fi
[ -f "$PROBE_RESULT" ] || { show_log_tail "$PROBE_LOG"; fail "probe produced no final-answer file"; }
PROBE_ANSWER="$(tr -d '\r\n' <"$PROBE_RESULT")"
[ "$PROBE_ANSWER" = "OK" ] || { show_log_tail "$PROBE_LOG"; fail "probe response was not exactly OK"; }
ok "probe returned exactly OK (model $MODEL, read-only sandbox)"

say ""
say "PASS: codex-review is installed. In Claude Code, invoke /codex-review or ask for a Codex review."
