@echo off
title Persona Desktop log
set "PD_LOG=%~dp0collect-log.ps1"
if not exist "%PD_LOG%" set "PD_LOG=%~dp0setup\collect-log.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PD_LOG%"
echo.
pause
