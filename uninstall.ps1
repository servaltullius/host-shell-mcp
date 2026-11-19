param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".gemini\antigravity\bin\host-shell-mcp"),
    [string]$ConfigPath = (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json")
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host "=== host-shell-mcp Uninstaller ===" -ForegroundColor Cyan

# 1. Remove entry from mcp_config.json
if (Test-Path -LiteralPath $ConfigPath) {
    $rawJson = [System.IO.File]::ReadAllText($ConfigPath, $Utf8NoBom)
    if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
        $cfgObj = $rawJson | ConvertFrom-Json
        if (($cfgObj.PSObject.Properties.Name -contains "mcpServers") -and ($null -ne $cfgObj.mcpServers)) {
            if ($cfgObj.mcpServers.PSObject.Properties.Name -contains "host-shell") {
                $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
                $cfgObj.mcpServers.PSObject.Properties.Remove("host-shell")
                $finalJson = $cfgObj | ConvertTo-Json -Depth 20
                [System.IO.File]::WriteAllText($ConfigPath, $finalJson + "`r`n", $Utf8NoBom)
                Write-Host "[OK] Removed 'host-shell' from $ConfigPath (backup: $backupPath)" -ForegroundColor Green
            } else {
                Write-Host "[INFO] 'host-shell' entry not found in $ConfigPath" -ForegroundColor Gray
            }
        }
    }
}

# 2. Stop running process if located in InstallDir and remove folder
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
