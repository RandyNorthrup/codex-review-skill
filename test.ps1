# codex-review skill smoke test (Windows PowerShell / pwsh).
#
#   .\test.ps1          quick: CLI present, version, login, probe
#   .\test.ps1 -Full    also: real planted-bug review (slow, minutes) and a
#                       read-only check
param([switch]$Full)
$ErrorActionPreference = "Stop"

$MinVersion = [version]"0.144.1"
$Model = if ($env:CODEX_REVIEW_MODEL) { $env:CODEX_REVIEW_MODEL } else { "gpt-5.6-sol" }

function Ok($m)   { Write-Host "  ok: $m" }
function Fail($m) { Write-Host "FAIL: $m" -ForegroundColor Red; exit 1 }

Write-Host "== codex-review smoke test =="

# 1. CLI on PATH
$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codexCmd) { Fail "codex not on PATH. Run the installer: .\install.ps1" }
$CODEX = $codexCmd.Source
Ok "codex found at $CODEX"

# 2. Version
$verOut = & $CODEX --version 2>$null
if ("$verOut" -match '(\d+\.\d+\.\d+)') { $ver = [version]$Matches[1] } else { Fail "could not parse codex version" }
if ($ver -lt $MinVersion) { Fail "codex $ver is older than $MinVersion. Run: npm install -g @openai/codex@latest" }
Ok "version $ver >= $MinVersion"

# 3. Login
& $CODEX login status *> $null
if ($LASTEXITCODE -ne 0) { Fail "codex is not logged in. Run: codex login" }
Ok "logged in"

# 4. Skill installed
$skill = Join-Path $HOME ".claude\skills\codex-review\SKILL.md"
if (Test-Path $skill) { Ok "skill installed at $skill" } else { Write-Host "  warn: skill not found at $skill (run .\install.ps1)" }

# 5. Probe (auth + model + exec path)
$out = "Reply with exactly OK" | & $CODEX exec -m $Model --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 2>&1 | Out-String
if ($out -notmatch "OK") {
    Write-Host $out.Substring([Math]::Max(0, $out.Length - 2000))
    Fail "probe did not return OK (auth? model? usage limit?)"
}
Ok "probe returned OK (model $Model)"

# 6. Full: planted-bug review must find the bugs and stay read-only
if ($Full) {
    Write-Host "running full planted-bug review (xhigh - takes minutes)..."
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-review-test-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        @'
def average(items):
    total = 0
    for i in range(len(items) - 1):
        total += items[i]
    return total / len(items)
'@ | Set-Content -Path (Join-Path $tmp "sample.py")
        $prompt = "Read-only review of sample.py as it stands - there is no diff. Goal: correct arithmetic mean. Report ONLY bugs with file:line. Output ONLY the final findings list. Do NOT modify/create/delete any file; only read and report."
        $review = $prompt | & $CODEX -C $tmp exec -m $Model -c model_reasoning_effort="xhigh" `
            --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 2>&1 | Out-String
        if ($review -notmatch "(?i)off.by.one|last (item|element)|skips") {
            Write-Host $review; Fail "full review did not flag the planted off-by-one"
        }
        if ($review -notmatch "(?i)zero|empty") {
            Write-Host $review; Fail "full review did not flag division by zero on empty input"
        }
        if ((Get-ChildItem $tmp | Measure-Object).Count -ne 1) { Fail "review created files in the scratch dir (read-only violated)" }
        Ok "full review found the planted bugs and stayed read-only"
    } finally {
        Remove-Item -Recurse -Force $tmp
    }
}

Write-Host ""
Write-Host "PASS: codex-review environment is working"
