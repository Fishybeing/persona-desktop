param([string]$TargetSkins)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationCore, WindowsBase, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class IconX {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, uint[] ids, uint n, uint flags);
  [DllImport("user32.dll")]
  public static extern bool DestroyIcon(IntPtr h);
}
"@

$skinRoot = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Rainmeter\Skins"
$rmIni = Join-Path $env:APPDATA "Rainmeter\Rainmeter.ini"
if (Test-Path $rmIni) {
  $sp = Get-Content $rmIni | Where-Object { $_ -like "SkinPath=*" } | Select-Object -First 1
  if ($sp) { $skinRoot = $sp.Substring(9).TrimEnd("\") }
}
if ($TargetSkins) { $skinRoot = $TargetSkins }
$skin = Join-Path $skinRoot "PersonaMenu"
$iconDir = Join-Path $skin "@Resources\Icons"
$extra = Join-Path $PSScriptRoot "Menu Shortcuts"
New-Item -ItemType Directory -Force $iconDir, $extra | Out-Null
Get-ChildItem $iconDir -Filter *.png | Remove-Item -Force

$sources = @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("CommonDesktopDirectory"), $extra)
$launchers = "steam", "riot client", "ubisoft connect", "modrinth app", "nvidia geforce now", "epic games launcher", "battle.net", "ea app", "roblox player", "rpcs3", "valorant", "minecraft"
$ws = New-Object -ComObject WScript.Shell

function Save-Png($bmpSource, $path) {
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmpSource))
  $fs = [IO.File]::Create($path)
  try { $enc.Save($fs) } finally { $fs.Close() }
}

