@echo off
setlocal
set "CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ERROR] .NET Framework 4.x csc.exe not found at %CSC%
    exit /b 1
)
"%CSC%" /nologo /optimize+ /target:exe /r:System.Web.Extensions.dll /out:"%~dp0host-shell-mcp.exe" "%~dp0Program.cs"
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)
echo [OK] Built %~dp0host-shell-mcp.exe
endlocal
