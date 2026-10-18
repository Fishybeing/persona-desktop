param([string]$WallpaperDir)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$created = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\PersonaMusicApp", [ref]$created)
if (-not $created) {
  try { if (-not $mutex.WaitOne(0)) { exit } } catch [System.Threading.AbandonedMutexException] { }
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PmNative {
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
  [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string id);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
  [DllImport("uxtheme.dll", EntryPoint = "#135")] public static extern int SetPreferredAppMode(int mode);
}
"@
try { [void][PmNative]::SetPreferredAppMode(2) } catch { }

$appData = Join-Path $env:LOCALAPPDATA "PersonaMusic"
New-Item -ItemType Directory -Force $appData | Out-Null
$settingsFile = Join-Path $appData "settings.json"
$livelyData = Join-Path $env:LOCALAPPDATA "Lively Wallpaper"
function Find-LivelyExe {
  $running = Get-Process Lively, Lively.Player.WebView2 -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($running) {
    $dir = Split-Path $running.Path
    for ($i = 0; $i -lt 4 -and $dir; $i++) {
      $c = Join-Path $dir "Lively.exe"
      if ((Test-Path $c) -and $c -notlike "*\WindowsApps\*") { return $c }
      $dir = Split-Path $dir
    }
  }
  $paths = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Lively Wallpaper\Lively.exe"),
    (Join-Path $env:ProgramFiles "Lively Wallpaper\Lively.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Lively Wallpaper\Lively.exe")
  )
  foreach ($root in "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall") {
    Get-ItemProperty "$root\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Lively Wallpaper*" } | ForEach-Object {
      if ($_.InstallLocation) { $paths += Join-Path $_.InstallLocation "Lively.exe" }
      if ($_.DisplayIcon) { $paths += Join-Path (Split-Path ($_.DisplayIcon -replace '"', '' -replace ',\d+$', '')) "Lively.exe" }
    }
  }
  $paths += Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps") -Recurse -Filter "Lively*.exe" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*Player*" } | ForEach-Object { $_.FullName }
  foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
  return $null
}
$exts = ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac", ".wav", ".webm"
$mainFolders = "Other Music", "Persona 3 Reload"
$removedDir = Join-Path ([Environment]::GetFolderPath("MyMusic")) "Persona Desktop - removed songs"

function Find-WallpaperDir {
  $state = Join-Path $env:LOCALAPPDATA "PersonaDesktop\state.json"
  if (Test-Path $state) {
    try { $d = (Get-Content $state -Raw | ConvertFrom-Json).wallpaper; if ($d -and (Test-Path (Join-Path $d "hud.js"))) { return $d } } catch { }
  }
  $layout = Join-Path $livelyData "WallpaperLayout.json"
  if (Test-Path $layout) {
    try {
      $d = @((Get-Content $layout -Raw | ConvertFrom-Json) | ForEach-Object { $_.LivelyInfoPath } | Where-Object { $_ -and (Test-Path (Join-Path $_ "hud.js")) })[0]
      if ($d) { return $d }
    } catch { }
  }
  $found = Get-ChildItem (Join-Path $livelyData "Library\wallpapers") -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "hud.js") } | Select-Object -First 1
  if ($found) { return $found.FullName }
  return $null
}

$wpDir = if ($WallpaperDir) { $WallpaperDir } else { Find-WallpaperDir }
if (-not $wpDir) {
  [System.Windows.Forms.MessageBox]::Show("Persona Desktop isn't installed, so there's no music player to add songs to.`n`nInstall Persona Desktop first, then open Persona Music again.", "Persona Music", "OK", "Warning") | Out-Null
  exit
}
$music = Join-Path $wpDir "music"
$updateScript = Join-Path $wpDir "Update playlist.ps1"
New-Item -ItemType Directory -Force $music | Out-Null

$settings = @{ playlist = "" }
if (Test-Path $settingsFile) { try { $s = Get-Content $settingsFile -Raw | ConvertFrom-Json; if ($s.playlist) { $settings.playlist = [string]$s.playlist } } catch { } }
function Save-Settings { $settings | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8 }

