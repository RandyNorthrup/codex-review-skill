# codex-review installer for Windows PowerShell and PowerShell 7.
#
# Checks or installs Node.js/npm and Codex CLI, verifies Codex login, installs
# the Claude Code skill, and runs an exact live probe in the read-only sandbox.
$ErrorActionPreference = "Stop"

$Repo = "RandyNorthrup/codex-review-skill"
$Raw = "https://raw.githubusercontent.com/$Repo/main"
$MinVersion = [version]"0.149.0"
$Model = if ($env:CODEX_REVIEW_MODEL) { $env:CODEX_REVIEW_MODEL } else { "gpt-5.6-sol" }
$SkillsRoot = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME ".claude\skills" }
$SkillDir = Join-Path $SkillsRoot "codex-review"

function Ok($Message) {
    Write-Output "  ok: $Message"
}

function Fail($Message) {
    throw "FAIL: $Message"
}

function Show-LogTail($Path) {
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Tail 20 | Write-Output
    }
}

function Get-CodexVersion($Executable) {
    $output = & $Executable --version 2>$null
    if ("$output" -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

function Resolve-NativeCommand($BaseName) {
    foreach ($name in "$BaseName.cmd", "$BaseName.exe", $BaseName) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

Write-Output "== codex-review skill installer =="

# --- 1. Node / npm -----------------------------------------------------------
$Npm = Resolve-NativeCommand "npm"
if (-not $Npm) {
    Write-Output "npm not found - trying to install Node.js via winget..."
    $Winget = Resolve-NativeCommand "winget"
    if ($Winget) {
        & $Winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { Fail "winget could not install Node.js" }
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path", "User")
        $Npm = Resolve-NativeCommand "npm"
    }
    if (-not $Npm) {
        Fail "could not install Node.js automatically. Install it from https://nodejs.org, open a new terminal, and rerun this installer."
    }
}
Ok "npm $(& $Npm --version)"

# --- 2. Codex CLI ------------------------------------------------------------
$needCodex = $false
$Codex = Resolve-NativeCommand "codex"
if (-not $Codex) {
    Write-Output "codex not found - installing..."
    $needCodex = $true
} else {
    $version = Get-CodexVersion $Codex
    if (-not $version) {
        $needCodex = $true
    } elseif ($version -lt $MinVersion) {
        Write-Output "codex $version is older than $MinVersion - updating..."
        $needCodex = $true
    }
}

if ($needCodex) {
    & $Npm install -g @openai/codex@latest
    if ($LASTEXITCODE -ne 0) { Fail "npm install -g @openai/codex@latest failed" }
    $Codex = Resolve-NativeCommand "codex"

    # PATH can resolve to a stale app-managed copy. Prefer npm-global when the
    # resolved command is still missing or too old.
    $npmCodex = Join-Path $env:APPDATA "npm\codex.cmd"
    $resolvedVersion = if ($Codex) { Get-CodexVersion $Codex } else { $null }
    if ((Test-Path -LiteralPath $npmCodex) -and ((-not $resolvedVersion) -or ($resolvedVersion -lt $MinVersion))) {
        $Codex = $npmCodex
    }
    if (-not $Codex) {
        Fail "codex is still not on PATH after installation. Open a new terminal and rerun this installer."
    }
}

$version = Get-CodexVersion $Codex
if (-not $version) { Fail "could not parse Codex CLI version from $Codex" }
if ($version -lt $MinVersion) {
    Fail "codex on PATH is $version (< $MinVersion) at $Codex. Remove or reorder stale installations, then rerun."
}
Ok "codex $version at $Codex"

# --- 3. Codex login ----------------------------------------------------------
& $Codex login status *> $null
if ($LASTEXITCODE -eq 0) {
    Ok "codex is logged in"
} else {
    Write-Output "codex is not logged in - launching 'codex login' in your browser..."
    & $Codex login
    if ($LASTEXITCODE -ne 0) {
        Fail "codex login failed. Run 'codex login' manually, then rerun this installer."
    }
    Ok "codex login complete"
}

# --- 4. Install the skill ----------------------------------------------------
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
$destination = Join-Path $SkillDir "SKILL.md"
$localSkill = if ($PSScriptRoot) { Join-Path $PSScriptRoot "SKILL.md" } else { $null }

if ($localSkill -and (Test-Path -LiteralPath $localSkill)) {
    $newContent = [System.IO.File]::ReadAllText($localSkill, [System.Text.Encoding]::UTF8)
} else {
    $newContent = (Invoke-WebRequest -UseBasicParsing "$Raw/SKILL.md").Content
    if (-not $newContent) { Fail "could not download SKILL.md from $Raw" }
}
if ((Test-Path -LiteralPath $destination) -and
    ([System.IO.File]::ReadAllText($destination, [System.Text.Encoding]::UTF8) -cne $newContent)) {
    Copy-Item -LiteralPath $destination -Destination "$destination.bak" -Force
    Write-Output "  note: existing SKILL.md differed; backed up to SKILL.md.bak"
}
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($destination, $newContent, $utf8WithoutBom)
Ok "skill installed at $destination"

# --- 5. Exact live probe -----------------------------------------------------
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-review-install-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $workDir | Out-Null
try {
    Write-Output "running a quick end-to-end probe..."
    $probeResult = Join-Path $workDir "probe-result.md"
    $probeLog = Join-Path $workDir "probe.log"
    "Reply with exactly OK" | & $Codex -s read-only -a never `
        --disable plugins --disable apps --disable hooks `
        -c "mcp_servers={}" exec -m $Model `
        --skip-git-repo-check --ephemeral -o $probeResult *> $probeLog
    $probeExit = $LASTEXITCODE
    if ($probeExit -ne 0) {
        Show-LogTail $probeLog
        Fail "probe failed (authentication, model access, usage limit, or sandbox startup). The skill was installed."
    }
    if (-not (Test-Path -LiteralPath $probeResult)) {
        Show-LogTail $probeLog
        Fail "probe produced no final-answer file"
    }
    $probeAnswer = (Get-Content -Raw -LiteralPath $probeResult).Trim()
    if ($probeAnswer -cne "OK") {
        Show-LogTail $probeLog
        Fail "probe response was not exactly OK"
    }
    Ok "probe returned exactly OK (model $Model, read-only sandbox)"
} finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}

Write-Output ""
Write-Output "PASS: codex-review is installed. In Claude Code, invoke /codex-review or ask for a Codex review."
