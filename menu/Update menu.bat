@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Menu.ps1"
set "RM=%ProgramFiles%\Rainmeter\Rainmeter.exe"
if exist "%RM%" "%RM%" !Refresh PersonaMenu