function Export-Icon($file, $index, $out) {
  if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $false }
  if ($file.ToLower().EndsWith(".ico")) {
    try {
      $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create((New-Object Uri $file), "PreservePixelFormat", "OnLoad")
      $frame = $dec.Frames | Where-Object { $_.PixelWidth -le 256 } | Sort-Object PixelWidth -Descending | Select-Object -First 1
      if ($frame) { Save-Png $frame $out; return $true }
    } catch {}
  }
  $h = New-Object IntPtr[] 1; $ids = New-Object uint32[] 1
  $got = [IconX]::PrivateExtractIcons($file, [int]$index, 64, 64, $h, $ids, 1, 0)
  if ($got -ge 1 -and $h[0] -ne [IntPtr]::Zero) {
    try {
      $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($h[0], [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
      Save-Png $src $out
      return $true
    } finally { [void][IconX]::DestroyIcon($h[0]) }
  }
  return $false
}

function Export-ShortcutIcon($path, $out) {
  if ($path -like "*.lnk") {
    $s = $ws.CreateShortcut($path)
    $loc = $s.IconLocation
    if ($loc -and $loc -notmatch '^,') {
      $f = [Environment]::ExpandEnvironmentVariables(($loc -replace ',-?\d+$', ''))
      $i = 0; if ($loc -match ',(-?\d+)$') { $i = [int]$Matches[1] }
      if (Export-Icon $f $i $out) { return $true }
    }
    return (Export-Icon $s.TargetPath 0 $out)
  }
  if ($path -like "*.url") {
    $txt = Get-Content -LiteralPath $path
    $f = ($txt | Where-Object { $_ -like "IconFile=*" } | Select-Object -First 1) -replace '^IconFile=', ''
    if ($f -and (Export-Icon $f 0 $out)) { return $true }
  }
  return (Export-Icon $path 0 $out)
}

$items = @()
$seen = @{}
$packDir = Join-Path $PSScriptRoot "icons"
$pack = @(
  @{ N = "Steam"; I = "steam.ico"; G = 1; S = '^Steam$' },
  @{ N = "Battle.net"; I = "battlenet_icon.ico"; G = 1; S = '^Battle\.net$' },
  @{ N = "EA app"; I = "origin_icon.ico"; G = 1; S = '^(Origin|EA|EA app)$' },
  @{ N = "Ubisoft Connect"; I = "uplay_icon.ico"; G = 1; S = '^(Ubisoft Connect|Uplay)$' },
  @{ N = "PS Remote Play"; I = "remoteplay_icon.ico"; G = 1; S = '^PS Remote Play$' },
  @{ N = "Counter-Strike 2"; I = "Games\csgo_icon.ico"; G = 1; A = 730; S = '^Counter-Strike' },
  @{ N = "Fortnite"; I = "Games\fortnite_icon.ico"; G = 1; S = '^Fortnite$'; E = "Fortnite" },
  @{ N = "Hearthstone"; I = "Games\hearthstone_icon.ico"; G = 1; S = '^Hearthstone$' },
  @{ N = "League of Legends"; I = "Games\lol_icon.ico"; G = 1; S = '^League of Legends$' },
  @{ N = "NieR:Automata"; I = "Games\nier_icon.ico"; G = 1; A = 524220; S = '^NieR' },
  @{ N = "osu!"; I = "Games\osu_icon.ico"; G = 1; S = '^osu!' },
  @{ N = "Overwatch"; I = "Games\overwatch_icon.ico"; G = 1; A = 2357570; S = '^Overwatch' },
  @{ N = "PUBG: Battlegrounds"; I = "Games\pubg_icon.ico"; G = 1; A = 578080; S = '^PUBG' },
  @{ N = "Rainbow Six Siege"; I = "Games\r6siege_icon.ico"; G = 1; A = 359550; S = "^Tom Clancy's Rainbow Six" },
  @{ N = "Rocket League"; I = "Games\rocket_league_icon.ico"; G = 1; A = 252950; S = '^Rocket League' },
  @{ N = "Team Fortress 2"; I = "Games\tf2_icon.ico"; G = 1; A = 440; S = '^Team Fortress 2$' },
  @{ N = "Warframe"; I = "Games\warframe_icon_KHv_icon.ico"; G = 1; A = 230410; S = '^Warframe$' },
  @{ N = "World of Warcraft"; I = "Games\wow_icon.ico"; G = 1; S = '^World of Warcraft' },
  @{ N = "Google Chrome"; I = "chrome_icon.ico"; G = 0; S = '^Google Chrome$' },
  @{ N = "Microsoft Edge"; I = "edge.ico"; G = 0; S = '^Microsoft Edge$' },
  @{ N = "Firefox"; I = "firefox_icon.ico"; G = 0; S = '^(Mozilla )?Firefox$' },
  @{ N = "Discord"; I = "discord_icon.ico"; G = 0; S = '^Discord$' },
  @{ N = "Spotify"; I = "spotify_icon.ico"; G = 0; S = '^Spotify$' },
  @{ N = "VLC media player"; I = "music_icon.ico"; G = 0; S = '^VLC media player$' },
  @{ N = "Notepad++"; I = "notepad_icon.ico"; G = 0; S = '^Notepad\+\+$'; F = "$env:WINDIR\notepad.exe"; FN = "Notepad" },
  @{ N = "Photoshop"; I = "photoshop_icon.ico"; G = 0; S = '^(Adobe )?Photoshop' },
  @{ N = "Illustrator"; I = "illustrator_icon.ico"; G = 0; S = '^(Adobe )?Illustrator' },
  @{ N = "Word"; I = "m_word_icon.ico"; G = 0; S = '^(Microsoft )?Word( 20\d\d)?$' },
  @{ N = "Excel"; I = "m_excel_icon.ico"; G = 0; S = '^(Microsoft )?Excel( 20\d\d)?$' },
  @{ N = "PowerPoint"; I = "m_powerpoint_icon.ico"; G = 0; S = '^(Microsoft )?PowerPoint( 20\d\d)?$' },
  @{ N = "File Explorer"; I = "file_explorer.ico"; G = 0; F = "$env:WINDIR\explorer.exe" },
  @{ N = "Command Prompt"; I = "command_prompt_icon.ico"; G = 0; F = "$env:WINDIR\System32\cmd.exe" }
)

$startMenu = @()
foreach ($d in [Environment]::GetFolderPath("Programs"), [Environment]::GetFolderPath("CommonPrograms")) {
  if (Test-Path $d) { $startMenu += Get-ChildItem $d -Recurse -File -Include *.lnk, *.url -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -notmatch '^(Uninstall|Remove)' } }
}
$steamApps = @{}
$steamRoot = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
if ($steamRoot) {
  $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
  $libs = @($steamRoot)
  if (Test-Path $vdf) { $libs += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } }
  foreach ($lib in $libs | Select-Object -Unique) {
    Get-ChildItem (Join-Path $lib "steamapps") -Filter "appmanifest_*.acf" -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Name -match 'appmanifest_(\d+)\.acf') { $steamApps[$Matches[1]] = $true } }
  }
}
$epic = @{}
Get-ChildItem "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests" -Filter *.item -ErrorAction SilentlyContinue | ForEach-Object {
  try { $m = Get-Content $_.FullName -Raw | ConvertFrom-Json; $epic[$m.DisplayName] = $m.AppName } catch {}
}

