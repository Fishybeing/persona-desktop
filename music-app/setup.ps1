param([switch]$Uninstall)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $env:LOCALAPPDATA "PersonaMusic"
$link = Join-Path ([Environment]::GetFolderPath("Programs")) "Persona Music.lnk"

Write-Host ""
if ($Uninstall) {
  Write-Host "  UNINSTALLING PERSONA MUSIC  " -ForegroundColor White -BackgroundColor DarkRed
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*PersonaMusic.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Remove-Item $link -Force -ErrorAction SilentlyContinue
  Remove-Item $app -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "   Removed the app. Your songs and playlists are still in the music player."
  exit 0
}

Write-Host "  PERSONA MUSIC  " -ForegroundColor White -BackgroundColor DarkRed
Write-Host "   An easy way to add songs to the Persona Desktop music player."

$livelyLib = Join-Path $env:LOCALAPPDATA "Lively Wallpaper\Library\wallpapers"
$player = Get-ChildItem $livelyLib -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "hud.js") } | Select-Object -First 1
if (-not $player) {
  Write-Host ""
  Write-Host "   Persona Desktop isn't installed yet. Install it first, then run this again:" -ForegroundColor Yellow
  Write-Host "   https://github.com/Fishybeing/persona-desktop"
  exit 1
}

New-Item -ItemType Directory -Force $app | Out-Null
Copy-Item (Join-Path $here "PersonaMusic.ps1") $app -Force
Copy-Item (Join-Path $here "setup.ps1") $app -Force
Copy-Item (Join-Path $here "Uninstall.bat") $app -Force

$icon = "$env:SystemRoot\System32\imageres.dll,103"
$packIcon = @(
  (Join-Path $env:LOCALAPPDATA "PersonaDesktop\menu\icons\music_icon.ico"),
  (Join-Path $env:LOCALAPPDATA "PersonaMenu\icons\music_icon.ico")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($packIcon) {
  Copy-Item $packIcon (Join-Path $app "music_icon.ico") -Force
  $icon = (Join-Path $app "music_icon.ico") + ",0"
}

$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($link)
$s.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" + (Join-Path $app "PersonaMusic.ps1") + "`""
$s.WorkingDirectory = $app
$s.IconLocation = $icon
$s.Description = "Add songs to the Persona Desktop music player"
$s.WindowStyle = 7
$s.Save()

Write-Host ""
Write-Host "  DONE  " -ForegroundColor White -BackgroundColor DarkRed
Write-Host "   Open it any time from Start > Persona Music."
Write-Host "   Opening it now..."
Start-Process $link
