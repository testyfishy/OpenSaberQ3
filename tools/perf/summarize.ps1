<#
.SYNOPSIS
  Summarise a bench.csv produced by game/scripts/BenchmarkRunner.gd.

.DESCRIPTION
  Reports the criteria this project is judged on (spec SC-002/003/010/011) rather than a
  friendly average:

    - percentiles of wall-clock frame interval and process delta
    - frames over the 13.9 ms (72 Hz) / 11.1 ms (90 Hz) budget
    - spike clusters, because a missed frame in this workload is a spike, not a slow mean
    - whether the run was focused (a backgrounded app renders slower and would poison the numbers)

.EXAMPLE
  pwsh -File tools/perf/summarize.ps1 -Csv bench.csv -Hz 72
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Csv,
    [ValidateSet(72, 80, 90, 120)][int]$Hz = 72,
    [double]$SpikeMs = 0
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Csv)) { throw "not found: $Csv" }

$rows = Import-Csv $Csv
if (-not $rows -or $rows.Count -eq 0) { throw "empty csv: $Csv" }

$budgetMs = 1000.0 / $Hz

function Pct($values, $p) {
    if (-not $values -or $values.Count -eq 0) { return $null }
    $s = $values | Sort-Object
    $i = [math]::Floor($s.Count * $p)
    if ($i -ge $s.Count) { $i = $s.Count - 1 }
    return $s[$i]
}

# tolerate either column name the runner may emit
$deltaCol = 'delta_usec'
if (-not ($rows[0].PSObject.Properties.Name -contains $deltaCol)) { $deltaCol = 'frame_usec' }
if (-not ($rows[0].PSObject.Properties.Name -contains $deltaCol)) {
    throw "no delta column found; columns are: $($rows[0].PSObject.Properties.Name -join ', ')"
}

$deltaMs = @($rows | ForEach-Object { [double]$_.$deltaCol / 1000.0 })
$procMs = @()
if ($rows[0].PSObject.Properties.Name -contains 'process_delta_usec') {
    $procMs = @($rows | Where-Object { $_.process_delta_usec } | ForEach-Object { [double]$_.process_delta_usec / 1000.0 })
}

$over = @($deltaMs | Where-Object { $_ -gt $budgetMs })
$focusedVals = @()
if ($rows[0].PSObject.Properties.Name -contains 'focused') {
    $focusedVals = @($rows | ForEach-Object { $_.focused })
}

$mean = ($deltaMs | Measure-Object -Average).Average

"file        : $Csv"
"target      : $Hz Hz  (budget {0:N2} ms)" -f $budgetMs
"samples     : $($rows.Count)"
""
"wall frame interval (ms)"
"  mean      : {0:N2}   ({1:N1}% of budget)" -f $mean, (100.0 * $mean / $budgetMs)
"  p50       : {0:N2}" -f (Pct $deltaMs 0.50)
"  p95       : {0:N2}" -f (Pct $deltaMs 0.95)
"  p99       : {0:N2}   ({1:N1}% of budget)" -f (Pct $deltaMs 0.99), (100.0 * (Pct $deltaMs 0.99) / $budgetMs)
"  max       : {0:N2}" -f (($deltaMs | Measure-Object -Maximum).Maximum)
""
"over budget : {0} frames ({1:N2}%)" -f $over.Count, (100.0 * $over.Count / $deltaMs.Count)

if ($procMs.Count -gt 0) {
    ""
    "process delta (ms)"
    "  mean      : {0:N2}" -f ($procMs | Measure-Object -Average).Average
    "  p99       : {0:N2}" -f (Pct $procMs 0.99)
    "  max       : {0:N2}" -f (($procMs | Measure-Object -Maximum).Maximum)
}

if ($focusedVals.Count -gt 0) {
    $notFocused = @($focusedVals | Where-Object { $_ -eq '0' -or $_ -eq 'false' }).Count
    ""
    "focused     : {0} of {1} rows focused{2}" -f ($focusedVals.Count - $notFocused), $focusedVals.Count,
        $(if ($notFocused -gt 0) { "  <-- INVALID RUN: app lost focus, numbers are not comparable" } else { "" })
}

# spike clusters: consecutive frames over budget are one hitch, not N
$threshold = if ($SpikeMs -gt 0) { $SpikeMs } else { $budgetMs }
$clusters = @(); $current = 0
foreach ($ms in $deltaMs) {
    if ($ms -gt $threshold) { $current++ }
    elseif ($current -gt 0) { $clusters += $current; $current = 0 }
}
if ($current -gt 0) { $clusters += $current }

""
"hitches over {0:N2} ms : {1} clusters" -f $threshold, $clusters.Count
if ($clusters.Count -gt 0) {
    "  longest   : {0} consecutive frames" -f (($clusters | Measure-Object -Maximum).Maximum)
    "  sizes     : {0}" -f (($clusters | Sort-Object -Descending | Select-Object -First 12) -join ', ')
}

""
"verdict"
if ($over.Count -eq 0) { "  SC-010 (zero stale/over-budget frames): PASS" }
else { "  SC-010: FAIL - $($over.Count) frames over budget" }
"  SC-011 (p99 <= 75% of budget): {0}" -f $(if ((Pct $deltaMs 0.99) -le 0.75 * $budgetMs) { 'PASS' } else { 'FAIL' })
"  hard ceiling (max <= 90% of budget): {0}" -f $(if ((($deltaMs | Measure-Object -Maximum).Maximum) -le 0.90 * $budgetMs) { 'PASS' } else { 'FAIL' })
