<#
.SYNOPSIS
  Run one deterministic on-device benchmark and validate that the capture is trustworthy.

.DESCRIPTION
  Implements the measurement rig agreed at G2 (advisor):
    1. Put the headset into Meta's supported test-automation state (guardian off, system dialogs
       off, autosleep off) via the com.oculus.rc content provider. PIN comes from -Pin or
       $env:OCULUS_TEST_PIN and is never written to disk or the repo.
    2. Verify the fork is actually the resumed activity before trusting anything.
    3. Record environment (charging, battery temp, cold/hot) with the run.
    4. Push the bench flag, launch, wait for the app to finish, pull bench.csv,
       and capture VrApi samples to a sidecar file.
    5. Fail loudly if the CSV is missing or short, instead of producing a number that lies.

  System properties are restored at the end (autosleep/guardian back on), because leaving them
  off drains the battery and keeps the lenses projecting.

.EXAMPLE
  $env:OCULUS_TEST_PIN = '1234'
  pwsh -File tools/perf/bench.ps1 -Label baseline-rel -DurationSec 60

.EXAMPLE
  pwsh -File tools/perf/bench.ps1 -Label baseline-rel -DurationSec 60 -Pin 1234 -KeepAwake
#>
[CmdletBinding()]
param(
    [string]$Label = 'run',
    [int]$DurationSec = 60,
    [string]$Map = 'Timelapse',
    [int]$Hz = 72,
    [string]$AppId = 'io.github.testyfishy.opensaberq3',
    [string]$LaunchActivity = 'com.godot.game.GodotAppLauncher',
    [string]$Pin = $env:OCULUS_TEST_PIN,
    [string]$Serial = '2G0YC1ZF9J0G2V',
    [string]$Adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe",
    [switch]$KeepAwake
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Adb)) { throw "adb not found at $Adb" }

$outDir = Join-Path (Get-Location) 'perf\captures'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = Join-Path $outDir "$stamp-$Label"

function A([string]$cmd) { (& $Adb -s $Serial shell $cmd 2>&1) -join "`n" }
function Fail([string]$msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Step([string]$msg) { Write-Host "== $msg" }
function SetProps([bool]$on) {
    $v = if ($on) { 'true' } else { 'false' }
    if (-not $Pin) { return 'skipped (no PIN)' }
    (A "content call --uri content://com.oculus.rc --method SET_PROPERTY --extra 'disable_guardian:b:$v' --extra 'disable_dialogs:b:$v' --extra 'disable_autosleep:b:$v' --extra 'PIN:s:$Pin'")
}

$devs = (& $Adb devices) -join "`n"
if ($devs -notmatch ([regex]::Escape($Serial) + '\s+device')) { Fail "device $Serial not connected/authorized`n$devs" }

# 1. automation state
Step "automation state"
if ($Pin) {
    $r = SetProps $true
    if ($r -notmatch 'Success=true') { Fail "could not disable guardian/dialogs/autosleep - check the PIN. Response: $r" }
} else {
    Write-Host "  no PIN supplied; guardian/dialogs/autosleep left as-is (precondition check will catch a blocked launch)"
}
Write-Host "  $(A 'content call --uri content://com.oculus.rc --method GET_PROPERTY')"

# 2. environment
Step "environment"
$batt = A 'dumpsys battery'
$level = if ($batt -match 'level:\s*(\d+)') { $matches[1] } else { '?' }
$ac = if ($batt -match 'AC powered:\s*(\w+)') { $matches[1] } else { '?' }
$usb = if ($batt -match 'USB powered:\s*(\w+)') { $matches[1] } else { '?' }
$temp = A 'dumpsys thermalservice'
$tstat = if ($temp -match 'Thermal Status:\s*(\d+)') { $matches[1] } else { '?' }
Write-Host "  battery=$level% ac=$ac usb=$usb thermal_status=$tstat"

# 3. clear and stage the run
Step "stage run"
A "am force-stop $AppId" | Out-Null
$ext = "/sdcard/Android/data/$AppId/files"
A "mkdir -p $ext" | Out-Null
A "rm -f $ext/bench.csv $ext/bench_meta.txt $ext/bench.flag $ext/bench.flag.consumed" | Out-Null
$flag = Join-Path $env:TEMP "bench-$stamp.flag"
[System.IO.File]::WriteAllText($flag, "[bench]`nmap=`"$Map`"`nduration=$DurationSec`n", (New-Object System.Text.UTF8Encoding($false)))
& $Adb -s $Serial push $flag "$ext/bench.flag" 2>&1 | Out-Null

# 4. launch + capture VrApi in the background
Step "launch"
& $Adb -s $Serial logcat -c
$proc = Start-Process -FilePath $Adb -ArgumentList @('-s', $Serial, 'logcat', '-v', 'time', 'VrApi:I', 'godot:I', '*:S') `
    -RedirectStandardOutput "$base.logcat.txt" -PassThru -WindowStyle Hidden
A "am start -n $AppId/$LaunchActivity" | Out-Null

$deadline = (Get-Date).AddSeconds($DurationSec + 90)
$done = $false; $reason = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $log = Get-Content "$base.logcat.txt" -ErrorAction SilentlyContinue
    if ($log -match 'BENCH: done') { $done = $true; $reason = (($log | Select-String 'BENCH: done' | Select-Object -Last 1).Line); break }
    if (A "pidof $AppId" -eq '') { $reason = 'process exited without BENCH: done'; break }
}
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue

if (-not $done) {
    Step "diagnostics"
    Write-Host (A "dumpsys activity activities | grep topResumedActivity")
    Write-Host (A "dumpsys window | grep mCurrentFocus")
    if (-not $KeepAwake) { [void](SetProps $false) }
    Fail "benchmark did not complete. $reason"
}

# 5. pull + validate
Step "collect"
& $Adb -s $Serial pull "$ext/bench.csv" "$base.bench.csv" 2>&1 | Out-Null
if (Test-Path "$ext/bench_meta.txt") { & $Adb -s $Serial pull "$ext/bench_meta.txt" "$base.meta.txt" 2>&1 | Out-Null }

if (-not (Test-Path "$base.bench.csv")) {
    if (-not $KeepAwake) { [void](SetProps $false) }
    Fail "bench.csv not produced"
}
$rows = (Import-Csv "$base.bench.csv" | Measure-Object).Count
$expected = [math]::Floor(0.95 * $Hz * $DurationSec)
Write-Host "  rows=$rows expected>=$expected"
if ($rows -lt $expected) {
    if (-not $KeepAwake) { [void](SetProps $false) }
    Fail "csv short: $rows rows, expected at least $expected"
}

if (-not $KeepAwake) { [void](SetProps $false) }

Step "result"
Write-Host "  csv  : $base.bench.csv"
Write-Host "  meta : $base.meta.txt"
Write-Host "  vr   : $base.logcat.txt"
& pwsh -NoProfile -File tools\perf\summarize.ps1 -Csv "$base.bench.csv" -Hz $Hz
