---
name: codex-review
description: Independent second-opinion code review via the Codex CLI (GPT-5.6-sol, xhigh reasoning), running strictly read-only. Works for diff reviews (a commit, branch, or uncommitted changes) AND plain reviews of files/directories with no diff. Use when the user asks for a "codex review", a "second set of eyes", an independent/external review, or to double-check that a change has no bugs and nothing is missing before committing. Codex only reviews; it never edits code.
---

# Codex independent code review

Run Codex as a second, independent reviewer over code or a diff. Codex is a
different model (GPT-5.6-sol) than me, so it catches things I miss. It runs
**read-only** and must **never change code** - it only reports findings.

## The reviewer contract
- **Read-only, always.** Codex must not edit files, apply patches, or run
  write commands. The OS sandbox is bypassed on every platform (see
  "Sandbox policy" below), so read-only is enforced in the PROMPT: it always
  ends with the instruction "do NOT modify/create/delete; only read and
  report".
- **Two review scopes, both supported:**
  - **Diff review** - a commit sha, a branch diff, or uncommitted changes.
    Tell Codex to run `git show <sha>` / `git diff <base>` itself in the
    prompt.
  - **Plain review (no diff)** - named files, a directory, or a module,
    reviewed as they stand. No git required at all (`--skip-git-repo-check`
    covers non-repos). Just name the files/dirs in the prompt.
- **Report only three things:** (1) bugs / correctness defects, (2) anything
  missing versus the stated goal, (3) quality issues (dead code, duplication,
  weak error handling, unclear naming).
- **I never auto-apply Codex's output.** I read its findings, verify each one
  against the code myself, and surface the real ones to the user. A Codex
  finding is a lead, not a verdict.
- **Model + effort:** `-m gpt-5.6-sol` and `-c model_reasoning_effort="xhigh"`.
- **Prompts stay short** - one line of goal, one line of scope, one line of
  what to report.

## Locating the CLI (cross-platform)

Resolve `codex` from PATH; require codex-cli >= 0.144.1 (older versions error
"requires a newer version of Codex" on `gpt-5.6-sol`):

```bash
CODEX="$(command -v codex)"; "$CODEX" --version     # bash / zsh / Git Bash
```
```powershell
$CODEX = (Get-Command codex).Source; & $CODEX --version   # PowerShell
```

If it is missing or too old: `npm install -g @openai/codex@latest`.