function C($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cBg = C "#0C0809"; $cPanel = C "#170A0D"; $cField = C "#211014"; $cRed = C "#D8203A"; $cRedHi = C "#F0334D"
$cDeep = C "#7A0F1E"; $cWhite = [System.Drawing.Color]::White; $cGrey = C "#A79A9D"; $cRow = C "#140A0C"; $cRowAlt = C "#1B0D10"

$p5Family = $null
$probe = New-Object System.Drawing.Font("Personified UX", 10)
if ($probe.Name -eq "Personified UX") { $p5Family = $probe.FontFamily }
else {
  $cands = @()
  $rmIni = Join-Path $env:APPDATA "Rainmeter\Rainmeter.ini"
  if (Test-Path $rmIni) {
    $sp = Get-Content $rmIni | Where-Object { $_ -like "SkinPath=*" } | Select-Object -First 1
    if ($sp) { $cands += Join-Path $sp.Substring(9) "PersonaMenu\@Resources\Fonts\PersonifiedUXRegular.ttf" }
  }
  $cands += Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Rainmeter\Skins\PersonaMenu\@Resources\Fonts\PersonifiedUXRegular.ttf"
  $cands += Join-Path $PSScriptRoot "PersonifiedUXRegular.ttf"
  $fontFile = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($fontFile) {
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($fontFile)
    $p5Family = $pfc.Families[0]
  }
}
function P5Font([float]$size) {
  if ($p5Family) { New-Object System.Drawing.Font($p5Family, $size) } else { New-Object System.Drawing.Font("Segoe UI Black", ($size * 0.8)) }
}
$fBody = New-Object System.Drawing.Font("Segoe UI", 10)
$fSmall = New-Object System.Drawing.Font("Segoe UI", 9)
$fTitle = P5Font 30
$fHead = P5Font 15
$fButton = P5Font 13
$fDrop = P5Font 18

$iconFile = @(
  (Join-Path $PSScriptRoot "music_icon.ico"),
  (Join-Path $env:LOCALAPPDATA "PersonaDesktop\menu\icons\music_icon.ico"),
  (Join-Path $env:LOCALAPPDATA "PersonaMenu\icons\music_icon.ico")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$form = New-Object System.Windows.Forms.Form
$form.Text = "Persona Music"
$form.ClientSize = New-Object System.Drawing.Size(900, 630)
$form.MinimumSize = New-Object System.Drawing.Size(916, 669)
$form.StartPosition = "CenterScreen"
$form.BackColor = $cBg
$form.ForeColor = $cWhite
$form.Font = $fBody
if ($iconFile) { $form.Icon = New-Object System.Drawing.Icon($iconFile) }
$form.Add_HandleCreated({ $one = 1; [void][PmNative]::DwmSetWindowAttribute($form.Handle, 20, [ref]$one, 4) })

function New-Label($text, $font, $color, $x, $y, $w, $h) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.Font = $font; $l.ForeColor = $color; $l.BackColor = [System.Drawing.Color]::Transparent
  $l.UseCompatibleTextRendering = $true
  $l.SetBounds($x, $y, $w, $h)
  $l
}
function New-Button($text, $x, $y, $w, $h, [switch]$Primary, $Font = $fButton) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text; $b.Font = $Font; $b.ForeColor = $cWhite
  $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
  $b.BackColor = if ($Primary) { $cRed } else { $cDeep }
  $b.FlatAppearance.MouseOverBackColor = if ($Primary) { $cRedHi } else { $cRed }
  $b.FlatAppearance.MouseDownBackColor = $cDeep
  $b.UseCompatibleTextRendering = $true
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.SetBounds($x, $y, $w, $h)
  $b
}

$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 900, 80)
$header.Anchor = "Top,Left,Right"
$header.BackColor = $cBg
$script:headerInfo = ""
$header.Add_Paint({
  param($s, $e)
  $g = $e.Graphics
  $g.SmoothingMode = "AntiAlias"
  $pts = [System.Drawing.Point[]]@((New-Object System.Drawing.Point(14, 14)), (New-Object System.Drawing.Point(372, 8)), (New-Object System.Drawing.Point(356, 70)), (New-Object System.Drawing.Point(4, 72)))
  $g.FillPolygon((New-Object System.Drawing.SolidBrush($cRed)), $pts)
  $g.DrawString("PERSONA MUSIC", $fTitle, [System.Drawing.Brushes]::White, 22, 16)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = "Far"
  $g.DrawString($script:headerInfo, $fSmall, (New-Object System.Drawing.SolidBrush($cGrey)), (New-Object System.Drawing.RectangleF(380, 30, ($header.Width - 400), 24)), $sf)
})
$form.Controls.Add($header)

