param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".gemini\antigravity\bin\host-shell-mcp"),
    [string]$ConfigPath = (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
    [string]$RulesPath  = (Join-Path $env:USERPROFILE ".gemini\GEMINI.md"),
    [switch]$SkipRule,
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$RepoBase   = "https://raw.githubusercontent.com/servaltullius/host-shell-mcp/main"
$ReleaseExe = "https://github.com/servaltullius/host-shell-mcp/releases/latest/download/host-shell-mcp.exe"
$CscCandidates = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$CscPath   = $CscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Register-McpConfig {
    param(
        [string]$Path,
        [string]$ExePath
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $cfgObj = $null
    if (Test-Path -LiteralPath $Path) {
        $rawJson = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
            $backupPath = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $Path -Destination $backupPath -Force
            Write-Host "      Backup created: $backupPath" -ForegroundColor DarkGray
            $cfgObj = $rawJson | ConvertFrom-Json
        }
    }

    if ($null -eq $cfgObj) {
        $cfgObj = New-Object PSObject
    }

    if (-not ($cfgObj.PSObject.Properties.Name -contains "mcpServers") -or $null -eq $cfgObj.mcpServers) {
        $cfgObj | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue (New-Object PSObject) -Force
    }

    $entry = [ordered]@{
        command = $ExePath
        args    = @()
    }
    $cfgObj.mcpServers | Add-Member -NotePropertyName "host-shell" -NotePropertyValue ([PSCustomObject]$entry) -Force

    $finalJson = $cfgObj | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $finalJson + "`r`n", $Utf8NoBom)
    Write-Host "      Updated: $Path" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== host-shell-mcp One-Touch Installer ===" -ForegroundColor Cyan

# 1. Prepare install directory
if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
$InstallDir = (Resolve-Path -LiteralPath $InstallDir).Path
$TargetExe  = Join-Path $InstallDir "host-shell-mcp.exe"
$TargetSrc  = Join-Path $InstallDir "Program.cs"

# 2. Stop existing instance at the exact target path if locked (for seamless upgrades)
try {
    $running = Get-Process -Name "host-shell-mcp" -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and ($_.Path.Equals($TargetExe, [System.StringComparison]::OrdinalIgnoreCase)) } catch { $false }
    }
    if ($running) {
        Write-Host "[INFO] Stopping existing host-shell-mcp process at target path..." -ForegroundColor Yellow
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 300
    }
} catch {}

# 3. Acquire binary: prefer local source compile (avoids SmartScreen MOTW), fallback to release download
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { "" }
$LocalSrc  = if ($ScriptDir) { Join-Path $ScriptDir "Program.cs" } else { "" }
$BuiltOk   = $false

if (-not $ForceDownload -and $CscPath) {
    try {
        if ($LocalSrc -and (Test-Path -LiteralPath $LocalSrc)) {
            if (-not $LocalSrc.Equals($TargetSrc, [System.StringComparison]::OrdinalIgnoreCase)) {
                Copy-Item -LiteralPath $LocalSrc -Destination $TargetSrc -Force
            }
            Write-Host "[1/4] Compiling local Program.cs with built-in .NET csc.exe..." -ForegroundColor Gray
        } else {
            Write-Host "[1/4] Downloading Program.cs and compiling locally with built-in .NET csc.exe..." -ForegroundColor Gray
            Invoke-WebRequest -Uri "$RepoBase/Program.cs" -OutFile $TargetSrc -UseBasicParsing
        }

        $cscOut = & $CscPath /nologo /optimize+ /target:exe /r:System.Web.Extensions.dll "/out:$TargetExe" "$TargetSrc" 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $TargetExe)) {
            $BuiltOk = $true
            Write-Host "      Build succeeded: $TargetExe" -ForegroundColor Green
        } else {
            Write-Warning "Local csc.exe build failed: $($cscOut -join ' ')"
        }
    } catch {
        Write-Warning "Local compile path failed ($($_.Exception.Message)); falling back to Release binary."
    }
}

if (-not $BuiltOk) {
    Write-Host "[1/4] Downloading prebuilt host-shell-mcp.exe from GitHub Releases..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $ReleaseExe -OutFile $TargetExe -UseBasicParsing
    try { Unblock-File -LiteralPath $TargetExe -ErrorAction SilentlyContinue } catch {}
    Write-Host "      Downloaded: $TargetExe" -ForegroundColor Green
}

