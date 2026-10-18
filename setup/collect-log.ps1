param([switch]$NoWallpaperTest)
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms

$app = Join-Path $env:LOCALAPPDATA "PersonaDesktop"
$livelyData = Join-Path $env:LOCALAPPDATA "Lively Wallpaper"
$livelyExe = Join-Path $env:LOCALAPPDATA "Programs\Lively Wallpaper\Lively.exe"
$rmExe = Join-Path $env:ProgramFiles "Rainmeter\Rainmeter.exe"
$work = Join-Path $env:TEMP ("persona-desktop-log-" + [guid]::NewGuid().ToString("N"))
$zip = Join-Path ([Environment]::GetFolderPath("Desktop")) "PersonaDesktop-log.zip"
$report = Join-Path $work "report.txt"
New-Item -ItemType Directory -Force $work, (Join-Path $work "lively-logs") | Out-Null

function Say($m) { Write-Host "   $m" }
function Add($title, $lines) {
  Add-Content $report "== $title =="
  foreach ($l in @($lines)) { Add-Content $report ([string]$l) }
  Add-Content $report ""
}
function Try-Lines($block) { try { & $block } catch { "failed: $($_.Exception.Message)" } }

Write-Host ""
Write-Host "  PERSONA DESKTOP LOG  " -ForegroundColor White -BackgroundColor DarkRed
Say "Collecting info about your PC and the wallpaper. This takes about a minute."

$wpDir = $null
$stateFile = Join-Path $app "state.json"
if (Test-Path $stateFile) { try { $wpDir = (Get-Content $stateFile -Raw | ConvertFrom-Json).wallpaper } catch { } }
if (-not $wpDir -or -not (Test-Path $wpDir)) {
  $layout = Join-Path $livelyData "WallpaperLayout.json"
  if (Test-Path $layout) { try { $wpDir = @((Get-Content $layout -Raw | ConvertFrom-Json) | ForEach-Object { $_.LivelyInfoPath } | Where-Object { $_ -and (Test-Path $_) })[0] } catch { } }
}
if (-not $wpDir -or -not (Test-Path (Join-Path $wpDir "hud.js"))) {
  $found = Get-ChildItem (Join-Path $livelyData "Library\wallpapers") -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "hud.js") } | Select-Object -First 1
  if ($found) { $wpDir = $found.FullName }
}

Add "Persona Desktop log" @(
  "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
  "Wallpaper folder: $wpDir"
)

Add "Windows" (Try-Lines {
  $os = Get-CimInstance Win32_OperatingSystem
  "$($os.Caption) $($os.Version) build $($os.BuildNumber) ($($os.OSArchitecture))"
  "Language: $((Get-Culture).Name)"
  "Last boot: $($os.LastBootUpTime)"
  "PowerShell: $($PSVersionTable.PSVersion)"
})

Add "Hardware" (Try-Lines {
  Get-CimInstance Win32_Processor | ForEach-Object { "CPU: $($_.Name.Trim())" }
  "RAM: {0:N1} GB" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
  Get-CimInstance Win32_VideoController | ForEach-Object { "GPU: $($_.Name) | driver $($_.DriverVersion) from $($_.DriverDate) | $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) @ $($_.CurrentRefreshRate) Hz" }
  [System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "Screen: $($_.DeviceName) $($_.Bounds.Width)x$($_.Bounds.Height) primary=$($_.Primary)" }
  $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
  if ($bat) { "Battery: $($bat.EstimatedChargeRemaining)% status $($bat.BatteryStatus) (1 = on battery, 2 = plugged in)" } else { "Battery: none" }
})

Add "Software" (Try-Lines {
  if (Test-Path $livelyExe) { "Lively: $((Get-Item $livelyExe).VersionInfo.FileVersion)" } else { "Lively: not found at $livelyExe" }
  if (Test-Path $rmExe) { "Rainmeter: $((Get-Item $rmExe).VersionInfo.ProductVersion)" } else { "Rainmeter: not found" }
  $wv = @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}") | ForEach-Object { (Get-ItemProperty $_ -ErrorAction SilentlyContinue).pv } | Select-Object -First 1
  "WebView2 runtime: $wv"
  $av = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object displayName
  "Antivirus: $($av -join ', ')"
})