$form.Controls.Add((New-Label "PUT NEW SONGS IN" $fHead $cRed 20 96 300 26))
$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = "DropDownList"
$combo.FlatStyle = "Flat"
$combo.BackColor = $cField
$combo.ForeColor = $cWhite
$combo.Font = $fBody
$combo.SetBounds(20, 124, 262, 28)
$form.Controls.Add($combo)
$btnNew = New-Button "+ NEW PLAYLIST" 290 122 140 30 -Font (P5Font 10.5)
$form.Controls.Add($btnNew)

$drop = New-Object System.Windows.Forms.Panel
$drop.SetBounds(20, 168, 410, 170)
$drop.BackColor = $cPanel
$drop.AllowDrop = $true
$drop.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:dropHot = $false
$drop.Add_Paint({
  param($s, $e)
  $g = $e.Graphics
  $g.SmoothingMode = "AntiAlias"
  $pen = New-Object System.Drawing.Pen($(if ($script:dropHot) { $cRedHi } else { $cRed }), 2)
  $pen.DashStyle = "Dash"
  $g.DrawRectangle($pen, 4, 4, $drop.Width - 9, $drop.Height - 9)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = "Center"; $sf.LineAlignment = "Center"
  $g.DrawString("DROP SONGS OR FOLDERS HERE", $fDrop, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 40, $drop.Width, 50)), $sf)
  $g.DrawString("or click to pick files  (mp3, m4a, ogg, opus, flac, wav, webm)", $fSmall, (New-Object System.Drawing.SolidBrush($cGrey)), (New-Object System.Drawing.RectangleF(0, 92, $drop.Width, 30)), $sf)
})
$form.Controls.Add($drop)

$form.Controls.Add((New-Label "OR PASTE A YOUTUBE LINK" $fHead $cRed 20 356 400 26))
$url = New-Object System.Windows.Forms.TextBox
$url.BackColor = $cField
$url.ForeColor = $cWhite
$url.BorderStyle = "FixedSingle"
$url.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$url.SetBounds(20, 386, 410, 28)
$form.Controls.Add($url)
$whole = New-Object System.Windows.Forms.CheckBox
$whole.Text = "Get the whole playlist or album"
$whole.ForeColor = $cWhite
$whole.FlatStyle = "Flat"
$whole.Font = $fSmall
$whole.SetBounds(20, 420, 300, 24)
$form.Controls.Add($whole)
$btnDl = New-Button "DOWNLOAD" 20 450 410 42 -Primary
$form.Controls.Add($btnDl)
$form.Controls.Add((New-Label "Works with YouTube and YouTube Music: single songs, albums and playlists." $fSmall $cGrey 20 498 410 36))

$form.Controls.Add((New-Label "YOUR SONGS" $fHead $cRed 460 96 200 26))
$search = New-Object System.Windows.Forms.TextBox
$search.BackColor = $cField
$search.ForeColor = $cWhite
$search.BorderStyle = "FixedSingle"
$search.SetBounds(460, 124, 420, 28)
$search.Anchor = "Top,Left,Right"
$form.Controls.Add($search)

