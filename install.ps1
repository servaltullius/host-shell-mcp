param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".gemini\antigravity\bin\host-shell-mcp"),
    [string]$ConfigPath = (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoBase   = "https://raw.githubusercontent.com/servaltullius/host-shell-mcp/main"
$ReleaseExe = "https://github.com/servaltullius/host-shell-mcp/releases/latest/download/host-shell-mcp.exe"
$CscPath    = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

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

if (-not $ForceDownload -and (Test-Path -LiteralPath $CscPath)) {
    try {
        if ($LocalSrc -and (Test-Path -LiteralPath $LocalSrc)) {
            if (-not $LocalSrc.Equals($TargetSrc, [System.StringComparison]::OrdinalIgnoreCase)) {
                Copy-Item -LiteralPath $LocalSrc -Destination $TargetSrc -Force
            }
            Write-Host "[1/3] Compiling local Program.cs with built-in .NET csc.exe..." -ForegroundColor Gray
        } else {
            Write-Host "[1/3] Downloading Program.cs and compiling locally with built-in .NET csc.exe..." -ForegroundColor Gray
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
    Write-Host "[1/3] Downloading prebuilt host-shell-mcp.exe from GitHub Releases..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $ReleaseExe -OutFile $TargetExe -UseBasicParsing
    try { Unblock-File -LiteralPath $TargetExe -ErrorAction SilentlyContinue } catch {}
    Write-Host "      Downloaded: $TargetExe" -ForegroundColor Green
}

# 4. Smoke test MCP JSON-RPC initialize handshake
Write-Host "[2/3] Verifying MCP stdio handshake..." -ForegroundColor Gray
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
$respLine = $proc.StandardOutput.ReadLine()
if (-not $proc.WaitForExit(5000)) {
    try { $proc.Kill() } catch {}
}
if (-not $respLine -or ($respLine -notmatch '"serverInfo"') -or ($respLine -notmatch '"host-shell"')) {
    throw "MCP handshake verification failed. Output: $respLine"
}
Write-Host "      Verified OK (host-shell MCP ready)" -ForegroundColor Green

# 5. Safely merge into Antigravity mcp_config.json (with backup, UTF-8 no BOM)
Write-Host "[3/3] Registering in $ConfigPath..." -ForegroundColor Gray
$ConfigDir = Split-Path -Parent $ConfigPath
if (-not (Test-Path -LiteralPath $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$cfgObj = $null
if (Test-Path -LiteralPath $ConfigPath) {
    $rawJson = [System.IO.File]::ReadAllText($ConfigPath, $Utf8NoBom)
    if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
        $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
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
    command = $TargetExe
    args    = @()
}
$cfgObj.mcpServers | Add-Member -NotePropertyName "host-shell" -NotePropertyValue ([PSCustomObject]$entry) -Force

$finalJson = $cfgObj | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($ConfigPath, $finalJson + "`r`n", $Utf8NoBom)

Write-Host ""
Write-Host "[DONE] host-shell-mcp installed and registered!" -ForegroundColor Green
Write-Host "  Binary : $TargetExe"
Write-Host "  Config : $ConfigPath"
Write-Host ""
Write-Host "Next step: Restart Antigravity to load the 'host-shell' MCP server." -ForegroundColor Cyan
Write-Host ""