# 4. Smoke test MCP JSON-RPC initialize handshake (with timeout)
Write-Host "[2/4] Verifying MCP stdio handshake..." -ForegroundColor Gray
$initReq = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $TargetExe
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = $Utf8NoBom

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$proc.StandardInput.WriteLine($initReq)
$proc.StandardInput.Close()
$readTask = $proc.StandardOutput.ReadLineAsync()
$respLine = if ($readTask.Wait(5000)) { $readTask.Result } else { $null }
if (-not $proc.WaitForExit(5000)) {
    try { $proc.Kill() } catch {}
}
if (-not $respLine -or ($respLine -notmatch '"serverInfo"') -or ($respLine -notmatch '"host-shell"')) {
    throw "MCP handshake verification failed. Output: $respLine"
}
Write-Host "      Verified OK (host-shell MCP ready)" -ForegroundColor Green

# 5. Safely merge into Antigravity mcp_config.json (and legacy path if already present)
Write-Host "[3/4] Registering MCP configuration..." -ForegroundColor Gray
Register-McpConfig -Path $ConfigPath -ExePath $TargetExe

$LegacyConfigPath = Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json"
if ((Test-Path -LiteralPath $LegacyConfigPath) -and (-not $LegacyConfigPath.Equals($ConfigPath, [System.StringComparison]::OrdinalIgnoreCase))) {
    Write-Host "      Detected legacy Antigravity config; updating as well..." -ForegroundColor Gray
    Register-McpConfig -Path $LegacyConfigPath -ExePath $TargetExe
}

# 6. Register global usage rule in GEMINI.md so Antigravity invokes host-shell proactively
if (-not $SkipRule) {
    Write-Host "[4/4] Checking global agent rule ($RulesPath)..." -ForegroundColor Gray
    $ruleDir = Split-Path -Parent $RulesPath
    if (-not (Test-Path -LiteralPath $ruleDir)) {
        New-Item -ItemType Directory -Path $ruleDir -Force | Out-Null
    }
    $existingRule = if (Test-Path -LiteralPath $RulesPath) {
        [System.IO.File]::ReadAllText($RulesPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    } else { "" }

    $startMarker = "<!-- host-shell-mcp:start -->"
    $endMarker   = "<!-- host-shell-mcp:end -->"
    $ruleBlock = @(
        $startMarker,
        "# Windows Host Shell & Elevation",
        "- Windows built-in ``run_command`` runs in an isolated hidden desktop (``exebox-*``) and Job Object even in Turbo mode, so GUI app launches (``WinSta0\Default``) and UAC elevation (``sudo``/``RunAs``) can fail or hang.",
        "- For Administrator/elevated tasks (services, scheduled tasks, system registry), use the ``host-shell`` MCP server's ``execute_elevated`` tool to request standard Windows UAC approval instead of ``run_command``.",
        "- For commands requiring the interactive user desktop session (``WinSta0\Default``), GUI apps (use ``Start-Process`` for non-blocking launch), or window/process interaction, prefer the ``host-shell`` MCP server's ``execute_command`` tool.",
        $endMarker
    ) -join "`r`n"

    if ($existingRule -match [regex]::Escape($startMarker) -or $existingRule -match "# Windows Host Shell & Elevation") {
        Write-Host "      Rule already present in $RulesPath (skipped)" -ForegroundColor DarkGray
    } else {
        $sep = if ([string]::IsNullOrWhiteSpace($existingRule)) { "" } else { "`r`n`r`n" }
        $newContent = $existingRule.TrimEnd() + $sep + $ruleBlock + "`r`n"
        [System.IO.File]::WriteAllText($RulesPath, $newContent, $Utf8NoBom)
        Write-Host "      Added host-shell usage rule to $RulesPath" -ForegroundColor Green
    }
} else {
    Write-Host "[4/4] Skipped global rule update (-SkipRule)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "[DONE] host-shell-mcp installed and configured!" -ForegroundColor Green
Write-Host "  Binary : $TargetExe"
Write-Host "  Config : $ConfigPath"
if (-not $SkipRule) { Write-Host "  Rules  : $RulesPath" }
Write-Host ""
Write-Host "Next step: Restart Antigravity to load the 'host-shell' MCP server." -ForegroundColor Cyan
Write-Host ""