$lv = New-Object System.Windows.Forms.ListView
$lv.View = "Details"
$lv.FullRowSelect = $true
$lv.HideSelection = $false
$lv.MultiSelect = $true
$lv.BorderStyle = "None"
$lv.BackColor = $cRow
$lv.ForeColor = $cWhite
$lv.HeaderStyle = "Nonclickable"
$lv.OwnerDraw = $true
$lv.SetBounds(460, 162, 420, 330)
$lv.Anchor = "Top,Bottom,Left,Right"
[void]$lv.Columns.Add("SONG", 250)
[void]$lv.Columns.Add("GAME / PLAYLIST", 150)
function Fit-Columns {
  $w = $lv.ClientSize.Width
  if ($w -lt 200) { return }
  $lv.Columns[1].Width = 150
  $lv.Columns[0].Width = $w - 152
}
$lv.Add_Resize({ Fit-Columns })
$lv.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"NonPublic,Instance").SetValue($lv, $true, $null)
$hdrBrush = New-Object System.Drawing.SolidBrush($cDeep)
$fHdr = P5Font 11
$lv.Add_DrawColumnHeader({
  param($s, $e)
  $e.Graphics.FillRectangle($hdrBrush, $e.Bounds)
  $e.Graphics.DrawString($e.Header.Text, $fHdr, [System.Drawing.Brushes]::White, ($e.Bounds.X + 6), ($e.Bounds.Y + 3))
})
$lv.Add_DrawItem({ param($s, $e) })
$lv.Add_DrawSubItem({
  param($s, $e)
  $sel = $e.Item.Selected
  $bg = if ($sel) { $cRed } elseif ($e.ItemIndex % 2) { $cRowAlt } else { $cRow }
  $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $e.Bounds)
  $fg = if ($sel -or $e.ColumnIndex -eq 0) { $cWhite } else { $cGrey }
  $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, ($e.Bounds.Width - 8), $e.Bounds.Height)
  [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.SubItem.Text, $fBody, $r, $fg, [System.Windows.Forms.TextFormatFlags]"VerticalCenter, Left, EndEllipsis, SingleLine, NoPrefix")
})
$form.Controls.Add($lv)
$btnRemove = New-Button "REMOVE" 460 504 140 34
$btnRemove.Anchor = "Bottom,Left"
$form.Controls.Add($btnRemove)
$countLabel = New-Label "" $fSmall $cGrey 612 512 268 22
$countLabel.Anchor = "Bottom,Left,Right"
$countLabel.TextAlign = "MiddleRight"
$form.Controls.Add($countLabel)

$bar = New-Object System.Windows.Forms.Panel
$bar.SetBounds(0, 560, 900, 70)
$bar.Anchor = "Bottom,Left,Right"
$bar.BackColor = $cPanel
$form.Controls.Add($bar)
$status = New-Label "Ready." $fBody $cWhite 20 12 620 46
$status.Anchor = "Top,Left,Right"
$bar.Controls.Add($status)
$btnReload = New-Button "RELOAD WALLPAPER" 660 16 220 38
$btnReload.Anchor = "Top,Right"
$bar.Controls.Add($btnReload)

$form.Add_Shown({
  [void][PmNative]::SetWindowTheme($lv.Handle, "DarkMode_Explorer", $null)
  Fit-Columns
  $form.ActiveControl = $url
  [void][PmNative]::SendMessage($search.Handle, 0x1501, [IntPtr]1, "Search your songs...")
  [void][PmNative]::SendMessage($url.Handle, 0x1501, [IntPtr]1, "https://music.youtube.com/watch?v=...")
})

$script:pending = $false
function Set-Pending($on) {
  $script:pending = $on
  $btnReload.BackColor = if ($on) { $cRed } else { $cDeep }
  $btnReload.Text = if ($on) { "RELOAD WALLPAPER  !" } else { "RELOAD WALLPAPER" }
}
Set-Pending $false

function Say($text, [switch]$Bad) {
  $status.ForeColor = if ($Bad) { $cRedHi } else { $cWhite }
  $status.Text = $text
}

$script:targets = @()
function Load-Playlists {
  $mainTarget = if (Test-Path (Join-Path $music "Other Music")) { Join-Path $music "Other Music" } else { $music }
  $list = @([pscustomobject]@{ Name = "All Music (the main pile)"; Path = $mainTarget; Key = "" })
  Get-ChildItem $music -Directory -ErrorAction SilentlyContinue | Where-Object { $mainFolders -notcontains $_.Name } | Sort-Object Name | ForEach-Object {
    $only = Test-Path -LiteralPath (Join-Path $_.FullName "only-when-selected.txt")
    $list += [pscustomobject]@{ Name = $_.Name + $(if ($only) { "  (only when picked)" } else { "" }); Path = $_.FullName; Key = $_.Name }
  }
  $script:targets = $list
  $combo.Items.Clear()
  foreach ($t in $list) { [void]$combo.Items.Add($t.Name) }
  $i = [Array]::IndexOf(@($list | ForEach-Object { $_.Key }), $settings.playlist)
  $combo.SelectedIndex = if ($i -ge 0) { $i } else { 0 }
}
function Get-Target { $script:targets[[Math]::Max(0, $combo.SelectedIndex)] }

