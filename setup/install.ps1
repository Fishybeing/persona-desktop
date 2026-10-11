param([switch]$SkipApps, [string]$TestRoot)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

$src = Split-Path -Parent $PSScriptRoot
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
$monorailPage = "https://moewalls.com/anime/yuki-x-aigis-in-the-train-persona-3-reload-live-wallpaper/"
$stillUrl = "https://w.wallhaven.cc/full/k8/wallhaven-k8zd97.jpg"

function Step($m) { Write-Host ""; Write-Host ">> $m" -ForegroundColor Red }
function Info($m) { Write-Host "   $m" }

if ($TestRoot) {
  $local = Join-Path $TestRoot "Local"; $roaming = Join-Path $TestRoot "Roaming"; $docs = Join-Path $TestRoot "Documents"
  $startMenu = Join-Path $TestRoot "StartMenu"; $startup = Join-Path $TestRoot "Startup"; $downloads = Join-Path $TestRoot "Downloads"
} else {
  $local = $env:LOCALAPPDATA; $roaming = $env:APPDATA; $docs = [Environment]::GetFolderPath("MyDocuments")
  $startMenu = [Environment]::GetFolderPath("Programs"); $startup = [Environment]::GetFolderPath("Startup")
  $downloads = (New-Object -ComObject Shell.Application).Namespace("shell:Downloads").Self.Path
}
$app = Join-Path $local "PersonaDesktop"
$livelyExe = Join-Path $local "Programs\Lively Wallpaper\Lively.exe"
$livelyData = Join-Path $local "Lively Wallpaper"
$wpRoot = Join-Path $livelyData "Library\wallpapers"
$wpDir = Join-Path $wpRoot "persona-monorail"
$rmExe = Join-Path $env:ProgramFiles "Rainmeter\Rainmeter.exe"
$rmIni = Join-Path $roaming "Rainmeter\Rainmeter.ini"
$stateFile = Join-Path $app "state.json"
New-Item -ItemType Directory -Force $app | Out-Null
$state = @{ wallpaper = $wpDir; startupShortcut = $false; icons = @{} }
if (Test-Path $stateFile) {
  $old = Get-Content $stateFile -Raw | ConvertFrom-Json
  $state.startupShortcut = [bool]$old.startupShortcut
  if ($old.icons) { $old.icons.PSObject.Properties | ForEach-Object { $state.icons[$_.Name] = $_.Value } }
}

function Get-File($url, $out, $referer) {
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    $cargs = @("-sSfL", "-A", $ua, "-o", $out, $url)
    if ($referer) { $cargs = @("-e", $referer) + $cargs }
    & $curl.Source @cargs
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $url" }
  } else {
    $h = @{}
    if ($referer) { $h["Referer"] = $referer }
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out -UserAgent $ua -Headers $h
  }
}

function Install-Package($id, $name, $override) {
  & winget list --id $id -e --accept-source-agreements *> $null
  if ($LASTEXITCODE -eq 0) { Info "$name is already installed."; return }
  Info "Installing $name..."
  if ($override) { & winget install --id $id -e --override $override --accept-package-agreements --accept-source-agreements }
  else { & winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements }
  if ($LASTEXITCODE -ne 0) { throw "Couldn't install $name (winget error $LASTEXITCODE)." }
}

Write-Host ""
Write-Host "  PERSONA DESKTOP  " -ForegroundColor White -BackgroundColor DarkRed
Write-Host "  Animated Persona 3 wallpaper, music player and a Persona 5 shortcut menu."

if (-not $SkipApps) {
  Step "Installing apps (Lively Wallpaper and Rainmeter)"
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is missing. Install 'App Installer' from the Microsoft Store, then run Install.bat again."
  }
  Install-Package "Microsoft.DotNet.DesktopRuntime.9" ".NET 9 Desktop Runtime"
  Install-Package "rocksdanister.LivelyWallpaper" "Lively Wallpaper"
  Install-Package "Rainmeter.Rainmeter" "Rainmeter" "/S /AUTOSTARTUP=1"
}

Step "Setting up the wallpaper"
if (-not $TestRoot -and -not (Test-Path $wpRoot)) {
  Info "Starting Lively for the first time..."
  Start-Process $livelyExe
  for ($i = 0; $i -lt 90 -and -not (Test-Path $wpRoot); $i++) { Start-Sleep 1 }
  if (-not (Test-Path $wpRoot)) { throw "Lively didn't finish its first start. Open Lively once, then run Install.bat again." }
}
New-Item -ItemType Directory -Force $wpDir, (Join-Path $wpDir "music") | Out-Null
Get-ChildItem (Join-Path $src "wallpaper") | Where-Object { $_.Name -ne "music" } | ForEach-Object { Copy-Item $_.FullName $wpDir -Recurse -Force }
Copy-Item (Join-Path $src "wallpaper\music\*") (Join-Path $wpDir "music") -Force

