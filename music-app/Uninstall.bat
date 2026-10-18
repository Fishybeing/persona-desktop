@echo off
title Uninstall Persona Music
copy /y "%~dp0setup.ps1" "%TEMP%\persona-music-setup.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\persona-music-setup.ps1" -Uninstall
del "%TEMP%\persona-music-setup.ps1" >nul 2>&1
echo.
pause
