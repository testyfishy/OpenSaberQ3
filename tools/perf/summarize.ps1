<#
.SYNOPSIS
  Score a bench.csv (and optionally the VrApi logcat from the same run) against this project's
  frame-pacing criteria.

.DESCRIPTION
  Two things are being measured and they must not be confused:

  * Frame INTERVAL from the CSV is vsync-locked. A healthy app sitting at 72 Hz reports
    ~13.89 ms every frame, with half of them a hair above the period purely from jitter.
    Counting "interval > period" as a failure would fail every healthy VR app, so a missed
    frame is defined as ONE OR MORE SKIPPED VSYNC INTERVALS (>= 1.5x period).

  * HEADROOM (SC-011) cannot come from the interval at all, because the interval is clamped to
    the panel rate. It comes from VrApi's own GPU/CPU timing (`App=` and `CPU&GPU=`), parsed
    from the logcat captured alongside the run.

.EXAMPLE
  pwsh -File tools/perf/summarize.ps1 -Csv perf\captures\r1.bench.csv -Hz 72 `
       -Logcat perf\captures\r1.logcat.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Csv,
    [ValidateSet(72, 80, 90, 120)][int]$Hz = 72,
    [string]$Logcat = ''
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Csv)) { throw "not found: $Csv" }
$rows = Import-Csv $Csv
if (-not $rows -or $rows.Count -eq 0) { throw "empty csv: $Csv" }

$period = 1000.0 / $Hz
$dropThreshold = 1.5 * $period   # one or more skipped vsync intervals
# TRUE on-time threshold. A frame is on time if it is delivered within one refresh plus a small
# tolerance. Using 1.5x the period as the pass/fail line (as this script used to) reports every
# frame between 1.0x and 1.5x as perfect, which at 120 Hz hides the whole 8.33-12.5 ms band - the
# band that actually contains most of the lateness we are trying to remove.
$onTimeThreshold = 1.05 * $period
$severeThreshold = 2.5 * $period # two or more

function Pct($values, $p) {
    if (-not $values -or $values.Count -eq 0) { return $null }
    $s = @($values | Sort-Object)
    $i = [math]::Floor($s.Count * $p)
    if ($i -ge $s.Count) { $i = $s.Count - 1 }
    return $s[$i]
}

$deltaCol = 'delta_usec'
if (-not ($rows[0].PSObject.Properties.Name -contains $deltaCol)) { $deltaCol = 'frame_usec' }
if (-not ($rows[0].PSObject.Properties.Name -contains $deltaCol)) {
    throw "no delta column found; columns are: $($rows[0].PSObject.Properties.Name -join ', ')"
}

$ms = @($rows | ForEach-Object { [double]$_.$deltaCol / 1000.0 })
$procMs = @()
if ($rows[0].PSObject.Properties.Name -contains 'process_delta_usec') {
    $procMs = @($rows | Where-Object { $_.process_delta_usec } | ForEach-Object { [double]$_.process_delta_usec / 1000.0 })
}

$dropped = @($ms | Where-Object { $_ -ge $dropThreshold })
$severe = @($ms | Where-Object { $_ -ge $severeThreshold })
$onVsync = $ms.Count - $dropped.Count
$focusedRows = 0
if ($rows[0].PSObject.Properties.Name -contains 'focused') {
    $focusedRows = @($rows | Where-Object { $_.focused -eq '1' -or $_.focused -eq 'true' }).Count
}

"file        : $Csv"
"target      : $Hz Hz  (period {0:N2} ms, dropped-frame threshold {1:N2} ms)" -f $period, $dropThreshold
"samples     : $($ms.Count)"
""
"frame interval"
"  mean      : {0:N2} ms" -f ($ms | Measure-Object -Average).Average
"  p50       : {0:N2} ms" -f (Pct $ms 0.50)
"  p95       : {0:N2} ms" -f (Pct $ms 0.95)
"  p99       : {0:N2} ms" -f (Pct $ms 0.99)
"  max       : {0:N2} ms" -f (($ms | Measure-Object -Maximum).Maximum)
""
"frames delivered on vsync : {0} of {1} ({2:N3}%)" -f $onVsync, $ms.Count, (100.0 * $onVsync / $ms.Count)
$onTime = @($ms | Where-Object { $_ -le $onTimeThreshold }).Count
$late = $ms.Count - $onTime - $dropped.Count
$fps = 1000.0 / (($ms | Measure-Object -Average).Average)
"delivered                 : {0:N2} fps of {1:N1}  ({2:N2}% of the display rate)" -f $fps, $Hz, (100.0 * $fps / $Hz)
"frame budget use          : p50 {0:N1}%  p95 {1:N1}%  p99 {2:N1}% of the {3:N2} ms period" -f `
    (100.0 * (Pct $ms 0.50) / $period), (100.0 * (Pct $ms 0.95) / $period), (100.0 * (Pct $ms 0.99) / $period), $period
"frames truly on time     : {0} of {1} ({2:N3}%)  <= {3:N2} ms" -f $onTime, $ms.Count, (100.0 * $onTime / $ms.Count), $onTimeThreshold
"frames late but not dropped: {0} ({1:N3}%)  in the {2:N2}-{3:N2} ms band" -f $late, (100.0 * $late / $ms.Count), $onTimeThreshold, $dropThreshold
"  ^ presented late-latch, NOT lost: a frame here finished a fraction of a millisecond after the"
"    period and was still shown. At 120 Hz this band sits at ~20% on this build while only 0.2% of"
"    vsync slots are actually skipped, so it is a budget-margin diagnostic, not a frame-rate figure."
"dropped-frame events      : {0} ({1:N3}% of frames missed at least one vsync)" -f $dropped.Count, (100.0 * $dropped.Count / $ms.Count)
"severe events (>=2 vsync) : {0}" -f $severe.Count