$script:songs = @()
function Load-Songs {
  $songs = @()
  $pl = Join-Path $music "playlist.js"
  if (Test-Path $pl) {
    try {
      $raw = [IO.File]::ReadAllText($pl)
      $start = $raw.IndexOf("["); $end = $raw.LastIndexOf("]")
      if ($start -ge 0 -and $end -gt $start) {
        $arr = $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json
        foreach ($x in $arr) {
          if (-not $x.file) { continue }
          $rel = ($x.file -split "/" | ForEach-Object { [Uri]::UnescapeDataString($_) }) -join "\"
          $label = if ($x.game) { [string]$x.game } elseif ($x.artist) { [string]$x.artist } else { "" }
          $songs += [pscustomobject]@{ Title = [string]$x.title; Label = $label; Artist = [string]$x.artist; Path = (Join-Path $wpDir $rel) }
        }
      }
    } catch { Say "Couldn't read the playlist: $($_.Exception.Message)" -Bad }
  }
  $script:songs = $songs
  $script:headerInfo = "$($songs.Count) songs in the player"
  $header.Invalidate()
  Show-Songs
}
function Show-Songs {
  $q = $search.Text.Trim()
  $lv.BeginUpdate()
  $lv.Items.Clear()
  $shown = 0
  foreach ($s in $script:songs) {
    if ($q -and -not ($s.Title -like "*$q*" -or $s.Label -like "*$q*" -or $s.Artist -like "*$q*")) { continue }
    $it = New-Object System.Windows.Forms.ListViewItem($s.Title)
    [void]$it.SubItems.Add($s.Label)
    $it.Tag = $s.Path
    [void]$lv.Items.Add($it)
    $shown++
  }
  $lv.EndUpdate()
  Fit-Columns
  $countLabel.Text = if ($q) { "$shown of $($script:songs.Count) songs" } else { "$($script:songs.Count) songs" }
}

$script:job = $null
$script:busy = $false
function Set-Busy($on) {
  $script:busy = $on
  foreach ($c in $btnDl, $btnNew, $btnRemove, $combo, $url, $whole) { $c.Enabled = -not $on }
  $drop.Cursor = if ($on) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Hand }
}
function Start-Bg($exe, $argLine, $onLine, $onDone) {
  $log = Join-Path $env:TEMP ("persona-music-" + [guid]::NewGuid().ToString("N") + ".log")
  $p = Start-Process -FilePath $exe -ArgumentList $argLine -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + ".err")
  $null = $p.Handle
  $script:job = @{ P = $p; Files = @($log, ($log + ".err")); Pos = @{}; Buf = @{}; OnLine = $onLine; OnDone = $onDone; Lines = (New-Object System.Collections.Generic.List[string]) }
  Set-Busy $true
}
function Read-Job($j, [switch]$Final) {
  foreach ($f in $j.Files) {
    if (-not (Test-Path $f)) { continue }
    if (-not $j.Pos.ContainsKey($f)) { $j.Pos[$f] = 0L; $j.Buf[$f] = "" }
    $fs = [IO.File]::Open($f, "Open", "Read", "ReadWrite")
    try {
      if ($fs.Length -gt $j.Pos[$f]) {
        [void]$fs.Seek($j.Pos[$f], "Begin")
        $bytes = New-Object byte[] ($fs.Length - $j.Pos[$f])
        $n = $fs.Read($bytes, 0, $bytes.Length)
        $j.Pos[$f] += $n
        $j.Buf[$f] += [Text.Encoding]::UTF8.GetString($bytes, 0, $n)
      }
    } finally { $fs.Dispose() }
    $parts = $j.Buf[$f] -split "`r?`n"
    $j.Buf[$f] = if ($Final) { "" } else { $parts[-1] }
    $upto = if ($Final) { $parts.Count - 1 } else { $parts.Count - 2 }
    for ($i = 0; $i -le $upto; $i++) {
      $line = $parts[$i].Trim()
      if ($line) { $j.Lines.Add($line); if ($j.OnLine) { & $j.OnLine $line } }
    }
  }
}
$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 400
$poll.Add_Tick({
  $j = $script:job
  if (-not $j) { return }
  try { Read-Job $j } catch { }
  if ($j.P.HasExited) {
    try { Read-Job $j -Final } catch { }
    $script:job = $null
    Set-Busy $false
    foreach ($f in $j.Files) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    & $j.OnDone $j.P.ExitCode $j.Lines
  }
})
$poll.Start()

