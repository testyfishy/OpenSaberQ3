<#
.SYNOPSIS
  Capture on-device Quest frame timing + thermal state for a fixed window.

.DESCRIPTION
  Host-side only: nothing is installed and no in-app code is required, so this can measure
  the unmodified baseline APK as well as the fork (spec FR-023).

  Source of truth is the VR runtime's own log line (VrApi), which reports achieved/target FPS,
  stale frames and tear per sample. Thermal state and battery/charging come from dumpsys and are
  recorded with every run because Quest 3 raises clocks while charging (spec R-6).

.EXAMPLE
  pwsh -File tools/perf/capture.ps1 -Seconds 120 -Label baseline-cool
#>
[CmdletBinding()]
param(
    [int]$Seconds = 120,
    [string]$Label = 'run',
    [string]$Package = 'org.godotengine.open_saber',
    [string]$OutDir = 'perf/captures',
    [string]$Adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Adb)) { throw "adb not found at $Adb" }

# 0. device gate
$devices = & $Adb devices | Select-String -Pattern '\sdevice$'
if (-not $devices) { throw "No authorized device. Run 'adb devices' and accept the prompt on the headset." }
$serial = ($devices[0].Line -split "`t")[0]
Write-Host "device: $serial"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = Join-Path $OutDir "$stamp-$Label"

function Invoke-Adb([string]$cmd) { (& $Adb -s $serial shell $cmd 2>&1) -join "`n" }

# 1. metadata snapshot (state at capture start, not averaged)
$battery = Invoke-Adb "dumpsys battery"
$thermal = Invoke-Adb "dumpsys thermalservice"
$meta = [ordered]@{
    label           = $Label
    captured_at     = (Get-Date).ToString('o')
    serial          = $serial
    package         = $Package
    seconds         = $Seconds
    model           = (Invoke-Adb "getprop ro.product.model").Trim()
    os_version      = (Invoke-Adb "getprop ro.build.version.release").Trim()
    battery_level   = if ($battery -match 'level:\s*(\d+)') { [int]$Matches[1] } else { $null }
    charging        = if ($battery -match 'AC powered:\s*(\w+)') { $Matches[1] } else { $null }
    usb_powered     = if ($battery -match 'USB powered:\s*(\w+)') { $Matches[1] } else { $null }
    thermal_status  = if ($thermal -match 'Thermal Status:\s*(\d+)') { [int]$Matches[1] } else { $null }
    app_installed   = [bool](Invoke-Adb "pm list packages $Package" | Select-String $Package)
}
$meta | ConvertTo-Json | Set-Content "$base.meta.json" -Encoding utf8
Write-Host ("battery={0}% charging={1} thermal_status={2}" -f $meta.battery_level, $meta.charging, $meta.thermal_status)

# 2. start logcat (VrApi carries the frame samples; Godot tag warns about engine-side stalls)
& $Adb -s $serial logcat -c
$log = "$base.logcat.txt"
$proc = Start-Process -FilePath $Adb `
    -ArgumentList @('-s', $serial, 'logcat', '-v', 'time', 'VrApi:I', 'Godot:I', 'GodotEngine:I', 'libc:F', '*:S') `
    -RedirectStandardOutput $log -PassThru -WindowStyle Hidden

Write-Host "capturing $Seconds s -> $log"
Start-Sleep -Seconds $Seconds
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 3. parse. VrApi sample shape:
#   FPS=72/72,Prd=33ms,Tear=0,Early=0,Stale=0,...,CPU4/GPU=3/3,1094/587MHz,...
$lines = Get-Content $log -ErrorAction SilentlyContinue
$samples = foreach ($l in $lines) {
    if ($l -match 'FPS=(\d+)/(\d+)') {
        [pscustomobject]@{
            fps          = [int]$Matches[1]
            target       = [int]$Matches[2]
            stale        = if ($l -match 'Stale=(\d+)') { [int]$Matches[1] } else { $null }
            tear         = if ($l -match 'Tear=(\d+)') { [int]$Matches[1] } else { $null }
            cpu          = if ($l -match 'CPU4?/GPU=(\d+)/(\d+)') { [int]$Matches[1] } else { $null }
            gpu          = if ($l -match 'CPU4?/GPU=(\d+)/(\d+)') { [int]$Matches[2] } else { $null }
            raw          = $l
        }
    }
}

if (-not $samples) {
    Write-Warning "No VrApi FPS samples found. Is the app actually running and in immersive mode?"
    $summary = [ordered]@{ label = $Label; samples = 0; note = 'no VrApi samples' }
} else {
    $fps = $samples.fps
    $target = ($samples.target | Select-Object -First 1)
    $budgetMs = 1000.0 / $target
    $onTarget = ($samples | Where-Object { $_.fps -ge $_.target }).Count
    $sorted = $fps | Sort-Object
    $summary = [ordered]@{
        label              = $Label
        samples            = $samples.Count
        target_fps         = $target
        frame_budget_ms    = [math]::Round($budgetMs, 2)
        fps_mean           = [math]::Round(($fps | Measure-Object -Average).Average, 2)
        fps_min            = ($fps | Measure-Object -Minimum).Minimum
        fps_p1             = $sorted[[math]::Min($sorted.Count - 1, [int][math]::Floor($sorted.Count * 0.01))]
        fps_p5             = $sorted[[math]::Min($sorted.Count - 1, [int][math]::Floor($sorted.Count * 0.05))]
        pct_samples_on_target = [math]::Round(100.0 * $onTarget / $samples.Count, 1)
        pct_frames_on_budget  = [math]::Round(100.0 * $onTarget / $samples.Count, 1)
        stale_total        = ($samples.stale | Measure-Object -Sum).Sum
        cpu_level_max      = ($samples.cpu | Measure-Object -Maximum).Maximum
        gpu_level_max      = ($samples.gpu | Measure-Object -Maximum).Maximum
        battery_level      = $meta.battery_level
        charging           = $meta.charging
        thermal_status     = $meta.thermal_status
    }
}

$summary | ConvertTo-Json | Set-Content "$base.summary.json" -Encoding utf8
$summary.GetEnumerator() | ForEach-Object { "{0,-22} {1}" -f $_.Key, $_.Value }
Write-Host ""
Write-Host "wrote: $base.summary.json"
Write-Host "       $base.logcat.txt"
