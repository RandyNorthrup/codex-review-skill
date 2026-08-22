# codex-review

> Independent, sandboxed Codex reviews for Claude Code.

[![License: MIT](https://img.shields.io/badge/license-MIT-2ea44f.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Linux%20%7C%20macOS-4c1.svg)](#platform-support)

Run a second-opinion review over a diff or existing files. Codex reads the
local tree inside its read-only sandbox; Claude verifies every finding before
reporting it.

## Why use it?

- **Independent pass:** a separate model reviews the same local evidence.
- **Enforced read-only access:** Codex CLI runs with `-s read-only -a never`;
  the skill never uses the dangerous sandbox-bypass flag.
- **Isolated tool surface:** configured MCP servers, plugins, apps, and hooks
  are disabled for the review process.
- **Useful scopes:** commits, branch diffs, uncommitted changes, files, folders,
  and non-Git directories.
- **Triaged results:** Codex findings are leads. Claude checks each citation and
  rejects false positives before reporting conclusions.
- **Quiet execution:** `--ephemeral` prevents review sessions from being saved.

> [!IMPORTANT]
> No model review proves code is bug-free. This skill adds an independent,
> evidence-backed review pass; it does not replace tests, security analysis, or
> domain-specific validation.

## Quick start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- Internet access
- A ChatGPT account that can authenticate Codex CLI

The installer checks Node.js, npm, Codex CLI, Codex authentication, skill
installation, and a live model probe. It does **not** install Claude Code.

### Install

#### macOS or Linux

```bash
curl -fsSL https://raw.githubusercontent.com/RandyNorthrup/codex-review-skill/main/install.sh | bash
```

#### Windows PowerShell

```powershell
iwr -useb https://raw.githubusercontent.com/RandyNorthrup/codex-review-skill/main/install.ps1 | iex
```

Prefer inspecting scripts before execution? Clone first:

```bash
git clone https://github.com/RandyNorthrup/codex-review-skill.git
cd codex-review-skill
bash ./install.sh
```

```powershell
git clone https://github.com/RandyNorthrup/codex-review-skill.git
Set-Location codex-review-skill
.\install.ps1
```

Installers place the skill at:

| Scope | Location |
|---|---|
| Personal, macOS/Linux | `~/.claude/skills/codex-review/SKILL.md` |
| Personal, Windows | `%USERPROFILE%\.claude\skills\codex-review\SKILL.md` |
| Project only | `<repo>/.claude/skills/codex-review/SKILL.md` |

If an installed `SKILL.md` differs, the installer preserves it as
`SKILL.md.bak` before replacing it. Node.js or Codex CLI may be installed or
upgraded when missing or below the supported minimum.

## Use

Ask naturally or invoke `/codex-review`:

```text
Give me a Codex review of my uncommitted changes.
```

```text
Codex review commit abc1234. Goal: fix the job-queue race.
```

```text
Second set of eyes on src/core/scheduler.cpp as it stands; there is no diff.
```

Review output is limited to three categories:

1. bugs and correctness defects;
2. anything missing from the stated goal;
3. quality issues such as dead code, duplication, weak error handling, or
   unclear naming.

Findings include `file:line` evidence and severity. Claude then verifies each
finding against the actual local tree.

## Test

Quick test checks CLI discovery, version, login, installed skill, and an exact
live-model response:

```bash
bash ./test.sh
```

```powershell
.\test.ps1
```

Full test adds a real review of a planted-bug file. It checks expected findings,
the file hash, and the target directory inventory for persistent changes:

```bash
bash ./test.sh --full
```

```powershell
.\test.ps1 -Full
```

Live tests consume Codex quota. The included GitHub Actions workflow uses a
deterministic fake CLI to test cross-platform script control flow without
credentials or model usage.

## Platform support

| Platform | Installer | Test runner | Workflow coverage | Verified live host |
|---|---|---|---|---|
| Windows 10/11 | `install.ps1` | `test.ps1` | PowerShell 7 + Windows PowerShell 5.1 mocked flows | Windows 11, PowerShell 7 |
| Linux | `install.sh` | `test.sh` | Ubuntu 24.04, Bash mocked full flow | Kubuntu 26.04, Bash 5.3 |
| macOS | `install.sh` | `test.sh` | macOS 15, Bash mocked full flow | macOS 26.6 Intel, Bash 3.2 |

Current support floor: Codex CLI **0.149.0**. The default model is
`gpt-5.6-sol`; full reviews request `xhigh` reasoning. Model availability
depends on the account and can change independently of this repository.

Last live verification: **2026-08-21** with Codex CLI 0.149.0 on Windows 11,
Kubuntu 26.04, and macOS 26.6 Intel. Each platform passed its installer probe
and full planted-bug review through the read-only sandbox. The full tests also
confirmed that Codex preserved the target file hash and directory inventory.

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| `CODEX_REVIEW_MODEL` | Override model used by installers and tests | `gpt-5.6-sol` |
| `CLAUDE_SKILLS_DIR` | Override personal Claude skills root in installers and tests | Platform user skills directory |

## Safety model

Codex runs with a restricted invocation equivalent to:

```text
-s read-only -a never --disable plugins --disable apps --disable hooks
-c mcp_servers={} exec ... --ephemeral
```

This combination asks Codex CLI to enforce filesystem read-only access, denies
approval escalation, clears configured MCP servers, disables plugin/app/hook
tool surfaces, and avoids saving the session. User configuration remains loaded
because Codex CLI 0.149.0 on Windows rejects target reads when
`--ignore-user-config` is set; explicit CLI flags override side-effecting tool
configuration. Prompts also state the read-only rule, but prompt text is not
treated as the security boundary.

Review results and logs belong in a temporary directory outside the target.
Fixes are separate work and require explicit user authorization.

## Troubleshooting

| Problem | Resolution |
|---|---|
| `codex` missing or too old | Install current Codex CLI, then open a new shell and rerun the test. |
| `codex login status` fails | Run `codex login`. |
| Default model is unavailable | Set `CODEX_REVIEW_MODEL` to a model available to your account. |
| Usage-limit message | Retry after the reset time shown by Codex. |
| Empty result file | Read the captured log; the review did not complete successfully. |
| Read-only sandbox cannot start | Stop. Report platform and CLI version; do not bypass the sandbox. |

## Repository layout

| Path | Purpose |
|---|---|
| `SKILL.md` | Claude Code skill instructions |
| `install.sh`, `install.ps1` | Prerequisite checks, installation, and live probe |
| `test.sh`, `test.ps1` | Quick and full live validation |
| `tests/fake-codex.mjs` | Credential-free CI test double |
| `.github/workflows/verify.yml` | Windows, Linux, and macOS validation matrix |

## License

[MIT](LICENSE) © 2026 Randy Northrup
