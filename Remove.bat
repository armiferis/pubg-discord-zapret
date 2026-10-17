@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
set "ZAPRET_PACKAGE_ROOT=%~dp0"
set "ZAPRET_PACKAGE_ACTION=remove"
if not exist "%~dp0Manage.ps1" (
 echo Сначала извлеките ZIP целиком в обычную папку.
 pause
 exit /b 1
)
fltmc >nul 2>&1
if errorlevel 1 (
 powershell.exe -NoLogo -NoProfile -Command "try { Start-Process -FilePath (Join-Path $env:ZAPRET_PACKAGE_ROOT 'Remove.bat') -Verb RunAs -ErrorAction Stop } catch { Write-Host $_.Exception.Message; exit 1 }"
 exit /b
)
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; Invoke-Expression ([IO.File]::ReadAllText((Join-Path $env:ZAPRET_PACKAGE_ROOT 'Manage.ps1'),[Text.Encoding]::UTF8))"
set "ZAPRET_RESULT=%errorlevel%"
echo.
pause
exit /b %ZAPRET_RESULT%
