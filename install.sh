#!/usr/bin/env bash
# codex-review skill installer (macOS / Linux / Git Bash).
#
# Checks every prerequisite and installs what is missing:
#   1. Node.js / npm  (via brew / apt / dnf / pacman / winget if absent)
#   2. Codex CLI >= 0.144.1  (npm install -g @openai/codex@latest)
#   3. Codex login  (launches `codex login` if needed)
#   4. The skill itself -> ~/.claude/skills/codex-review/SKILL.md
#   5. A quick end-to-end probe
#
# Safe to re-run; re-running updates everything to latest.
set -u

REPO="RandyNorthrup/codex-review-skill"
RAW="https://raw.githubusercontent.com/$REPO/main"
MIN_VERSION="0.144.1"
MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
SKILL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/codex-review"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

say "== codex-review skill installer =="

# --- 1. Node / npm -----------------------------------------------------------
if ! command -v npm >/dev/null 2>&1; then
  say "npm not found - trying to install Node.js..."
  if command -v brew >/dev/null 2>&1; then brew install node
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y nodejs npm
  elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y nodejs npm
  elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm nodejs npm
  elif command -v winget >/dev/null 2>&1; then winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
  fi
  command -v npm >/dev/null 2>&1 || fail "could not install Node.js automatically. Install it from https://nodejs.org, open a NEW terminal, and re-run this installer."
fi
ok "npm $(npm --version)"

# --- 2. Codex CLI (>= $MIN_VERSION) ------------------------------------------
codex_version() { codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }

need_codex=0
if ! command -v codex >/dev/null 2>&1; then
  say "codex not found - installing..."
  need_codex=1
else
  VER="$(codex_version)"
  if [ -z "$VER" ]; then
    need_codex=1
  elif [ "$(printf '%s\n%s\n' "$MIN_VERSION" "$VER" | sort -V | head -1)" != "$MIN_VERSION" ]; then
    say "codex $VER is older than $MIN_VERSION - updating..."
    need_codex=1
  fi
fi
if [ "$need_codex" = 1 ]; then
  npm install -g @openai/codex@latest || fail "npm install -g @openai/codex@latest failed"
  hash -r 2>/dev/null || true
  command -v codex >/dev/null 2>&1 || fail "codex still not on PATH after install - open a NEW terminal and re-run this installer."
fi
ok "codex $(codex_version) at $(command -v codex)"

# --- 3. Codex login ----------------------------------------------------------
if codex login status >/dev/null 2>&1; then
  ok "codex is logged in"
else
  if [ -e /dev/tty ]; then
    say "codex is not logged in - launching 'codex login' (finishes in your browser)..."
    codex login </dev/tty || fail "codex login failed - run 'codex login' manually, then re-run this installer."
    ok "codex login complete"
  else
    fail "codex is not logged in. Run 'codex login' once, then re-run this installer."
  fi
fi

# --- 4. Install the skill ----------------------------------------------------
mkdir -p "$SKILL_DIR"
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/SKILL.md" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

TMP_MD="$(mktemp)"
if [ -n "$SRC_DIR" ]; then
  cp "$SRC_DIR/SKILL.md" "$TMP_MD"           # running from a clone
else
  curl -fsSL "$RAW/SKILL.md" -o "$TMP_MD" || fail "could not download SKILL.md from $RAW"
fi
if [ -f "$SKILL_DIR/SKILL.md" ] && ! cmp -s "$TMP_MD" "$SKILL_DIR/SKILL.md"; then
  cp "$SKILL_DIR/SKILL.md" "$SKILL_DIR/SKILL.md.bak"
  say "  note: existing SKILL.md differed (self-repairs?) - backed up to SKILL.md.bak"
fi
mv "$TMP_MD" "$SKILL_DIR/SKILL.md"
ok "skill installed at $SKILL_DIR/SKILL.md"

# --- 5. Probe ----------------------------------------------------------------
say "running a quick end-to-end probe (~30s)..."
OUT="$(echo "Reply with exactly OK" | codex exec -m "$MODEL" --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 2>&1)"
if printf '%s' "$OUT" | grep -q "OK"; then
  ok "probe returned OK (model $MODEL)"
else
  printf '%s\n' "$OUT" | tail -15
  fail "probe failed (usage limit? model access?). The skill IS installed; see the Self-repair section in SKILL.md."
fi

say ""
say "PASS: codex-review is installed. In Claude Code, ask for a 'codex review'."
