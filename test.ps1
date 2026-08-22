# codex-review skill smoke test for Windows PowerShell and PowerShell 7.
#
#   .\test.ps1          quick CLI, version, login, and live probe
#   .\test.ps1 -Full    planted-bug review plus read-only checks
param([switch]$Full)
$ErrorActionPreference = "Stop"

$MinVersion = [version]"0.149.0"
$Model = if ($env:CODEX_REVIEW_MODEL) { $env:CODEX_REVIEW_MODEL } else { "gpt-5.6-sol" }

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

function Get-TreeSnapshot($Root) {
    $rootPath = (Resolve-Path -LiteralPath $Root).Path
    return (Get-ChildItem -LiteralPath $rootPath -Recurse -Force |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($rootPath.Length)
            "$relative|$($_.PSIsContainer)|$($_.Length)"
        }) -join "`n"
}

Write-Output "== codex-review smoke test =="

# 1. CLI on PATH
function Resolve-CodexExecutable {
    foreach ($name in "codex.cmd", "codex.exe", "codex") {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

$Codex = Resolve-CodexExecutable
if (-not $Codex) { Fail "codex executable not on PATH. Run the installer: .\install.ps1" }
Ok "codex found at $Codex"

# 2. Version
$versionOutput = & $Codex --version 2>$null
if ("$versionOutput" -match '(\d+\.\d+\.\d+)') {
    $version = [version]$Matches[1]
} else {
    Fail "could not parse codex version"
}
if ($version -lt $MinVersion) {
    Fail "codex $version is older than $MinVersion. Install the current Codex CLI."
}
Ok "version $version >= $MinVersion"

# 3. Login
& $Codex login status *> $null
if ($LASTEXITCODE -ne 0) { Fail "codex is not logged in. Run: codex login" }
Ok "logged in"

# 4. Skill installed
$skillsRoot = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME ".claude\skills" }
$skillPath = Join-Path $skillsRoot "codex-review\SKILL.md"
if (-not (Test-Path -LiteralPath $skillPath)) {
    Fail "skill not found at $skillPath. Run .\install.ps1"
}
$sourceSkill = Join-Path $PSScriptRoot "SKILL.md"
if ((Test-Path -LiteralPath $sourceSkill) -and
    ((Get-FileHash -LiteralPath $sourceSkill).Hash -cne (Get-FileHash -LiteralPath $skillPath).Hash)) {
    Fail "installed skill differs from repository SKILL.md. Rerun .\install.ps1"
}
Ok "current skill installed at $skillPath"

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-review-test-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $workDir | Out-Null
$testSucceeded = $false

try {
    # 5. Exact live probe using the enforced read-only sandbox
    $probeResult = Join-Path $workDir "probe-result.md"
    $probeLog = Join-Path $workDir "probe.log"
    "Reply with exactly OK" | & $Codex -s read-only -a never `
        --disable plugins --disable apps --disable hooks `
        -c "mcp_servers={}" exec -m $Model `
        --skip-git-repo-check --ephemeral -o $probeResult *> $probeLog
    $probeExit = $LASTEXITCODE
    if ($probeExit -ne 0) {
        Show-LogTail $probeLog
        Fail "probe failed (authentication, model access, usage limit, or sandbox startup)"
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

    # 6. Full: planted-bug review must find both bugs and preserve target state
    if ($Full) {
        Write-Output "running full planted-bug review (xhigh; may take minutes)..."
        $target = Join-Path $workDir "target"
        New-Item -ItemType Directory -Path $target | Out-Null
        $samplePath = Join-Path $target "sample.py"
        @'
def average(items):
    total = 0
    for i in range(len(items) - 1):
        total += items[i]
    return total / len(items)
'@ | Set-Content -LiteralPath $samplePath

        $beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $samplePath).Hash
        $beforeTree = Get-TreeSnapshot $target
        $reviewResult = Join-Path $workDir "review-result.md"
        $reviewLog = Join-Path $workDir "review.log"
        $prompt = "Read-only review of sample.py as it stands; there is no diff. Read the actual local working tree. Goal: correct arithmetic mean. Report only: (1) bugs and correctness defects, (2) anything missing from the goal, and (3) quality issues. Cite file:line, rank by severity, and output only the final findings list. Do not modify, create, or delete files."

        $prompt | & $Codex -C $target -s read-only -a never `
            --disable plugins --disable apps --disable hooks `
            -c "mcp_servers={}" exec `
            -m $Model -c model_reasoning_effort="xhigh" `
            --skip-git-repo-check --ephemeral -o $reviewResult *> $reviewLog
        $reviewExit = $LASTEXITCODE
        if ($reviewExit -ne 0) {
            Show-LogTail $reviewLog
            Fail "full review command failed"
        }
        if (-not (Test-Path -LiteralPath $reviewResult)) {
            Show-LogTail $reviewLog
            Fail "full review produced no final-answer file"
        }
        $review = Get-Content -Raw -LiteralPath $reviewResult
        if ($review -notmatch '(?i)off.by.one|skip(s|ped|ping)?|omit(s|ted|ting)?|exclud(e|es|ed|ing)?|(last|final) (item|element|value)') {
            Write-Output $review
            Fail "full review did not flag the planted off-by-one"
        }
        if ($review -notmatch '(?i)division by zero|zero|empty') {
            Write-Output $review
            Fail "full review did not flag empty-input division by zero"
        }

        $afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $samplePath).Hash
        $afterTree = Get-TreeSnapshot $target
        if ($beforeHash -cne $afterHash) { Fail "review modified sample.py (read-only violated)" }
        if ($beforeTree -cne $afterTree) { Fail "review changed target directory inventory (read-only violated)" }
        Ok "full review found planted bugs and preserved target hash and inventory"
    }

    $testSucceeded = $true
    Write-Output ""
    Write-Output "PASS: codex-review environment is working"
} finally {
    if ($testSucceeded -and (Test-Path -LiteralPath $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    } elseif (Test-Path -LiteralPath $workDir) {
        Write-Output "  debug artifacts preserved at $workDir"
    }
}
