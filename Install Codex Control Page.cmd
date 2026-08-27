@echo off
setlocal
title Install Codex Control Page
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\install.ps1"
if errorlevel 1 (
  echo.
  echo Installation did not complete. No existing Stream Deck page was intentionally replaced.
) else (
  echo.
  echo Installation complete.
)
echo.
pause