Add "Running" (Try-Lines {
  foreach ($n in "Lively", "Lively.Player.WebView2", "Lively.Watchdog", "Rainmeter") {
    $p = @(Get-Process $n -ErrorAction SilentlyContinue)
    "{0}: {1}" -f $n, $(if ($p.Count) { "yes (started $($p[0].StartTime))" } else { "no" })
  }
})

Add "Wallpaper files" (Try-Lines {
  if (-not $wpDir -or -not (Test-Path $wpDir)) { "Wallpaper folder not found."; return }
  Get-ChildItem $wpDir -File | ForEach-Object { "{0,-28} {1,12:N0} bytes  {2}" -f $_.Name, $_.Length, $_.LastWriteTime }
  $music = @(Get-ChildItem (Join-Path $wpDir "music") -File -Recurse -ErrorAction SilentlyContinue | Where-Object { ".mp3", ".m4a", ".ogg", ".opus", ".flac", ".wav", ".webm", ".aac" -contains $_.Extension.ToLower() })
  "Songs: $($music.Count)"
  $video = Join-Path $wpDir "background.mp4"
  if (Test-Path $video) {
    $sh = New-Object -ComObject Shell.Application
    $f = $sh.Namespace($wpDir).ParseName("background.mp4")
    "Video: {0}x{1}, {2:N1} seconds, {3:N1} Mbps, {4:N0} fps, {5:N1} MB" -f $f.ExtendedProperty("System.Video.FrameWidth"), $f.ExtendedProperty("System.Video.FrameHeight"), ($f.ExtendedProperty("System.Media.Duration") / 1e7), ($f.ExtendedProperty("System.Video.EncodingBitrate") / 1e6), ($f.ExtendedProperty("System.Video.FrameRate") / 1000), ((Get-Item $video).Length / 1MB)
  } else { "Video: background.mp4 is missing" }
})

foreach ($n in "Settings.json", "WallpaperLayout.json") {
  $f = Join-Path $livelyData $n
  if (Test-Path $f) { Copy-Item $f (Join-Path $work "lively-$n") }
}
if ($wpDir) {
  $saved = Get-ChildItem (Join-Path $livelyData "Library\SaveData\wpdata") -Recurse -Filter "LivelyProperties.json" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*$(Split-Path $wpDir -Leaf)*" } | Select-Object -First 1
  if ($saved) { Copy-Item $saved.FullName (Join-Path $work "wallpaper-saved-settings.json") }
}
Get-ChildItem (Join-Path $livelyData "logs") -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 4 | ForEach-Object { Copy-Item $_.FullName (Join-Path $work "lively-logs") }
$installLog = Join-Path $app "install-log.txt"
if (Test-Path $installLog) { Copy-Item $installLog $work } else { Add "Install log" "No install log found (installed before version 1.5, or not installed)." }

function Get-Json($url) {
  try { Invoke-RestMethod -Uri $url -TimeoutSec 3 } catch { $null }
}