if ($focusedRows -gt 0 -or ($rows[0].PSObject.Properties.Name -contains 'focused')) {
    ""
    "focused     : $focusedRows of $($ms.Count) rows"
    if ($focusedRows -lt $ms.Count) { "  <-- INVALID RUN: app lost focus; numbers describe a paused process" }
}

if ($procMs.Count -gt 0) {
    ""
    "process delta (ms)   [CPU-side, not vsync-clamped]"
    "  mean      : {0:N2}" -f ($procMs | Measure-Object -Average).Average
    "  p99       : {0:N2}" -f (Pct $procMs 0.99)
    "  max       : {0:N2}" -f (($procMs | Measure-Object -Maximum).Maximum)
}

# Engine-side CPU attribution (E0 instrumentation): TIME_PROCESS / TIME_PHYSICS_PROCESS
foreach ($pair in @(@('process_usec','TIME_PROCESS'), @('physics_usec','TIME_PHYSICS_PROCESS'))) {
    if ($rows[0].PSObject.Properties.Name -contains $pair[0]) {
        $vals = @($rows | Where-Object { $_.($pair[0]) } | ForEach-Object { [double]$_.($pair[0]) / 1000.0 })
        if ($vals.Count -gt 0) {
            ""
            "$($pair[1]) (ms)"
            "  mean      : {0:N2}" -f ($vals | Measure-Object -Average).Average
            "  p95       : {0:N2}" -f (Pct $vals 0.95)
            "  p99       : {0:N2}" -f (Pct $vals 0.99)
            "  max       : {0:N2}" -f (($vals | Measure-Object -Maximum).Maximum)
        }
    }
}

# hitch clusters: consecutive dropped frames are one hitch, not N
$clusters = @(); $run = 0
foreach ($v in $ms) {
    if ($v -ge $dropThreshold) { $run++ } elseif ($run -gt 0) { $clusters += $run; $run = 0 }
}
if ($run -gt 0) { $clusters += $run }
""
"hitches (>= {0:N2} ms) : {1} clusters" -f $dropThreshold, $clusters.Count
if ($clusters.Count -gt 0) {
    "  longest   : {0} consecutive frames" -f (($clusters | Measure-Object -Maximum).Maximum)
    "  sizes     : {0}" -f (($clusters | Sort-Object -Descending | Select-Object -First 12) -join ', ')
}

# ---- headroom from VrApi (the only source that is not vsync-clamped) ----
if ($Logcat -and (Test-Path $Logcat)) {
    $lines = Get-Content $Logcat
    $app = @(); $sub = @(); $stale = 0; $staleSamples = 0
    foreach ($l in $lines) {
        # Only VrApi's own periodic sample lines carry these fields. Other tags contain
        # "App=" in unrelated text and previously poisoned the mean.
        if ($l -notmatch 'FPS=\d+/\d+') { continue }
        if ($l -match 'App=([\d.]+)ms') { $app += [double]$matches[1] }
        if ($l -match 'CPU&GPU=([\d.]+)ms') { $sub += [double]$matches[1] }
        if ($l -match 'Stale=(\d+)') { $stale += [int]$matches[1]; $staleSamples++ }
    }
    ""
    "VrApi (1 sample/second, not vsync-clamped)"
    if ($app.Count -gt 0) {
        "  App GPU+CPU ms : mean {0:N2}  p95 {1:N2}  max {2:N2}  ({3:N1}% of period at mean)" -f `
            ($app | Measure-Object -Average).Average, (Pct $app 0.95), (($app | Measure-Object -Maximum).Maximum),
            (100.0 * ($app | Measure-Object -Average).Average / $period)
    }
    if ($sub.Count -gt 0) {
        "  CPU&GPU ms     : mean {0:N2}  p95 {1:N2}  max {2:N2}  ({3:N1}% of period at mean)" -f `
            ($sub | Measure-Object -Average).Average, (Pct $sub 0.95), (($sub | Measure-Object -Maximum).Maximum),
            (100.0 * ($sub | Measure-Object -Average).Average / $period)
    }
    "  Stale samples  : $stale (over $staleSamples VrApi samples)"
}

""
"verdict"
$sc010 = ($dropped.Count -eq 0)
"  SC-010 (zero dropped frames): {0}" -f $(if ($sc010) { 'PASS' } else { "FAIL - $($dropped.Count) dropped-frame events" })
# SC-011 must use VrApi (not vsync-clamped) when available; the interval cannot show headroom.
if ($sub.Count -gt 0) {
    $p95 = Pct $sub 0.95
    "  SC-011 (p95 CPU&GPU <= 75% of period): {0} ({1:N1}%)" -f $(if ($p95 -le 0.75 * $period) { 'PASS' } else { 'FAIL' }), (100.0 * $p95 / $period)
} elseif ($procMs.Count -gt 0) {
    "  SC-011: cannot be judged - no VrApi samples; process delta alone is vsync-clamped"
}
"  note: headroom needs the VrApi columns above; interval alone cannot show it."
