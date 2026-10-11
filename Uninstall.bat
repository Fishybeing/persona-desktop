@echo off
title Uninstall Persona Desktop
set "PD_SRC=%~dp0uninstall.ps1"
if not exist "%PD_SRC%" set "PD_SRC=%~dp0setup\uninstall.ps1"
copy /y "%PD_SRC%" "%TEMP%\persona-desktop-uninstall.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\persona-desktop-uninstall.ps1"
del "%TEMP%\persona-desktop-uninstall.ps1" >nul 2>&1
echo.
pause