function Invoke-Cdp($wsUrl, $expr) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ct = [Threading.CancellationToken]::None
  try {
    if (-not $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(10000)) { return $null }
    $msg = @{ id = 1; method = "Runtime.evaluate"; params = @{ expression = $expr; returnByValue = $true } } | ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    [void]$ws.SendAsync((New-Object "System.ArraySegment[byte]" -ArgumentList @(, $bytes)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(10000)
    $buf = New-Object byte[] 65536
    $ms = New-Object IO.MemoryStream
    do {
      $t = $ws.ReceiveAsync((New-Object "System.ArraySegment[byte]" -ArgumentList @(, $buf)), $ct)
      if (-not $t.Wait(15000)) { break }
      $ms.Write($buf, 0, $t.Result.Count)
    } while (-not $t.Result.EndOfMessage)
    $resp = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
    $resp.result.result.value
  } catch { $null } finally { $ws.Dispose() }
}

function Find-Page($port) {
  $list = Get-Json "http://127.0.0.1:$port/json"
  @($list) | Where-Object { $_.type -eq "page" -and $_.url -like "*index.html*" } | Select-Object -First 1
}

if (-not $NoWallpaperTest -and (Test-Path $livelyExe) -and $wpDir) {
  Say "Testing the wallpaper. It restarts for about 40 seconds, so your music pauses."
  $port = 9339
  $notes = New-Object System.Collections.Generic.List[string]
  Get-Process | Where-Object { $_.Path -like "*Lively Wallpaper*" } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$port"
  Start-Process $livelyExe
  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $null
  $page = $null
  for ($i = 0; $i -lt 25 -and -not $page; $i++) { Start-Sleep 1; $page = Find-Page $port }
  if (-not $page) {
    $notes.Add("Lively did not load the wallpaper by itself within 25 seconds, so the test told it to.")
    & $livelyExe setwp --file $wpDir
    for ($i = 0; $i -lt 25 -and -not $page; $i++) { Start-Sleep 1; $page = Find-Page $port }
  }
  if ($page) {
    Say "Wallpaper is running, watching it for 20 seconds..."
    Start-Sleep 20
    $diag = Invoke-Cdp $page.webSocketDebuggerUrl "JSON.stringify(window.__pdDiag ? window.__pdDiag() : { missing: 'the wallpaper script did not start' })"
    if ($diag) {
      $diag | Set-Content (Join-Path $work "wallpaper-test.json") -Encoding UTF8
      try {
        $d = $diag | ConvertFrom-Json
        $notes.Add("GPU seen by the wallpaper: $($d.gpu)")
        $notes.Add("Single video mode: $($d.single), problems: $($d.strikes), gave up: $($d.gaveUp)")
        foreach ($v in @($d.videos)) { $notes.Add("Video $($v.i): $($v.size), time $($v.time)s, paused $($v.paused), frames $($v.frames), dropped $($v.dropped), error $($v.error)") }
        foreach ($l in @($d.log)) { $notes.Add("  $l") }
      } catch { $notes.Add("Couldn't read the test result: $($_.Exception.Message)") }
    } else { $notes.Add("Couldn't read the wallpaper's status.") }
  } else { $notes.Add("The wallpaper page never started.") }
  Add "Wallpaper test" $notes
  Get-Process | Where-Object { $_.Path -like "*Lively Wallpaper*" } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
  Start-Process $livelyExe
  Get-ChildItem (Join-Path $livelyData "logs") -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2 | ForEach-Object { Copy-Item $_.FullName (Join-Path $work "lively-logs") -Force }
}

$user = [regex]::Escape($env:USERNAME)
Get-ChildItem $work -Recurse -File | Where-Object { ".txt", ".json" -contains $_.Extension } | ForEach-Object {
  $text = [IO.File]::ReadAllText($_.FullName)
  $text = [regex]::Replace($text, "(?i)(Users(\\\\|\\|/))$user(?=\\|/|""|$)", '$1<user>')
  [IO.File]::WriteAllText($_.FullName, $text, (New-Object Text.UTF8Encoding $false))
}

Remove-Item $zip -Force -ErrorAction SilentlyContinue
& tar.exe -a -c -f $zip -C $work . 2>$null
if (-not (Test-Path $zip)) { Compress-Archive -Path (Join-Path $work "*") -DestinationPath $zip -Force }
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if (Test-Path $zip) {
  Write-Host "  DONE  " -ForegroundColor White -BackgroundColor DarkRed
  Say "Your log is on your Desktop: PersonaDesktop-log.zip"
  Say "Send that file to whoever is helping you."
  Start-Process explorer.exe "/select,`"$zip`""
} else {
  Say "Couldn't create the zip file."
}
