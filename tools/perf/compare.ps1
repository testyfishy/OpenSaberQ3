<#
.SYNOPSIS
  Compare a set of bench captures against a baseline and report medians with deltas.

.DESCRIPTION
  Reads the meta + csv + logcat triples written by tools/perf/bench.sh, computes the
  project's metrics per run, and reports the median across runs. A change is only a
  win if it beats the baseline median by more than the baseline spread.

.EXAMPLE
  pwsh -File tools/perf/compare.ps1 -Baseline 'perf/captures/base-*.meta.txt' -Candidate 'perf/captures/native-*.meta.txt'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Baseline,
    [Parameter(Mandatory = $true)][string]$Candidate,
    [int]$Hz = 72
)

$ErrorActionPreference = 'Stop'
$period = 1000.0 / $Hz

function Pct($v, $p) {
    if (-not $v -or $v.Count -eq 0) { return $null }
    $s = @($v | Sort-Object); $i = [math]::Floor($s.Count * $p)
    if ($i -ge $s.Count) { $i = $s.Count - 1 }
    return $s[$i]
}

function Get-Runs([string]$pattern) {
    $metas = Get-ChildItem $pattern -ErrorAction SilentlyContinue | Sort-Object Name
    $runs = @()
    foreach ($m in $metas) {
        $base = $m.FullName -replace '\.meta\.txt$', ''
        $csv = "$base.bench.csv"
        if (-not (Test-Path $csv)) { continue }
        $rows = Import-Csv $csv
        if ($rows.Count -eq 0) { continue }
        $ms = @($rows | ForEach-Object { [double]$_.delta_usec / 1000.0 })
        $phys = if ($rows[0].PSObject.Properties.Name -contains 'physics_usec') {
            @($rows | ForEach-Object { [double]$_.physics_usec / 1000.0 }) } else { @() }
        $proc = if ($rows[0].PSObject.Properties.Name -contains 'process_usec') {
            @($rows | ForEach-Object { [double]$_.process_usec / 1000.0 }) } else { @() }
        $log = "$base.logcat.txt"
        $app = @(); $stale = 0
        if (Test-Path $log) {
            foreach ($l in (Get-Content $log)) {
                if ($l -notmatch 'FPS=\d+/\d+') { continue }
                if ($l -match 'App=([\d.]+)ms') { $app += [double]$matches[1] }
                if ($l -match 'Stale=(\d+)') { $stale += [int]$matches[1] }
            }
        }
        $meta = @{}
        foreach ($l in (Get-Content $m.FullName)) { if ($l -match '^([^=]+)=(.*)$') { $meta[$matches[1]] = $matches[2] } }
        $runs += [pscustomobject]@{
            name      = $m.BaseName
            dropped   = @($ms | Where-Object { $_ -ge 1.5 * $period }).Count
            p50       = [math]::Round((Pct $ms 0.50), 2)
            p95       = [math]::Round((Pct $ms 0.95), 2)
            p99       = [math]::Round((Pct $ms 0.99), 2)
            appMean   = if ($app.Count) { [math]::Round(($app | Measure-Object -Average).Average, 2) } else { $null }
            appP95    = if ($app.Count) { [math]::Round((Pct $app 0.95), 2) } else { $null }
            physMean  = if ($phys.Count) { [math]::Round(($phys | Measure-Object -Average).Average, 2) } else { $null }
            physP95   = if ($phys.Count) { [math]::Round((Pct $phys 0.95), 2) } else { $null }
            procMean  = if ($proc.Count) { [math]::Round(($proc | Measure-Object -Average).Average, 2) } else { $null }
            stale     = $stale
            notes     = $meta['bot_score_right_notes']
            rt        = $meta['render_target_size']
            hz        = $meta['refresh_rate_after']
            msaa      = $meta['msaa_3d']
            tick      = $meta['physics_ticks_effective']
        }
    }
    return $runs
}

$b = Get-Runs $Baseline
$c = Get-Runs $Candidate
if (-not $b -or -not $c) { throw "need at least one run on each side" }

function Median($v) { if (-not $v) { return $null }; $s = @($v | Sort-Object); $s[[int][math]::Floor($s.Count / 2)] }

"baseline runs : $($b.Count)"
"candidate runs: $($c.Count)"
""
"{0,-16} {1,>10} {2,>10} {3,>10}" -f 'metric', 'base med', 'cand med', 'delta'
foreach ($k in 'dropped', 'p50', 'p95', 'p99', 'appMean', 'appP95', 'physMean', 'physP95', 'procMean', 'stale', 'notes') {
    $bv = Median @($b | ForEach-Object { $_.$k })
    $cv = Median @($c | ForEach-Object { $_.$k })
    if ($null -eq $bv -or $null -eq $cv) { continue }
    $d = if ($bv -ne 0) { 100.0 * ($cv - $bv) / [math]::Abs($bv) } else { 0 }
    "{0,-16} {1,10} {2,10} {3,9:N1}%" -f $k, $bv, $cv, $d
}
""
"configuration"
$b | ForEach-Object { "  base      : rt=$($_.rt) hz=$($_.hz) msaa=$($_.msaa) tick=$($_.tick)" }
$c | ForEach-Object { "  candidate : rt=$($_.rt) hz=$($_.hz) msaa=$($_.msaa) tick=$($_.tick)" }
""
"spread (baseline)"
foreach ($k in 'dropped', 'appMean', 'physP95') {
    $vals = @($b | ForEach-Object { $_.$k })
    "  {0,-10} min={1} max={2}" -f $k, ($vals | Measure-Object -Minimum).Minimum, ($vals | Measure-Object -Maximum).Maximum
}
