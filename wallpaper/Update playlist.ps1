$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$music = Join-Path $here "music"
$metaFile = Join-Path $music "meta.json"
$exts = ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac", ".wav", ".webm"
$files = Get-ChildItem $music -File -Recurse | Where-Object { $exts -contains $_.Extension.ToLower() }

$meta = @{}
if (Test-Path $metaFile) {
  (Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $meta[$_.Name] = $_.Value }
}
$missing = @($files | ForEach-Object { if ($_.BaseName -match '\[([A-Za-z0-9_-]{11})\]$') { $Matches[1] } } | Where-Object { -not $meta.ContainsKey($_) } | Select-Object -Unique)
if ($missing.Count) {
  $yt = (Get-Command yt-dlp -ErrorAction SilentlyContinue).Source
  if (-not $yt) { $yt = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\yt-dlp.yt-dlp_*\yt-dlp.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
  if ($yt) {
    Write-Host ("Looking up " + $missing.Count + " songs on YouTube Music...")
    $batch = Join-Path $env:TEMP "p3_playlist_ids.txt"
    $missing | ForEach-Object { "https://music.youtube.com/watch?v=$_" } | Set-Content $batch -Encoding ASCII
    $prev = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $out = & $yt --skip-download --no-warnings --ignore-errors --encoding utf-8 -a $batch --print "%(id)s`t%(album)s`t%(artist)s`t%(title)s" 2>$null
    [Console]::OutputEncoding = $prev
    foreach ($line in $out) {
      $p = $line -split "`t"
      if ($p.Count -ge 4) { $meta[$p[0]] = [pscustomobject]@{ album = $p[1]; artist = $p[2]; title = $p[3] } }
    }
    foreach ($id in $missing) { if (-not $meta.ContainsKey($id)) { $meta[$id] = [pscustomobject]@{ album = "NA"; artist = "NA"; title = "NA" } } }
    Remove-Item $batch -ErrorAction SilentlyContinue
    $obj = [ordered]@{}
    foreach ($k in ($meta.Keys | Sort-Object)) { $obj[$k] = $meta[$k] }
    [IO.File]::WriteAllText($metaFile, (ConvertTo-Json -InputObject $obj -Depth 3), (New-Object Text.UTF8Encoding $false))
  }
}

$games = @(
  @('persona\s*5.*royal|p5r', 'PERSONA 5 ROYAL'),
  @('persona\s*5|persona5|p5 ', 'PERSONA 5'),
  @('persona\s*3.*reload|p3r', 'PERSONA 3 RELOAD'),
  @('persona\s*3|persona3', 'PERSONA 3'),
  @('persona\s*4|persona4', 'PERSONA 4'),
  @('undertale', 'UNDERTALE'),
  @('deltarune', 'DELTARUNE'),
  @('ultrakill|cyber grind', 'ULTRAKILL'),
  @('metal gear rising', 'METAL GEAR RISING'),
  @('metal gear', 'METAL GEAR'),
  @('castlevania', 'CASTLEVANIA'),
  @('kingdom come', 'KINGDOM COME: DELIVERANCE')
)
function Get-Game($text) {
  foreach ($g in $games) { if ($text -match $g[0]) { return $g[1] } }
  return ""
}
function Clean-Album($a) {
  if (-not $a -or $a -eq "NA") { return "" }
  $a = $a -replace '\s*[\(\[]?(original\s+)?(game\s+)?(sound\s*track|ost|soundtrack)[\)\]]?.*$', ''
  $a = $a -replace '\s*[\(\[][^\)\]]*$', ''
  return $a.Trim(" -:")
}

$list = @()
$files | Sort-Object @{ Expression = { $_.Directory.Name -ne "Persona 3 Reload" } }, FullName | ForEach-Object {
  $id = if ($_.BaseName -match '\[([A-Za-z0-9_-]{11})\]$') { $Matches[1] } else { "" }
  $m = if ($id -and $meta.ContainsKey($id)) { $meta[$id] } else { $null }
  $title = (($_.BaseName -replace '\s*\[[A-Za-z0-9_-]{11}\]$', '') -replace '^\s*\d+[\s\.\-_]+', '').Trim()
  $title = ($title -replace '\s*\([^)]*(soundtrack|ost)[^)]*\)\s*-\s*.*$', '' -replace '\s*\([^)]*(soundtrack|ost)[^)]*\)\s*$', '').Trim()
  $album = if ($m) { [string]$m.album } else { "" }
  $artist = if ($m -and $m.artist -and $m.artist -ne "NA") { (([string]$m.artist -split ',\s*') | Where-Object { $_ -notmatch '^ATLUS' } | Select-Object -First 1) } else { "" }
  $game = Get-Game ($album + " " + $_.BaseName + " " + $_.Directory.Name)
  if (-not $game) { $game = Clean-Album $album }
  $folderCat = $false
  if ($_.Directory.FullName -ne $music -and @("Other Music", "Persona 3 Reload") -notcontains $_.Directory.Name) { $game = $_.Directory.Name.ToUpper(); $folderCat = $true }
  if ($game -and $game -eq $title) { $game = "" }
  if (-not $artist -and $_.Directory.FullName -ne $music) { $artist = $_.Directory.Name }
  $rel = $_.FullName.Substring($here.Length + 1) -split '\\' | ForEach-Object { [uri]::EscapeDataString($_) }
  $list += [ordered]@{ file = ($rel -join '/'); title = $title; artist = $artist; game = $game; folder = $folderCat }
}
$json = if ($list.Count) { ConvertTo-Json -InputObject @($list) -Depth 3 } else { "[]" }
Set-Content -Path (Join-Path $music "playlist.js") -Value ("window.P3_PLAYLIST = " + $json + ";") -Encoding UTF8
Write-Host ("Playlist updated: " + $list.Count + $(if ($list.Count -eq 1) { " song." } else { " songs." }))
Write-Host "Reload the wallpaper in Lively (or restart Lively) to hear them."
