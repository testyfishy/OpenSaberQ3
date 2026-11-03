param(
    [string]$Name,
    [string]$Extra = "",
    [int]$Duration = 45,
    [string]$Map = "ODDS",
    [int]$Diff = 5,
    [int]$Hz = 120
)

$adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
. "$env:TEMP\toolchain\bench_guard.ps1"

$d = Wait-DeviceReady -Adb $adb
if (-not $d) { throw "no Quest attached (only non-Quest devices are on adb)" }
$pkg = "io.github.testyfishy.opensaberq3"
$ext = "/sdcard/Android/data/$pkg/files"
Wait-ForBattery -Adb $adb -Serial $d

& $adb -s $d shell "am force-stop $pkg; am force-stop com.oculus.guardian; setprop debug.oculus.guardian_pause 1; rm -f $ext/bench.csv $ext/bench_meta.txt $ext/bench.flag $ext/bench.flag.consumed"

$flag = @"
[bench]
map="$Map"
difficulty_index=$Diff
duration=$Duration
refresh_hz=$Hz
$Extra

[bot]
enabled=true
miss_percent=0
sway=true
"@
$flagPath = "$env:TEMP\toolchain\$Name.flag"
$flag | Set-Content -Path $flagPath -Encoding utf8
& $adb -s $d push $flagPath "$ext/bench.flag" | Out-Null

# A push that silently fails leaves the PREVIOUS arm's flag on the device, so the run uses the
# wrong duration and the capture is mislabelled. That is how a 180 s request produced a 40 s
# capture. Read it back and refuse to continue on a mismatch.
$actual = (& $adb -s $d shell "cat $ext/bench.flag" 2>&1) -join "`n"
if ($actual -notmatch [regex]::Escape("duration=$Duration")) {
    throw "flag push did not land: expected duration=$Duration, device has '$actual'"
}

& $adb -s $d logcat -c
& $adb -s $d shell "am start -n $pkg/com.godot.game.GodotAppLauncher" | Out-Null

$job = Start-Job -ArgumentList $adb, $d -ScriptBlock {
    param($a, $dev)
    $i = 0
    while ($i -lt 90) {
        & $a -s $dev shell "am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null 2>&1" | Out-Null
        $i++
        Start-Sleep -Seconds 2
    }
}
Start-Sleep -Seconds ($Duration + 30)
Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue

& $adb -s $d pull "$ext/bench_meta.txt" "perf\captures\$Name.meta.txt" 2>&1 | Out-Null
& $adb -s $d pull "$ext/bench.csv" "perf\captures\$Name.bench.csv" 2>&1 | Out-Null
& $adb -s $d shell "am force-stop $pkg"

"=== $Name ==="
Get-Content "perf\captures\$Name.meta.txt" -ErrorAction SilentlyContinue |
    Select-String -Pattern 'samples|elapsed_s|refresh_rate_final|overrides|limit_s'