Windows gotcha: there may be several Codex binaries installed. The npm-global
one (`%APPDATA%\npm\codex`) is the one kept current; app-managed copies under
`%LOCALAPPDATA%\OpenAI\Codex\bin\...` and `~\.codex\.sandbox-bin\` lag behind
(0.142.x, too old for gpt-5.6-sol). If `codex` on PATH resolves to a stale
copy, use the npm-global path explicitly.

Model notes: `gpt-5.6-sol` is the current best. `gpt-5.6` and `gpt-5.6-codex`
are NOT available on a ChatGPT account (400 "not supported"); only `-sol`
works. `gpt-5.5` is the fallback for older CLIs.

## Sandbox policy (all platforms: bypass)

Always pass `--dangerously-bypass-approvals-and-sandbox` and enforce
read-only in the PROMPT. Do NOT use `--sandbox read-only`: on Windows the OS
read-only sandbox is BROKEN (the low-privilege logon user fails to spawn),
and worse, it makes Codex read the wrong tree (stale GitHub instead of the
local working copy). Bypassing on every platform keeps the invocation
identical everywhere and guarantees Codex runs as the current user against
the REAL local tree - verify the run log shows the correct local HEAD. In a
git repo any stray change would be recoverable - and to date the prompt-level
read-only instruction has held.

## CLI flag placement

`-C/--cd` is a **global** flag, so it goes BEFORE the `exec` subcommand:
`codex -C "<dir>" exec ...`. Putting it after `exec` errors with
`unexpected argument '-C'`. `-C` can be omitted if the shell cwd is already
the target directory. `--skip-git-repo-check` is a subcommand flag (after
`exec`); always pass it - it is required for non-repo plain reviews and
harmless in repos.

## Feed the prompt through stdin

`codex exec` with the prompt as a command-line argument has hung in automation
("Reading additional input from stdin...") because a non-TTY stdin makes it
wait for EOF. **Pipe the prompt in** and omit the prompt argument - the pipe
closes stdin and it runs. (0.144.1 also accepts the positional-arg form, but
the stdin pipe is the safe default everywhere.)

```
"<prompt>" | codex exec [flags]        # correct
codex exec [flags] "<prompt>"          # has hung in automation - avoid
```

CRITICAL: `codex exec review` with a scope flag (`--commit` / `--base` /
`--uncommitted`) does NOT accept a custom prompt - passing one errors with
`'--commit <SHA>' cannot be used with '[PROMPT]'`. So the goal-injected review
must go through generic `codex exec` with the scope named in the prompt. Use
bare `exec review` only when the built-in reviewer prompt is enough and no
goal framing is needed.

## The one invocation (goal-framed, read-only)

Build the piped prompt from four parts:
1. **Scope** - e.g. `the change in git commit <sha>` (tell it to run
   `git show <sha>` itself), `the diff vs <branch> (run git diff <branch>)`,
   `uncommitted changes (run git diff)`, or for a plain review:
   `src/core/foo.cpp and src/core/foo.h as they stand - there is no diff`.
2. **Goal** - one line.
3. **What to report** - the three categories, `file:line`, ranked by severity,
   final findings list only.
4. **Read-only instruction** - do NOT modify/create/delete; only read and
   report.

Template prompt (fill the `<...>` parts):

```
Read-only review of <SCOPE>. Read the ACTUAL local working tree (do NOT rely
on remote/GitHub). Goal: <ONE-LINE GOAL>. Report ONLY: (1) bugs/correctness,
(2) anything missing vs the goal, (3) quality (dead code, duplication, error
handling, naming). Cite file:line, rank by severity. Output ONLY the final
findings list, no reasoning. Do NOT modify/create/delete any file; only read
and report.
```

**bash / zsh / Git Bash** (macOS, Linux, or the Bash tool on Windows):

```bash
CODEX="$(command -v codex)"
echo "<prompt>" | "$CODEX" -C "<repo-or-dir>" exec \
    -m gpt-5.6-sol -c model_reasoning_effort=xhigh \
    --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check \
    -o "<scratchpad>/codex-review.md" > "<scratchpad>/codex-log.txt" 2>&1
```

**PowerShell** (Windows):

```powershell
$CODEX = (Get-Command codex).Source
"<prompt>" | & $CODEX -C "<repo-or-dir>" exec `
    -m gpt-5.6-sol -c model_reasoning_effort="xhigh" `
    --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check `
    -o "<scratchpad>\codex-review.md" *> "<scratchpad>\codex-log.txt"
```

Bare built-in reviewer (no goal framing) is the only use for `exec review` and
its scope flags - and it CANNOT take a custom prompt:

```bash
"$CODEX" -C "<repo>" exec review \
    -m gpt-5.6-sol -c model_reasoning_effort=xhigh \
    --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check \
    --commit <sha> -o "<scratchpad>/codex-review.md"
```

## How to run it
1. Pick the scope from what the user asked: a diff (commit / branch /
   uncommitted) or a plain no-diff review of named files or directories.
2. Send the final message to a `-o` file in the scratchpad, and also redirect
   the whole run (bash: `> log 2>&1`; PowerShell: `*> log`) so you can see
   errors / the usage-limit line. xhigh is slow (minutes) - run it in the
   background and wait for it to finish.
