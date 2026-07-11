# codex-review skill installer (Windows PowerShell / pwsh).
#
# Checks every prerequisite and installs what is missing:
#   1. Node.js / npm  (via winget if absent)
#   2. Codex CLI >= 0.144.1  (npm install -g @openai/codex@latest)
#   3. Codex login  (launches `codex login` if needed)
#   4. The skill itself -> ~\.claude\skills\codex-review\SKILL.md
#   5. A quick end-to-end probe
#
# Safe to re-run; re-running updates everything to latest.
$ErrorActionPreference = "Stop"

$Repo = "RandyNorthrup/codex-review-skill"
$Raw = "https://raw.githubusercontent.com/$Repo/main"
$MinVersion = [version]"0.144.1"
$Model = if ($env:CODEX_REVIEW_MODEL) { $env:CODEX_REVIEW_MODEL } else { "gpt-5.6-sol" }
$SkillDir = Join-Path $HOME ".claude\skills\codex-review"

function Ok($m)   { Write-Host "  ok: $m" }
function Fail($m) { Write-Host "FAIL: $m" -ForegroundColor Red; exit 1 }

Write-Host "== codex-review skill installer =="

# --- 1. Node / npm -----------------------------------------------------------
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "npm not found - trying to install Node.js via winget..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
        # pick up the new PATH without a new terminal
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path", "User")
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Fail "could not install Node.js automatically. Install it from https://nodejs.org, open a NEW terminal, and re-run this installer."
    }
}
Ok "npm $(npm --version)"

# --- 2. Codex CLI (>= $MinVersion) -------------------------------------------
function Get-CodexVersion($exe) {
    $out = & $exe --version 2>$null
    if ("$out" -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

$needCodex = $false
$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codexCmd) {
    Write-Host "codex not found - installing..."
    $needCodex = $true
} else {
    $ver = Get-CodexVersion $codexCmd.Source
    if (-not $ver) { $needCodex = $true }
    elseif ($ver -lt $MinVersion) {
        Write-Host "codex $ver is older than $MinVersion - updating..."
        $needCodex = $true
    }
}
if ($needCodex) {
    npm install -g @openai/codex@latest
    if ($LASTEXITCODE -ne 0) { Fail "npm install -g @openai/codex@latest failed" }
    $codexCmd = Get-Command codex -ErrorAction SilentlyContinue
    # PATH may still resolve to a stale app-managed copy - prefer the npm-global one
    $npmCodex = Join-Path $env:APPDATA "npm\codex.cmd"
    if ((Test-Path $npmCodex) -and ((-not $codexCmd) -or ((Get-CodexVersion $codexCmd.Source) -lt $MinVersion))) {
        $codexCmd = Get-Command $npmCodex
    }
    if (-not $codexCmd) { Fail "codex still not on PATH after install - open a NEW terminal and re-run this installer." }
}
$CODEX = $codexCmd.Source
$ver = Get-CodexVersion $CODEX
if ($ver -lt $MinVersion) { Fail "codex on PATH is $ver (< $MinVersion) and points at $CODEX - a stale copy is shadowing the npm one. Put $env:APPDATA\npm first on PATH." }
Ok "codex $ver at $CODEX"

# --- 3. Codex login ----------------------------------------------------------
& $CODEX login status *> $null
if ($LASTEXITCODE -eq 0) {
    Ok "codex is logged in"
} else {
    Write-Host "codex is not logged in - launching 'codex login' (finishes in your browser)..."
    & $CODEX login
    if ($LASTEXITCODE -ne 0) { Fail "codex login failed - run 'codex login' manually, then re-run this installer." }
    Ok "codex login complete"
}

# --- 4. Install the skill ----------------------------------------------------
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
$dest = Join-Path $SkillDir "SKILL.md"
$localSkill = if ($PSScriptRoot) { Join-Path $PSScriptRoot "SKILL.md" } else { $null }

if ($localSkill -and (Test-Path $localSkill)) {
    $newContent = Get-Content -Raw $localSkill          # running from a clone
} else {
    $newContent = (Invoke-WebRequest -UseBasicParsing "$Raw/SKILL.md").Content
    if (-not $newContent) { Fail "could not download SKILL.md from $Raw" }
}
if ((Test-Path $dest) -and ((Get-Content -Raw $dest) -ne $newContent)) {
    Copy-Item $dest "$dest.bak" -Force
    Write-Host "  note: existing SKILL.md differed (self-repairs?) - backed up to SKILL.md.bak"
}
Set-Content -Path $dest -Value $newContent -NoNewline
Ok "skill installed at $dest"

# --- 5. Probe ----------------------------------------------------------------
Write-Host "running a quick end-to-end probe (~30s)..."
$out = "Reply with exactly OK" | & $CODEX exec -m $Model --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 2>&1 | Out-String
if ($out -match "OK") {
    Ok "probe returned OK (model $Model)"
} else {
    Write-Host $out.Substring([Math]::Max(0, $out.Length - 2000))
    Fail "probe failed (usage limit? model access?). The skill IS installed; see the Self-repair section in SKILL.md."
}

Write-Host ""
Write-Host "PASS: codex-review is installed. In Claude Code, ask for a 'codex review'."
