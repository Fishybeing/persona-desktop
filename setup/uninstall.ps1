$ErrorActionPreference = "Continue"
$app = Join-Path $env:LOCALAPPDATA "PersonaDesktop"
$stateFile = Join-Path $app "state.json"
$state = if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json } else { $null }
$wpDir = if ($state -and $state.wallpaper) { $state.wallpaper } else { Join-Path $env:LOCALAPPDATA "Lively Wallpaper\Library\wallpapers\persona-monorail" }
$livelyExe = Join-Path $env:LOCALAPPDATA "Programs\Lively Wallpaper\Lively.exe"
$rmExe = Join-Path $env:ProgramFiles "Rainmeter\Rainmeter.exe"

Write-Host ""
Write-Host "  UNINSTALLING PERSONA DESKTOP  " -ForegroundColor White -BackgroundColor DarkRed

$music = Join-Path $wpDir "music"
$exts = ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac", ".wav", ".webm"
$songs = @(Get-ChildItem $music -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension.ToLower() })
if ($songs.Count) {
  $keep = Join-Path ([Environment]::GetFolderPath("MyMusic")) "Persona Desktop music"
  New-Item -ItemType Directory -Force $keep | Out-Null
  foreach ($s in $songs) {
    $rel = $s.FullName.Substring($music.Length + 1)
    $dest = Join-Path $keep $rel
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Move-Item $s.FullName $dest -Force
  }
  Write-Host "   Your $($songs.Count) songs were moved to $keep"
}

if (Test-Path $livelyExe) {
  & $livelyExe closewp --monitor -1
  Start-Sleep 3
}
if (Test-Path $wpDir) { Remove-Item $wpDir -Recurse -Force }
Write-Host "   Removed the wallpaper."

$rmIni = Join-Path $env:APPDATA "Rainmeter\Rainmeter.ini"
$skinRoot = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Rainmeter\Skins"
if (Test-Path $rmIni) {
  $sp = Get-Content $rmIni | Where-Object { $_ -like "SkinPath=*" } | Select-Object -First 1
  if ($sp) { $skinRoot = $sp.Substring(9).TrimEnd("\") }
}
if ((Test-Path $rmExe) -and (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
  & $rmExe "!DeactivateConfig" "PersonaMenu"
  & $rmExe "!DeactivateConfig" "Persona 5 System"
  Start-Sleep 2
}
foreach ($n in "PersonaMenu", "Persona 5 System") {
  $p = Join-Path $skinRoot $n
  if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}
Write-Host "   Removed the menu and system bars."

if ($state -and $state.icons) {
  $clsid = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID"
  foreach ($c in $state.icons.PSObject.Properties) {
    $key = "$clsid\$($c.Name)\DefaultIcon"
    if ($c.Value.__none) { Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue; continue }
    foreach ($v in $c.Value.PSObject.Properties) {
      if ($null -eq $v.Value) { Remove-ItemProperty $key -Name $v.Name -ErrorAction SilentlyContinue }
      else { Set-ItemProperty $key -Name $v.Name -Value $v.Value }
    }
  }
  Write-Host "   Restored your Recycle Bin and This PC icons."
}

if ($state -and $state.startupShortcut) {
  Remove-Item (Join-Path ([Environment]::GetFolderPath("Startup")) "Rainmeter.lnk") -Force -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path ([Environment]::GetFolderPath("Programs")) "Persona Desktop") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $app -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "   Done. Lively Wallpaper and Rainmeter are still installed in case you use them for other things."
Write-Host "   To remove them too, run:"
Write-Host "     winget uninstall rocksdanister.LivelyWallpaper"
Write-Host "     winget uninstall Rainmeter.Rainmeter"