3. When it finishes, Read the `-o` file (Codex's final report). If it is
   empty, Read the log file - the most common cause is the usage limit.
4. **Triage (verify every finding):** for each finding, check the actual code
   yourself - ideally spawn a Claude general-purpose subagent per finding that
   reads the local tree and returns CONFIRMED / FALSE-POSITIVE /
   FAIL-CLOSED-GAP with file:line + reachability. Codex "confirmed" has been a
   false positive more often than not (a real run: 4 findings -> 3 false
   positives, 1 pre-existing). Keep only what survives verification, and tell
   the user which is which. Never present Codex's list verbatim as fact.
5. Fixing anything is a separate, explicit step that **I** do (or the user
   approves) - Codex's read-only run never touched the code.
6. If any step fails, go to **Self-repair** below - do not abandon the review
   on the first error.

## Self-repair

This skill encodes facts that rot: CLI version, model names, flag syntax,
account limits. When an invocation fails, first check the known-failures
table. For anything new: DIAGNOSE, FIX, VERIFY with the self-test, then
**edit this SKILL.md** so the fix persists for the next run - update the
stale fact, date-stamp the change, keep the structure intact.

### Invariants - never change these during a repair
- Codex stays read-only. Never remove the read-only prompt instruction, and
  never let a "fix" involve Codex editing files.
- Every Codex finding still gets verified by me before reaching the user.
- The findings-only contract (bugs / missing-vs-goal / quality) stays.

### Known failures -> fixes
| Symptom | Cause | Fix |
|---|---|---|
| "requires a newer version of Codex" | CLI too old for the model | `npm install -g @openai/codex@latest`, then re-resolve from PATH (Windows: ensure the npm-global copy wins over app-managed copies) |
| 400 "model ... not supported" | model name rotted or not on this account | probe models in order: `gpt-5.6-sol`, then `gpt-5.5`; if both fail, discover current names (`codex --help`, release notes) and update the Model+effort line in this file |
| `unexpected argument '-C'` | `-C` placed after `exec` | `-C` is global: `codex -C <dir> exec ...` |
| `'--commit <SHA>' cannot be used with '[PROMPT]'` | scope flag combined with custom prompt | use generic `exec` with the scope named in the prompt |
| Hang: "Reading additional input from stdin..." | prompt passed as arg with non-TTY stdin | pipe the prompt via stdin, omit the prompt argument |
| Empty `-o` file | run died before the final message | Read the log: "hit your usage limit" -> wait for the printed reset; auth error -> user runs `codex login` |
| "You've hit your usage limit" | account cap | not a skill bug; retry after the printed reset time |
| Log shows wrong/stale HEAD or remote content | sandbox not bypassed | ensure `--dangerously-bypass-approvals-and-sandbox` is present |
| `codex: command not found` | not installed / not on PATH | `npm install -g @openai/codex@latest`; on Windows confirm `%APPDATA%\npm` is on PATH |

### Diagnose protocol (unknown failures)
1. `codex --version` - compare against what this file expects (>= 0.144.1).
2. `codex --help` and `codex exec --help` - flags move and rename; trust
   `--help` output over this file, then update this file to match.
3. Minimal probe, isolating CLI/auth/model from the review prompt:
   `echo "Reply with exactly OK" | codex exec -m gpt-5.6-sol --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check`
4. Change one variable at a time (model, flag, scope, prompt) until the
   failing part is isolated. Fix it, then run the self-test.

### Self-test (verifies a repair end to end)
1. Write a scratch file with planted bugs, e.g. a function that divides by
   `len(items)` without an empty check plus a `range(len(x) - 1)` loop.
2. Run the standard plain-review invocation from this file against the
   scratch dir.
3. PASS = the `-o` file contains findings that cite the planted bugs with
   file:line. FAIL = empty/irrelevant output; read the log and keep
   diagnosing.
4. Confirm read-only held: no new or modified files in the scratch dir.
5. Update this SKILL.md: correct the rotted fact(s) and refresh the
   "Verified" note in Notes with today's date and what was re-verified.

### Rules for editing this file
- Change only the rotted facts; keep the contract, invariants, structure, and
  warnings.
- Date-stamp material changes (e.g. "updated YYYY-MM-DD").
- If a documented workaround becomes unnecessary (e.g. a fixed CLI bug), keep
  a one-line historical note explaining why the safe form is still preferred
  rather than silently deleting it.

## Notes
- Prompt via stdin (see above); `-o <file>` captures the final message; add
  `--json` for a JSONL progress stream if wanted.
- Usage limit: the account has a Codex cap. A "hit your usage limit" line
  means wait for the printed reset time, not a broken command.
- If Codex reports an auth error, the user must run `codex login` once.
- Keep each review tightly scoped - a smaller diff/file set gives sharper
  findings and a faster run.
- Verified 2026-07-11 on Windows (codex-cli 0.144.1): both scopes work end to
  end - a plain no-diff file review in a non-git directory (Bash form) and a
  goal-framed commit review in a git repo (PowerShell form) both returned
  correct findings for planted bugs.