function Update-Playlist($doneText) {
  Say "Updating the playlist..."
  $script:afterUpdate = $doneText
  Start-Bg "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$updateScript`"" { param($l) if ($l -like "Looking up*") { Say "Looking up which game each new song is from..." } } {
    param($code, $lines)
    Load-Songs
    Set-Pending $true
    Say ($script:afterUpdate + "  Click RELOAD WALLPAPER to hear them.")
  }
}

function Get-UniquePath($dir, $name) {
  $p = Join-Path $dir $name
  if (-not (Test-Path -LiteralPath $p)) { return $p }
  $base = [IO.Path]::GetFileNameWithoutExtension($name); $ext = [IO.Path]::GetExtension($name)
  for ($i = 2; ; $i++) { $p = Join-Path $dir "$base ($i)$ext"; if (-not (Test-Path -LiteralPath $p)) { return $p } }
}

function Add-Files($paths) {
  if ($script:busy) { return }
  $target = Get-Target
  New-Item -ItemType Directory -Force $target.Path | Out-Null
  $files = @()
  foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p -PathType Container) { $files += Get-ChildItem -LiteralPath $p -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLower() } }
    elseif ($exts -contains [IO.Path]::GetExtension($p).ToLower()) { $files += Get-Item -LiteralPath $p }
  }
  if (-not $files.Count) { Say "There were no songs in that. Supported: mp3, m4a, aac, ogg, opus, flac, wav and webm." -Bad; return }
  $added = 0; $same = 0; $i = 0
  foreach ($f in $files) {
    $i++
    if ($f.FullName.StartsWith($music, [StringComparison]::OrdinalIgnoreCase)) { $same++; continue }
    $existing = Join-Path $target.Path $f.Name
    if ((Test-Path -LiteralPath $existing) -and (Get-Item -LiteralPath $existing).Length -eq $f.Length) { $same++; continue }
    Copy-Item -LiteralPath $f.FullName (Get-UniquePath $target.Path $f.Name)
    $added++
    if ($i % 5 -eq 0) { Say "Copying songs... $i of $($files.Count)"; [System.Windows.Forms.Application]::DoEvents() }
  }
  $where = $target.Name -replace '\s+\(only when picked\)$', ''
  if (-not $added) { Say "Those songs are already in the player."; return }
  $msg = "Added $added song$(if ($added -ne 1) { 's' }) to $where." + $(if ($same) { " ($same were already there.)" } else { "" })
  Update-Playlist $msg
}

$drop.Add_DragEnter({
  param($s, $e)
  if (-not $script:busy -and $e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = "Copy"; $script:dropHot = $true; $drop.BackColor = $cField; $drop.Invalidate() }
})
$drop.Add_DragLeave({ $script:dropHot = $false; $drop.BackColor = $cPanel; $drop.Invalidate() })
$drop.Add_DragDrop({
  param($s, $e)
  $script:dropHot = $false; $drop.BackColor = $cPanel; $drop.Invalidate()
  Add-Files @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
})
$drop.Add_Click({
  if ($script:busy) { return }
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Multiselect = $true
  $dlg.Title = "Pick songs to add"
  $dlg.Filter = "Songs|*.mp3;*.m4a;*.aac;*.ogg;*.opus;*.flac;*.wav;*.webm|All files|*.*"
  if ($dlg.ShowDialog($form) -eq "OK") { Add-Files $dlg.FileNames }
})

$combo.Add_SelectedIndexChanged({
  $t = Get-Target
  if ($t) { $settings.playlist = $t.Key; Save-Settings }
})