$still = Join-Path $wpDir "background.jpg"
if (-not (Test-Path $still)) {
  Info "Downloading the monorail art by @Jurawings1 (Wallhaven)..."
  Get-File $stillUrl $still $null
}
$video = Join-Path $wpDir "background.mp4"
if (-not (Test-Path $video) -or (Get-Item $video).Length -lt 1000000) {
  Info "Downloading the animated version from MoeWalls (about 65 MB)..."
  $page = Invoke-WebRequest -UseBasicParsing -Uri $monorailPage -UserAgent $ua
  if ($page.Content -notmatch 'id="moe-download"[^>]*data-url="([^"]+)"') { throw "Couldn't find the video link on MoeWalls." }
  Get-File ("https://go.moewalls.com/download.php?video=" + $Matches[1]) $video $monorailPage
}
$thumb = Join-Path $wpDir "thumbnail.jpg"
if (-not (Test-Path $thumb)) {
  $img = [System.Drawing.Image]::FromFile($still)
  $bmp = New-Object System.Drawing.Bitmap 640, 360
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = "HighQualityBicubic"
  $g.DrawImage($img, 0, 0, 640, 360)
  $bmp.Save($thumb, [System.Drawing.Imaging.ImageFormat]::Jpeg)
  $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $wpDir "Update playlist.ps1") | Select-Object -First 1 | ForEach-Object { Info $_ }