$packRx = @()
foreach ($e in $pack) {
  $target = $null; $name = $e.N
  if ($e.A -and $steamApps.ContainsKey([string]$e.A)) { $target = "steam://rungameid/$($e.A)" }
  if (-not $target -and $e.E -and $epic.ContainsKey($e.E)) { $target = "com.epicgames.launcher://apps/$($epic[$e.E])?action=launch&silent=true" }
  if (-not $target -and $e.S) {
    $hit = $startMenu | Where-Object { $_.BaseName -match $e.S } | Select-Object -First 1
    if ($hit) { $target = $hit.FullName; $name = $hit.BaseName }
  }
  if (-not $target -and $e.F -and (Test-Path $e.F)) { $target = $e.F; if ($e.FN) { $name = $e.FN } }
  if (-not $target) { continue }
  if ($e.S) { $packRx += $e.S }
  $packRx += '^' + [regex]::Escape($name) + '$'
  $seen[$name.ToLower()] = $true
  $id = "i" + $items.Count
  $png = Join-Path $iconDir "$id.png"
  $has = Export-Icon (Join-Path $packDir $e.I) 0 $png
  if (-not $has -and $target -notmatch '^[a-z.]+://') { $has = Export-ShortcutIcon $target $png }
  if (-not $has -and $target -like "steam://*" -and $steamRoot) { $has = Export-Icon (Join-Path $steamRoot "steam.exe") 0 $png }
  $items += [pscustomobject]@{ Id = $id; Name = $name; Path = $target; Game = [bool]$e.G; Icon = $has }
}
foreach ($dir in $sources) {
  if (-not (Test-Path $dir)) { continue }
  foreach ($f in Get-ChildItem $dir -File -Force | Where-Object { $_.Extension -in ".lnk", ".url" }) {
    $name = $f.BaseName
    if ($seen.ContainsKey($name.ToLower())) { continue }
    if ($packRx | Where-Object { $name -match $_ }) { continue }
    $seen[$name.ToLower()] = $true
    $iconFile = $null; $iconIndex = 0; $game = $false
    if ($f.Extension -eq ".lnk") {
      $s = $ws.CreateShortcut($f.FullName)
      $loc = $s.IconLocation
      if ($loc -and $loc -notmatch '^,') {
        $iconFile = [Environment]::ExpandEnvironmentVariables(($loc -replace ',-?\d+$', ''))
        if ($loc -match ',(-?\d+)$') { $iconIndex = [int]$Matches[1] }
      }
      if (-not $iconFile -or -not (Test-Path -LiteralPath $iconFile)) { $iconFile = $s.TargetPath; $iconIndex = 0 }
    } else {
      $txt = Get-Content -LiteralPath $f.FullName
      $url = ($txt | Where-Object { $_ -like "URL=*" } | Select-Object -First 1) -replace '^URL=', ''
      $iconFile = ($txt | Where-Object { $_ -like "IconFile=*" } | Select-Object -First 1) -replace '^IconFile=', ''
      $ii = ($txt | Where-Object { $_ -like "IconIndex=*" } | Select-Object -First 1) -replace '^IconIndex=', ''
      if ($ii) { $iconIndex = [int]$ii }
      if ($url -like "steam://*" -or $url -like "com.epicgames*") { $game = $true }
    }
    if ($launchers -contains $name.ToLower()) { $game = $true }
    $id = "i" + $items.Count
    $png = Join-Path $iconDir "$id.png"
    $has = Export-Icon $iconFile $iconIndex $png
    if (-not $has) { $has = Export-Icon $f.FullName 0 $png }
    $items += [pscustomobject]@{ Id = $id; Name = $name; Path = $f.FullName; Game = $game; Icon = $has }
  }
}

$games = @($items | Where-Object Game | Sort-Object Name)
$apps = @($items | Where-Object { -not $_.Game } | Sort-Object Name)
if (-not $games.Count -and $apps.Count -gt 1) { $half = [Math]::Ceiling($apps.Count / 2); $games = $apps[0..($half - 1)]; $apps = $apps[$half..($apps.Count - 1)]; $leftTitle = "SHORTCUTS"; $rightTitle = "" }
else { $leftTitle = "GAMES"; $rightTitle = "APPS" }

