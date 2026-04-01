@echo off
:: Thin wrapper: launches start.ps1 with PowerShell
:: All logic is in start.ps1 for full feature parity with start.sh

:: Check if PowerShell is available
where powershell >nul 2>&1
if errorlevel 1 (
    echo Error: PowerShell is required but not found.
    echo PowerShell comes pre-installed on Windows 10 and later.
    echo Please install PowerShell: https://aka.ms/powershell
    exit /b 1
)

:: Forward all arguments to PowerShell script
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0start.ps1" %*
