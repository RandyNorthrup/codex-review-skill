---
name: codex-review
description: Run an independent, read-only code review with the OpenAI Codex CLI. Use for second-opinion reviews of commits, branch diffs, uncommitted changes, or files and directories as they stand. Report verified findings only; never edit reviewed code.
---

# Codex independent code review

Use Codex CLI as a second reviewer. Codex produces leads; verify every lead
against the local code before reporting it to the user.

## Contract

- Review only. Do not edit, create, or delete files in the target tree.
- Enforce read-only access with Codex's `read-only` sandbox and approvals set
  to `never`. Never use `--dangerously-bypass-approvals-and-sandbox`.
- Isolate the reviewer from configured MCP servers, plugins, apps, and hooks.
  These tools are outside the filesystem sandbox and could have side effects.
- Use `--ephemeral` so review sessions are not persisted.
- Support both diff reviews and plain reviews of files or directories.
- Report only:
  1. bugs and correctness defects;
  2. work missing from the stated goal;
  3. quality issues such as dead code, duplication, weak error handling, or
     unclear naming.
- Require `file:line` evidence and rank findings by severity.
- Independently verify each finding. Mark false positives as rejected rather
  than presenting Codex output as fact.
- Treat fixes as a separate task requiring user authorization.

## Prerequisites

Resolve `codex` from `PATH` and require Codex CLI 0.149.0 or newer. This floor
is tied to the currently verified cross-platform invocation and Windows
read-only sandbox behavior, not to a permanent model guarantee.

Use `gpt-5.6-sol` by default with `xhigh` reasoning. If the user set
`CODEX_REVIEW_MODEL`, use that value. If the default model is unavailable,
report the failure and ask before changing the configured model.

```bash
CODEX="$(command -v codex)"
"$CODEX" --version
```

```powershell
$Codex = (Get-Command codex.cmd -ErrorAction SilentlyContinue).Source
if (-not $Codex) { $Codex = (Get-Command codex.exe).Source }
& $Codex --version
```

## Build the prompt

Keep it short and include four parts:

1. Scope: commit, branch diff, uncommitted changes, or named paths as they
   currently exist.
2. Goal: one sentence describing intended behavior.
3. Output contract: the three finding categories, `file:line`, severity order,
   and final findings only.
4. Safety: read only; do not modify, create, or delete files.

Template:

```text
Read-only review of <SCOPE>. Read the actual local working tree; do not rely on
remote or GitHub content. Goal: <ONE-LINE GOAL>. Report only: (1) bugs and
correctness defects, (2) anything missing from the goal, and (3) quality issues
such as dead code, duplication, weak error handling, or unclear naming. Cite
file:line and rank by severity. Output only the final findings list. Do not
modify, create, or delete files.
```

For a diff review, tell Codex which read commands to use:

- Commit: `git show <sha>`.
- Branch: `git diff <base>...HEAD`.
- All uncommitted work: `git status --short`, `git diff HEAD`, then inspect
  every untracked path reported by status. Plain `git diff` is insufficient
  because it omits staged and untracked changes.
- Plain review: name the files or directories and state that there is no diff.

## Run Codex

Pipe the prompt through standard input. Write Codex's final answer and full log
to a temporary directory outside the reviewed tree.

### Bash, zsh, or Git Bash

```bash
MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-sol}"
printf '%s\n' "$PROMPT" | "$CODEX" -C "$TARGET" -s read-only -a never \
  --disable plugins --disable apps --disable hooks \
  -c 'mcp_servers={}' exec \
  -m "$MODEL" -c model_reasoning_effort=xhigh \
  --skip-git-repo-check --ephemeral \
  -o "$RESULT" >"$LOG" 2>&1
```

### PowerShell

```powershell
$Model = if ($env:CODEX_REVIEW_MODEL) { $env:CODEX_REVIEW_MODEL } else { "gpt-5.6-sol" }
$Prompt | & $Codex -C $Target -s read-only -a never `
  --disable plugins --disable apps --disable hooks `
  -c "mcp_servers={}" exec `
  -m $Model -c model_reasoning_effort="xhigh" `
  --skip-git-repo-check --ephemeral `
  -o $Result *> $Log
```

`-C`, `-s`, `-a`, `--disable`, and the MCP override are global flags and
therefore appear before `exec`. `--skip-git-repo-check`, `--ephemeral`, and
`-o` are `exec` flags.

## Triage

1. Read the final-answer file. If it is absent or empty, inspect the log.
2. For every finding, open the cited lines and trace reachable behavior.
3. Classify it as confirmed, false positive, or unresolved.
4. Report confirmed findings first. Disclose unresolved items and why they
   could not be verified. Do not copy raw model output as a verdict.
5. If no finding survives verification, say so and state the tested scope.

## Recovery

On failure, diagnose without weakening the sandbox:

1. Run `codex --version`, `codex login status`, `codex --help`, and
   `codex exec --help`.
2. Check the log for authentication, model-access, usage-limit, and flag errors.
3. Re-run the repository smoke test after correcting the environment.
4. Never bypass the sandbox or re-enable external tools as a workaround. Do
   not rewrite this skill unless the user explicitly asks for an update.

Common fixes:

| Symptom | Action |
|---|---|
| CLI missing or older than 0.149.0 | Install current Codex CLI, then resolve `codex` from `PATH` again. |
| Authentication failure | Run `codex login`. |
| Model unavailable | Set `CODEX_REVIEW_MODEL` to a model available to the user's account, with approval. |
| Usage limit | Wait for the reset time shown in the log. |
| Empty final-answer file | Inspect the full log; do not treat the review as successful. |
| Read-only sandbox failure | Stop and report the platform/CLI failure; never fall back to danger-full-access. |

## Verification note

Invocation and tests last live-verified on 2026-08-21 with Codex CLI 0.149.0 on
Windows 11, Kubuntu 26.04, and macOS 26.6 Intel. Installer probes and planted-bug
reviews passed through the read-only sandbox; full tests preserved the target
file hash and directory inventory. The included workflow is configured to test
mocked Bash and PowerShell control flow without account-bound model calls.