$colW = 300; $rowH = 36; $sk = 10; $top = 64; $headH = 46; $pad = 18
$rows = [Math]::Max($games.Count, $apps.Count)
$panelW = 2 * $colW + 2 * $pad + 10
$panelH = $headH + $rows * $rowH + 58

$sb = New-Object Text.StringBuilder
function L($s) { [void]$sb.AppendLine($s) }

L "[Rainmeter]"
L "Update=-1"
L "AccurateText=1"
L "DynamicWindowSize=1"
L "DefaultUpdateDivider=-1"
L "OnRefreshAction=[!HideMeterGroup Bars]"
L ""
L "[Metadata]"
L "Name=Persona Menu"
L "Information=Desktop shortcut menu in a Persona 5 style. Fonts and sounds from TingTyphoon's P5 Shibuya Station pack. Icons by FrozenVayne where available. Click UPDATE LIST after adding or removing apps."
L ""
L "[Variables]"
L "Red=229,25,28,255"
L "Ink=245,245,245,255"
L "Dim=170,170,170,255"
L "Black=10,10,10,215"
L "Tick=[Play `"#@#Sounds\00121.wav`"]"
L "Confirm=[Play `"#@#Sounds\00007.wav`"]"
L "MenuOpen=2"
L ""
L "[FontP5]"
L "Measure=String"
L "String="
L "LocalFont=#@#Fonts\PersonifiedUXRegular.ttf"
L "LocalFont2=#@#Fonts\Polt-ExtraBold.otf"
L "LocalFont3=#@#Fonts\RobotoCondensed-Bold.ttf"
L ""
L "[MeasureMenu]"
L "Measure=Calc"
L "Formula=#MenuOpen#"
L "DynamicVariables=1"
L "IfCondition=MeasureMenu = 1"
L "IfTrueAction=[!ShowMeterGroup Menu][!Redraw][Play `"#@#Sounds\open.wav`"]"
L "IfCondition2=MeasureMenu = 0"
L "IfTrueAction2=[!HideMeterGroup Menu][!HideMeterGroup Bars][!Redraw][Play `"#@#Sounds\close.wav`"]"
L ""
L "[TabShadow]"
L "Meter=Shape"
L "Shape=Path P | Fill Color 0,0,0,200 | StrokeWidth 0"
L "P=6,6 | LineTo 176,6 | LineTo 164,50 | LineTo -6,50 | ClosePath 1"
L "X=0"
L "Y=0"
L ""
L "[Tab]"
L "Meter=Shape"
L "Shape=Path P | Fill Color #Red# | StrokeWidth 0"
L "P=0,0 | LineTo 170,0 | LineTo 158,44 | LineTo -12,44 | ClosePath 1"
L "X=12"
L "Y=0"
L "MouseOverAction=[!SetOption Tab Shape `"Path P | Fill Color 255,255,255,255 | StrokeWidth 0`"][!SetOption TabText FontColor 10,10,10,255][!UpdateMeter Tab][!UpdateMeter TabText][!Redraw]"
L "MouseLeaveAction=[!SetOption Tab Shape `"Path P | Fill Color #Red# | StrokeWidth 0`"][!SetOption TabText FontColor 255,255,255,255][!UpdateMeter Tab][!UpdateMeter TabText][!Redraw]"
L "DynamicVariables=1"
L "LeftMouseUpAction=[!SetVariable MenuOpen `"(#MenuOpen#=0 ? 1 : 0)`"][!UpdateMeasure MeasureMenu][!UpdateMeter Tab]"
L ""
L "[TabText]"
L "Meter=String"
L "Text=MENU"
L "FontFace=Personified UX"
L "FontSize=24"
L "FontColor=255,255,255,255"
L "StringEffect=Shadow"
L "FontEffectColor=0,0,0,255"
L "AntiAlias=1"
L "X=40"
L "Y=4"
L ""
L "[Panel]"
L "Meter=Shape"
L "Group=Menu"
L ("Shape=Path P | Fill Color #Black# | StrokeWidth 3 | StrokeColor #Red#")
L ("P={0},0 | LineTo {1},0 | LineTo {2},{3} | LineTo 0,{3} | ClosePath 1" -f 24, ($panelW + 24), $panelW, $panelH)
L "X=0"
L "Y=$top"
L ""

$cols = @(@{ Title = $leftTitle; List = $games; X = $pad + 14 }, @{ Title = $rightTitle; List = $apps; X = $pad + 14 + $colW + 10 })
$c = 0
foreach ($col in $cols) {
  $c++
  $cx = $col.X
  if ($col.Title) {
    L "[Head$c]"
    L "Meter=String"
    L "Group=Menu"
    L "Text=$($col.Title)"
    L "FontFace=Personified UX"
    L "FontSize=22"
    L "FontColor=255,255,255,255"
    L "AntiAlias=1"
    L "X=$cx"
    L ("Y={0}" -f ($top + 8))
    L ""
    L "[HeadLine$c]"
    L "Meter=Shape"
    L "Group=Menu"
    L ("Shape=Path P | Fill Color #Red# | StrokeWidth 0")
    L ("P=8,0 | LineTo {0},0 | LineTo {1},5 | LineTo 0,5 | ClosePath 1" -f ($colW - 30), ($colW - 38))
    L "X=$cx"
    L ("Y={0}" -f ($top + $headH - 4))
    L ""
  }
  $r = 0
  foreach ($it in $col.List) {
    $y = $top + $headH + 6 + $r * $rowH
    $id = $it.Id
    $path = $it.Path
    $label = ($it.Name -replace '#', '##')
    L "[Bar_$id]"
    L "Meter=Shape"
    L "Group=Bars"
    L "Hidden=1"
    L "Shape=Path P | Fill Color #Red# | StrokeWidth 0"
    L ("P={0},0 | LineTo {1},0 | LineTo {2},{3} | LineTo 0,{3} | ClosePath 1" -f $sk, ($colW - 12), ($colW - 12 - $sk), ($rowH - 4))
    L ("X={0}" -f ($cx - 8))
    L ("Y={0}" -f ($y + 2))
    L ""
    L "[Text_$id]"
    L "Meter=String"
    L "Group=Menu"
    L "Text=$label"
    L "StringCase=Upper"
    L "FontFace=Roboto Condensed"
    L "FontSize=14"
    L "FontColor=#Ink#"
    L "ClipString=1"
    L "AntiAlias=1"
    L "SolidColor=0,0,0,1"
    L ("W={0}" -f ($colW - 20))
    L ("H={0}" -f ($rowH - 4))
    L "Padding=40,7,0,0"
    L "X=$cx"
    L ("Y={0}" -f ($y + 2))
    L ("MouseOverAction=[!ShowMeter Bar_$id][!SetOption Text_$id FontColor 255,255,255,255][!SetOption Text_$id Padding `"48,7,0,0`"][!UpdateMeter Text_$id][!Redraw]#Tick#")
    L ("MouseLeaveAction=[!HideMeter Bar_$id][!SetOption Text_$id FontColor #Ink#][!SetOption Text_$id Padding `"40,7,0,0`"][!UpdateMeter Text_$id][!Redraw]")
    L ("LeftMouseUpAction=#Confirm#[`"$path`"]")
    L ""
    if ($it.Icon) {
      L "[Icon_$id]"
      L "Meter=Image"
      L "Group=Menu"
      L "ImageName=#@#Icons\$id.png"
      L "W=26"
      L "H=26"
      L "PreserveAspectRatio=1"
      L "AntiAlias=1"
      L ("X={0}" -f ($cx + 4))
      L ("Y={0}" -f ($y + 5))
      L ""
    }
    $r++
  }
}

L "[Update]"
L "Meter=String"
L "Group=Menu"
L "Text=UPDATE LIST"
L "FontFace=Roboto Condensed"
L "FontSize=10"
L "FontColor=#Dim#"
L "AntiAlias=1"
L "SolidColor=0,0,0,1"
L "Padding=4,2,4,2"
L ("X={0}" -f ($panelW - 110))
L ("Y={0}" -f ($top + $panelH - 30))
L "MouseOverAction=[!SetOption Update FontColor #Red#][!UpdateMeter Update][!Redraw]"
L "MouseLeaveAction=[!SetOption Update FontColor #Dim#][!UpdateMeter Update][!Redraw]"
L ("LeftMouseUpAction=[`"{0}`"]" -f (Join-Path $PSScriptRoot "Update menu.bat"))
L ""

$ini = $sb.ToString()
[IO.File]::WriteAllText((Join-Path $skin "Menu.ini"), $ini, [Text.Encoding]::Unicode)
Write-Host ("Menu built: {0} games, {1} apps." -f $games.Count, $apps.Count)
