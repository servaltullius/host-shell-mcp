param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".gemini\antigravity\bin\host-shell-mcp"),
    [string]$ConfigPath = (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
    [string]$RulesPath  = (Join-Path $env:USERPROFILE ".gemini\GEMINI.md")
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Unregister-McpConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rawJson = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($rawJson)) { return }
    $cfgObj = $rawJson | ConvertFrom-Json
    if (($cfgObj.PSObject.Properties.Name -contains "mcpServers") -and ($null -ne $cfgObj.mcpServers)) {
        if ($cfgObj.mcpServers.PSObject.Properties.Name -contains "host-shell") {
            $backupPath = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $Path -Destination $backupPath -Force
            $cfgObj.mcpServers.PSObject.Properties.Remove("host-shell")
            $finalJson = $cfgObj | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($Path, $finalJson + "`r`n", $Utf8NoBom)
            Write-Host "[OK] Removed 'host-shell' from $Path (backup: $backupPath)" -ForegroundColor Green
        } else {
            Write-Host "[INFO] 'host-shell' entry not found in $Path" -ForegroundColor Gray
        }
    }
}

Write-Host "=== host-shell-mcp Uninstaller ===" -ForegroundColor Cyan

# 1. Remove entry from mcp_config.json (and legacy path if present)
Unregister-McpConfig -Path $ConfigPath
$LegacyConfigPath = Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json"
if ((Test-Path -LiteralPath $LegacyConfigPath) -and (-not $LegacyConfigPath.Equals($ConfigPath, [System.StringComparison]::OrdinalIgnoreCase))) {
    Unregister-McpConfig -Path $LegacyConfigPath
}

# 2. Remove managed rule block from GEMINI.md (only the block bounded by markers)
if (Test-Path -LiteralPath $RulesPath) {
    $ruleText = [System.IO.File]::ReadAllText($RulesPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $pattern = "(?s)\r?\n*<!-- host-shell-mcp:start -->.*?<!-- host-shell-mcp:end -->\r?\n*"
    if ($ruleText -match $pattern) {
        $cleaned = ([regex]::Replace($ruleText, $pattern, "`r`n")).Trim()
        if ([string]::IsNullOrEmpty($cleaned)) {
            [System.IO.File]::WriteAllText($RulesPath, "", $Utf8NoBom)
        } else {
            [System.IO.File]::WriteAllText($RulesPath, $cleaned + "`r`n", $Utf8NoBom)
        }
        Write-Host "[OK] Removed managed host-shell rule block from $RulesPath" -ForegroundColor Green
    }
}

# 3. Stop running process if located in InstallDir and remove folder
if (Test-Path -LiteralPath $InstallDir) {
    $TargetExe = Join-Path (Resolve-Path -LiteralPath $InstallDir).Path "host-shell-mcp.exe"
    try {
        $running = Get-Process -Name "host-shell-mcp" -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and ($_.Path.Equals($TargetExe, [System.StringComparison]::OrdinalIgnoreCase)) } catch { $false }
        }
        if ($running) {
            $running | Stop-Process -Force
            Start-Sleep -Milliseconds 300
        }
    } catch {}
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "[OK] Removed directory: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "[INFO] Install directory not found: $InstallDir" -ForegroundColor Gray
}

Write-Host "Done. Restart Antigravity to apply changes." -ForegroundColor Cyan
