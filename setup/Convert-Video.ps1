param([Parameter(Mandatory = $true)][string]$Path, [int]$MaxHeight = 1080)
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.FileProperties.VideoProperties, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime]
$null = [Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]

$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 }
$opTask = $asTask | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$progTask = $asTask | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1' } | Select-Object -First 1

function Await($op, [Type]$type) {
  $task = $opTask.MakeGenericMethod($type).Invoke($null, @($op))
  [void]$task.Wait(-1)
  $task.Result
}

function Get-VideoSize($file) {
  $p = Await ($file.Properties.GetVideoPropertiesAsync()) ([Windows.Storage.FileProperties.VideoProperties])
  @{ Width = [int]$p.Width; Height = [int]$p.Height; Seconds = [int]$p.Duration.TotalSeconds }
}

$Path = (Resolve-Path $Path).Path
$src = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
$size = Get-VideoSize $src
Write-Output ("Video is {0}x{1}, {2} seconds." -f $size.Width, $size.Height, $size.Seconds)
if ($size.Height -le 0) { throw "Windows couldn't read the video's size." }
if ($size.Height -le $MaxHeight) {
  Write-Output "No conversion needed."
  exit 0
}

$srcProfile = Await ([Windows.Media.MediaProperties.MediaEncodingProfile]::CreateFromFileAsync($src)) ([Windows.Media.MediaProperties.MediaEncodingProfile])
$fps = 30
if ($srcProfile.Video -and $srcProfile.Video.FrameRate.Denominator -gt 0) {
  $fps = [Math]::Round($srcProfile.Video.FrameRate.Numerator / $srcProfile.Video.FrameRate.Denominator)
}
$height = $MaxHeight
$width = [int]([Math]::Round($size.Width * $height / $size.Height / 2) * 2)

$profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp4([Windows.Media.MediaProperties.VideoEncodingQuality]::HD1080p)
$profile.Audio = $null
$profile.Video.Width = $width
$profile.Video.Height = $height
$profile.Video.FrameRate.Numerator = $fps
$profile.Video.FrameRate.Denominator = 1
$profile.Video.Bitrate = 12000000

$dir = Split-Path $Path
$tmpName = [IO.Path]::GetFileNameWithoutExtension($Path) + ".converting.mp4"
$folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($dir)) ([Windows.Storage.StorageFolder])
$dst = Await ($folder.CreateFileAsync($tmpName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])

$tc = New-Object Windows.Media.Transcoding.MediaTranscoder
$tc.HardwareAccelerationEnabled = $true
$prep = Await ($tc.PrepareFileTranscodeAsync($src, $dst, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])
if (-not $prep.CanTranscode) {
  Remove-Item (Join-Path $dir $tmpName) -Force -ErrorAction SilentlyContinue
  throw "Windows can't convert this video ($($prep.FailureReason))."
}
Write-Output ("Converting to {0}x{1} at {2} fps..." -f $width, $height, $fps)
$watch = [Diagnostics.Stopwatch]::StartNew()
$task = $progTask.MakeGenericMethod([double]).Invoke($null, @($prep.TranscodeAsync()))
try { [void]$task.Wait(-1) } catch { }
if ($task.Status -ne "RanToCompletion") {
  Remove-Item (Join-Path $dir $tmpName) -Force -ErrorAction SilentlyContinue
  $why = if ($task.Exception) { $task.Exception.InnerException.Message } else { $task.Status }
  throw "Converting the video failed: $why"
}

$tmpPath = Join-Path $dir $tmpName
$out = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmpPath)) ([Windows.Storage.StorageFile])
$outSize = Get-VideoSize $out
if ($outSize.Height -ne $height -or (Get-Item $tmpPath).Length -lt 1000000) {
  Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
  throw ("The converted video looks wrong ({0}x{1})." -f $outSize.Width, $outSize.Height)
}
Move-Item $tmpPath $Path -Force
Write-Output ("Done in {0} seconds: {1}x{2}, {3:N1} MB." -f [int]$watch.Elapsed.TotalSeconds, $outSize.Width, $outSize.Height, ((Get-Item $Path).Length / 1MB))