$btnNew.Add_Click({
  $d = New-Object System.Windows.Forms.Form
  $d.Text = "New playlist"
  $d.ClientSize = New-Object System.Drawing.Size(380, 178)
  $d.FormBorderStyle = "FixedDialog"; $d.MaximizeBox = $false; $d.MinimizeBox = $false
  $d.StartPosition = "CenterParent"
  $d.BackColor = $cBg; $d.ForeColor = $cWhite; $d.Font = $fBody
  $d.Add_HandleCreated({ $one = 1; [void][PmNative]::DwmSetWindowAttribute($d.Handle, 20, [ref]$one, 4) })
  $d.Controls.Add((New-Label "PLAYLIST NAME" $fHead $cRed 16 12 300 26))
  $name = New-Object System.Windows.Forms.TextBox
  $name.BackColor = $cField; $name.ForeColor = $cWhite; $name.BorderStyle = "FixedSingle"
  $name.SetBounds(16, 42, 348, 28)
  $d.Controls.Add($name)
  $only = New-Object System.Windows.Forms.CheckBox
  $only.Text = "Only play these when I pick this playlist in the player"
  $only.ForeColor = $cWhite; $only.FlatStyle = "Flat"; $only.Font = $fSmall
  $only.SetBounds(16, 78, 350, 24)
  $d.Controls.Add($only)
  $ok = New-Button "CREATE" 16 120 170 40 -Primary
  $cancel = New-Button "CANCEL" 194 120 170 40
  $d.Controls.Add($ok); $d.Controls.Add($cancel)
  $d.AcceptButton = $ok; $d.CancelButton = $cancel
  $ok.Add_Click({
    $n = $name.Text.Trim()
    if (-not $n) { return }
    if ($n.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $mainFolders -contains $n) {
      [System.Windows.Forms.MessageBox]::Show($d, "Pick a different name (no \ / : * ? `" < > |).", "New playlist") | Out-Null
      return
    }
    $dir = Join-Path $music $n
    New-Item -ItemType Directory -Force $dir | Out-Null
    if ($only.Checked) { New-Item -ItemType File -Force (Join-Path $dir "only-when-selected.txt") | Out-Null }
    $settings.playlist = $n
    Save-Settings
    $d.DialogResult = "OK"
  })
  if ($d.ShowDialog($form) -eq "OK") {
    Load-Playlists
    Say "Made the playlist '$($settings.playlist)'. Now drop songs or paste a link to fill it."
  }
})

$url.Add_TextChanged({
  $t = $url.Text
  if ($t -match 'playlist\?list=|/browse/') { $whole.Checked = $true }
  elseif ($t -match 'watch\?v=') { $whole.Checked = $false }
})

function Find-YtDlp {
  $c = Get-Command yt-dlp -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $cands = @((Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\yt-dlp.exe"))
  $cands += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\yt-dlp.yt-dlp_*\yt-dlp.exe") -ErrorAction SilentlyContinue | ForEach-Object FullName)
  $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Start-Download {
  $link = $url.Text.Trim()
  if ($link -notmatch '^https?://(www\.|music\.|m\.)?(youtube\.com|youtu\.be)/') { Say "Paste a YouTube or YouTube Music link first." -Bad; return }
  $yt = Find-YtDlp
  if (-not $yt) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Say "yt-dlp is needed for links, and winget isn't available to install it." -Bad; return }
    Say "Installing yt-dlp (only the first time, takes a minute)..."
    Start-Bg "winget.exe" "install --id yt-dlp.yt-dlp -e --silent --accept-package-agreements --accept-source-agreements" $null {
      param($code, $lines)
      if (Find-YtDlp) { Start-Download } else { Say "Couldn't install yt-dlp (winget error $code)." -Bad }
    }
    return
  }
  $target = Get-Target
  New-Item -ItemType Directory -Force $target.Path | Out-Null
  $archive = Join-Path $appData "have.txt"
  $ids = Get-ChildItem $music -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { if ($_.BaseName -match '\[([A-Za-z0-9_-]{11})\]$') { "youtube " + $Matches[1] } }
  [IO.File]::WriteAllLines($archive, [string[]]@($ids))
  $script:dl = @{ Target = $target; Started = Get-Date; Item = ""; Skipped = 0; Errors = (New-Object System.Collections.Generic.List[string]) }
  $mode = if ($whole.Checked) { "--yes-playlist" } else { "--no-playlist" }
  $out = Join-Path $target.Path "%(title)s [%(id)s].%(ext)s"
  $argLine = "-f bestaudio --newline --no-warnings --ignore-errors --encoding utf-8 --download-archive `"$archive`" $mode -o `"$out`" `"$link`""
  Say "Starting the download..."
  Start-Bg $yt $argLine {
    param($l)
    if ($l -match '^\[download\] Downloading item (\d+) of (\d+)') { $script:dl.Item = "song $($Matches[1]) of $($Matches[2]), " }
    elseif ($l -match '^\[download\]\s+([\d\.]+)%') { Say ("Downloading " + $script:dl.Item + [int][double]$Matches[1] + "%") }
    elseif ($l -match 'already been recorded in the archive') { $script:dl.Skipped++ }
    elseif ($l -match '^ERROR:\s*(.*)$') { $script:dl.Errors.Add($Matches[1]) }
  } {
    param($code, $lines)
    $lines | Set-Content (Join-Path $appData "last-download.log") -Encoding UTF8
    $new = @(Get-ChildItem -LiteralPath $script:dl.Target.Path -File | Where-Object { $_.LastWriteTime -ge $script:dl.Started.AddSeconds(-2) -and $exts -contains $_.Extension.ToLower() })
    $where = $script:dl.Target.Name -replace '\s+\(only when picked\)$', ''
    if ($new.Count) {
      $url.Text = ""
      $msg = "Downloaded $($new.Count) song$(if ($new.Count -ne 1) { 's' }) into $where." + $(if ($script:dl.Skipped) { " ($($script:dl.Skipped) you already had.)" } else { "" }) + $(if ($script:dl.Errors.Count) { " $($script:dl.Errors.Count) couldn't be downloaded." } else { "" })
      Update-Playlist $msg
    } elseif ($script:dl.Skipped) {
      Say "You already have $(if ($script:dl.Skipped -eq 1) { 'that song' } else { 'all of those songs' })."
    } elseif ($script:dl.Errors.Count) {
      Say ("Download failed: " + $script:dl.Errors[0]) -Bad
    } else {
      Say "Nothing was downloaded. Check the link and try again." -Bad
    }
  }
}
$btnDl.Add_Click({ if (-not $script:busy) { Start-Download } })
$url.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq "Enter") { $e.SuppressKeyPress = $true; if (-not $script:busy) { Start-Download } } })

