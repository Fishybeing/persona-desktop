@echo off
title Persona Desktop setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\install.ps1"
echo.
pause