if (-not $TestRoot) {
  Info "Switching Lively to the Persona wallpaper..."
  Get-Process | Where-Object { $_.Path -like "*Lively Wallpaper*" } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
  $settings = Join-Path $livelyData "Settings.json"
  if (Test-Path $settings) {
    $j = Get-Content $settings -Raw | ConvertFrom-Json
    $j | Add-Member -NotePropertyName AudioOnlyOnDesktop -NotePropertyValue $false -Force
    [IO.File]::WriteAllText($settings, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
  }
  Start-Process $livelyExe
  Start-Sleep 8
  & $livelyExe setwp --file (Join-Path $wpDir "index.html")
}

Step "Setting up the Persona 5 menu and system bars"
$menuApp = Join-Path $app "menu"
New-Item -ItemType Directory -Force $menuApp, (Join-Path $menuApp "Menu Shortcuts") | Out-Null
Copy-Item (Join-Path $src "menu\Build-Menu.ps1"), (Join-Path $src "menu\Update menu.bat") $menuApp -Force

$pack = Get-ChildItem $downloads -Filter "persona_5_desktop_icon_pack*.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$iconDir = Join-Path $menuApp "icons"
if ($pack) {
  Info "Found FrozenVayne's Persona 5 icon pack in Downloads, using it."
  $tmp = Join-Path $env:TEMP ("p5icons_" + [guid]::NewGuid().ToString("N"))
  Expand-Archive $pack.FullName $tmp -Force
  $root = Get-ChildItem $tmp -Recurse -Filter "recycle_empty.ico" | Select-Object -First 1
  if ($root) {
    New-Item -ItemType Directory -Force $iconDir | Out-Null
    Copy-Item (Join-Path $root.DirectoryName "*") $iconDir -Recurse -Force
  }
  Remove-Item $tmp -Recurse -Force
} elseif (-not (Test-Path (Join-Path $iconDir "recycle_empty.ico"))) {
  Info "Optional: FrozenVayne's Persona 5 icon pack isn't in your Downloads, so the menu uses normal app icons."
  Info "Get it from https://www.deviantart.com/frozenvayne/art/Persona-5-Desktop-Icon-Pack-Version-1-0-747871613"
  Info "then run Install.bat again."
}

if (-not $TestRoot -and (Test-Path (Join-Path $iconDir "recycle_empty.ico"))) {
  $clsid = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID"
  $targets = @{
    "{645FF040-5081-101B-9F08-00AA002F954E}" = @{ "(default)" = "recycle_empty.ico"; "empty" = "recycle_empty.ico"; "full" = "recycle_full.ico" }
    "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" = @{ "(default)" = "desktop_icon.ico" }
  }
  foreach ($c in $targets.Keys) {
    $key = "$clsid\$c\DefaultIcon"
    if (-not $state.icons.ContainsKey($c)) {
      $bk = @{}
      if (Test-Path $key) { $p = Get-ItemProperty $key; foreach ($n in $targets[$c].Keys) { $bk[$n] = $p.$n } } else { $bk["__none"] = $true }
      $state.icons[$c] = $bk
    }
    New-Item -Force $key -ErrorAction SilentlyContinue | Out-Null
    foreach ($n in $targets[$c].Keys) { Set-ItemProperty $key -Name $n -Value ((Join-Path $iconDir $targets[$c][$n]) + ",0") }
  }
  Info "Recycle Bin and This PC now use the Persona 5 icons."
}

$rmFresh = -not (Test-Path $rmIni)
$skinRoot = Join-Path $docs "Rainmeter\Skins"
if (-not $rmFresh) {
  $sp = Get-Content $rmIni | Where-Object { $_ -like "SkinPath=*" } | Select-Object -First 1
  if ($sp) { $skinRoot = $sp.Substring(9).TrimEnd("\") }
}
New-Item -ItemType Directory -Force $skinRoot | Out-Null
Copy-Item (Join-Path $src "menu\PersonaMenu") $skinRoot -Recurse -Force
Copy-Item (Join-Path $src "skins\Persona 5 System") $skinRoot -Recurse -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $menuApp "Build-Menu.ps1") -TargetSkins $skinRoot | ForEach-Object { Info $_ }

$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$sysY = [Math]::Max(0, $area.Bottom - 300)
if ($rmFresh) {
  New-Item -ItemType Directory -Force (Split-Path $rmIni) | Out-Null
  $ini = "[Rainmeter]`r`nSkinPath=$skinRoot\`r`n`r`n[PersonaMenu]`r`nActive=1`r`nWindowX=110`r`nWindowY=36`r`nAlwaysOnTop=-2`r`nDraggable=1`r`nSnapEdges=1`r`nKeepOnScreen=1`r`n`r`n[Persona 5 System]`r`nActive=1`r`nWindowX=30`r`nWindowY=$sysY`r`nAlwaysOnTop=-2`r`nDraggable=1`r`nSnapEdges=1`r`nKeepOnScreen=1`r`n"
  [IO.File]::WriteAllText($rmIni, $ini, [Text.Encoding]::Unicode)
}
if (-not $TestRoot -and (Test-Path $rmExe)) {
  if (-not (Get-Process Rainmeter -ErrorAction SilentlyContinue)) { Start-Process $rmExe; Start-Sleep 5 }
  if (-not $rmFresh) {
    & $rmExe "!RefreshApp"; Start-Sleep 4
    & $rmExe "!ActivateConfig" "PersonaMenu" "Menu.ini"
    & $rmExe "!ActivateConfig" "Persona 5 System" "System.ini"
    Start-Sleep 2
    & $rmExe "!ZPos" "-2" "PersonaMenu"
    & $rmExe "!ZPos" "-2" "Persona 5 System"
  }
}

$ws = New-Object -ComObject WScript.Shell
Step "Adding Start menu shortcuts"
$sm = Join-Path $startMenu "Persona Desktop"
New-Item -ItemType Directory -Force $sm | Out-Null
Copy-Item (Join-Path $src "setup\uninstall.ps1") $app -Force
Copy-Item (Join-Path $src "Uninstall.bat") $app -Force
$links = @(
  @("Music folder", (Join-Path $env:WINDIR "explorer.exe"), ('"' + (Join-Path $wpDir "music") + '"')),
  @("Update playlist", (Join-Path $wpDir "Update playlist.bat"), ""),
  @("Update menu", (Join-Path $menuApp "Update menu.bat"), ""),
  @("Menu shortcuts folder", (Join-Path $env:WINDIR "explorer.exe"), ('"' + (Join-Path $menuApp "Menu Shortcuts") + '"')),
  @("Uninstall Persona Desktop", (Join-Path $app "Uninstall.bat"), "")
)
foreach ($l in $links) {
  $s = $ws.CreateShortcut((Join-Path $sm ($l[0] + ".lnk")))
  $s.TargetPath = $l[1]; $s.Arguments = $l[2]; $s.Save()
}

$state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8

Write-Host ""
Write-Host "  DONE  " -ForegroundColor White -BackgroundColor DarkRed
Info "Put your music in: $(Join-Path $wpDir 'music')"
Info "Then open Start > Persona Desktop > Update playlist."
Info "Click the red MENU tab on your desktop to open your apps."
Info "Wallpaper options (clock, Dark Hour, animation) are in Lively > Customize."
