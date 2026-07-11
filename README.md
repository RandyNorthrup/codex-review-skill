# codex-review — independent second-opinion code review skill for Claude Code

A [Claude Code](https://claude.com/claude-code) skill that runs the
[OpenAI Codex CLI](https://github.com/openai/codex) (GPT-5.6-sol, xhigh
reasoning) as a **second, independent reviewer** over your code. Because Codex
is a different model than Claude, it catches things Claude misses — and Claude
verifies every Codex finding before reporting it, so you get a triaged,
cross-checked review instead of raw output.

**Two review scopes, both supported:**

- **Diff review** — a commit, a branch diff, or uncommitted changes
- **Plain review** — files or directories as they stand, no diff, no git needed

**Hard rules baked into the skill:**

- Codex runs **strictly read-only** — it never edits, creates, or deletes files
- Every finding is verified against the actual code before you see it — a
  Codex finding is a lead, not a verdict
- The skill **self-repairs**: when a fact rots (CLI version, model name, flag
  syntax), the model diagnoses the failure, fixes it, re-verifies with a
  built-in self-test, and updates the skill file so the fix persists

## Install (one-liner)

**macOS / Linux / Git Bash:**

```bash
curl -fsSL https://raw.githubusercontent.com/RandyNorthrup/codex-review-skill/main/install.sh | bash
```

**Windows (PowerShell):**

```powershell
iwr -useb https://raw.githubusercontent.com/RandyNorthrup/codex-review-skill/main/install.ps1 | iex
```

The installer checks every prerequisite and installs whatever is missing:

1. **Node.js / npm** — installed via your package manager (brew / apt / dnf /
   pacman / winget) if absent
2. **Codex CLI >= 0.144.1** — `npm install -g @openai/codex@latest` if missing
   or too old
3. **Codex login** — launches `codex login` (browser sign-in with your ChatGPT
   account) if you are not logged in
4. **The skill** — installed to `~/.claude/skills/codex-review/SKILL.md`
5. **End-to-end probe** — a quick live call to confirm everything works

Safe to re-run any time; re-running updates everything to latest. If your
installed skill has diverged (self-repairs), the old copy is backed up to
`SKILL.md.bak` before being replaced.

### Install from a clone instead

```bash
git clone https://github.com/RandyNorthrup/codex-review-skill
cd codex-review-skill
./install.sh        # or  .\install.ps1  on Windows
```

### Project-scoped install (this repo only, instead of all projects)

Copy `SKILL.md` to `<your-repo>/.claude/skills/codex-review/SKILL.md`.

## Test it

Quick smoke test (seconds — checks CLI, version, login, live probe):

```bash
./test.sh            # or  .\test.ps1  on Windows
```

Full test (minutes — runs a real review over a planted-bug file and asserts
the bugs are found and nothing was modified):

```bash
./test.sh --full     # or  .\test.ps1 -Full  on Windows
```

## Use it

In any Claude Code session, just ask:

> give me a codex review of my uncommitted changes

> codex review commit abc1234 — goal was to fix the race in the job queue

> second set of eyes on src/core/scheduler.cpp, no diff, just review it

Claude picks the scope, runs Codex read-only, verifies each finding against
the code, and reports which findings are real and which are false positives.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- A ChatGPT account for `codex login` (the skill uses `gpt-5.6-sol`, the model
  available to ChatGPT accounts; set `CODEX_REVIEW_MODEL` to override in the
  installer/tests)
- Node.js (auto-installed by the installer if a package manager is available)

## How it stays working (self-repair)

`SKILL.md` encodes facts that rot over time — CLI versions, model names, flag
placement. The skill includes:

- a **known-failures table** (symptom → cause → fix) covering every failure
  mode hit so far
- a **diagnose protocol** for new failures (trust `--help` over the file,
  probe with one variable changed at a time)
- a **self-test** (planted-bug review) to prove a repair end to end
- **edit rules** so the model updates the skill file itself — date-stamped,
  without ever weakening the read-only contract

## Repo layout

| File | Purpose |
|---|---|
| `SKILL.md` | The skill itself — this is what gets installed |
| `install.sh` / `install.ps1` | One-shot installer: prereqs + CLI + login + skill + probe |
| `test.sh` / `test.ps1` | Smoke test; `--full` / `-Full` runs a real planted-bug review |

## License

MIT — see [LICENSE](LICENSE).