$search.Add_TextChanged({ Show-Songs })

$btnRemove.Add_Click({
  if ($script:busy) { return }
  $sel = @($lv.SelectedItems | ForEach-Object { $_ })
  if (-not $sel.Count) { Say "Click a song in the list first (hold Ctrl to pick several)."; return }
  $what = if ($sel.Count -eq 1) { "`"$($sel[0].Text)`"" } else { "these $($sel.Count) songs" }
  $ans = [System.Windows.Forms.MessageBox]::Show($form, "Remove $what from the player?`n`nThey get moved to Music\Persona Desktop - removed songs, so you can get them back.", "Remove songs", "YesNo", "Question")
  if ($ans -ne "Yes") { return }
  New-Item -ItemType Directory -Force $removedDir | Out-Null
  $moved = 0; $failed = 0
  foreach ($it in $sel) {
    $p = [string]$it.Tag
    if (-not (Test-Path -LiteralPath $p)) { continue }
    try { Move-Item -LiteralPath $p (Get-UniquePath $removedDir (Split-Path $p -Leaf)); $moved++ } catch { $failed++ }
  }
  if ($moved) { Update-Playlist ("Removed $moved song$(if ($moved -ne 1) { 's' })." + $(if ($failed) { " $failed couldn't be moved because the wallpaper is playing them right now." } else { "" })) }
  elseif ($failed) { Say "Couldn't remove that song because the wallpaper is playing it right now. Skip to another song and try again." -Bad }
})

$btnReload.Add_Click({
  $livelyExe = Find-LivelyExe
  if (-not $livelyExe) { Say "Couldn't find Lively Wallpaper. Open Lively from the Start menu, then click this again." -Bad; return }
  Say "Reloading the wallpaper..."
  $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
  Start-Process $livelyExe -ArgumentList "closewp --monitor -1" -WindowStyle Hidden -Wait
  Start-Sleep -Milliseconds 1500
  Start-Process $livelyExe -ArgumentList "setwp --file `"$wpDir`"" -WindowStyle Hidden -Wait
  $form.Cursor = [System.Windows.Forms.Cursors]::Default
  Set-Pending $false
  Say "Wallpaper reloaded with your new songs. Press play on its music player."
})

$form.Add_FormClosing({
  param($s, $e)
  if ($script:job -and -not $script:job.P.HasExited) {
    $ans = [System.Windows.Forms.MessageBox]::Show($form, "Something is still downloading or updating. Close anyway?", "Persona Music", "YesNo", "Warning")
    if ($ans -ne "Yes") { $e.Cancel = $true; return }
    try { $script:job.P.Kill() } catch { }
  }
})

Load-Playlists
Load-Songs
[System.Windows.Forms.Application]::Run($form)
