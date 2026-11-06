param(
    [string]$Name,
    [string]$Extra = "",
    [int]$Duration = 40,
    [string]$Map = "ODDS",
    [int]$Diff = 5,
    [int]$Hz = 120,
    [int]$MissPercent = 0
)

$adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
. "$env:TEMP\toolchain\bench_guard.ps1"

$d = Wait-DeviceReady -Adb $adb
if (-not $d) { throw "no Quest attached (only non-Quest devices are on adb)" }
$pkg = "io.github.testyfishy.opensaberq3"
$ext = "/sdcard/Android/data/$pkg/files"
Wait-ForBattery -Adb $adb -Serial $d

& $adb -s $d shell "am force-stop $pkg; am force-stop com.oculus.guardian; setprop debug.oculus.guardian_pause 1; rm -f $ext/bench.csv $ext/bench_meta.txt $ext/bench.flag $ext/bench.flag.consumed $ext/audio_probe.wav $ext/audio_probe_sfx.wav"

@"
[bench]
map="$Map"
difficulty_index=$Diff
duration=$Duration
refresh_hz=$Hz
$Extra

[bot]
enabled=true
miss_percent=$MissPercent
sway=true
"@ | Set-Content -Path "$env:TEMP\toolchain\$Name.flag" -Encoding utf8
& $adb -s $d push "$env:TEMP\toolchain\$Name.flag" "$ext/bench.flag" | Out-Null

$actual = (& $adb -s $d shell "cat $ext/bench.flag" 2>&1) -join "`n"
if ($actual -notmatch [regex]::Escape("duration=$Duration")) {
    throw "flag push did not land: expected duration=$Duration, device has '$actual'"
}

$logpath = "$env:TEMP\toolchain\$Name.vrapi.log"
$logjob = Start-Job -ArgumentList $adb, $logpath, $d -ScriptBlock {
    param($a, $p, $dev)
    & $a -s $dev logcat -s VrApi:I > $p
}
& $adb -s $d shell "am start -n $pkg/com.godot.game.GodotAppLauncher" | Out-Null
$awake = Start-Job -ArgumentList $adb, $d -ScriptBlock {
    param($a, $dev)
    $i = 0
    while ($i -lt 90) {
        & $a -s $dev shell "am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null 2>&1" | Out-Null
        $i++
        Start-Sleep -Seconds 2
    }
}
Start-Sleep -Seconds ($Duration + 32)
Stop-Job $logjob, $awake -ErrorAction SilentlyContinue; Remove-Job $logjob, $awake -Force -ErrorAction SilentlyContinue
& $adb -s $d pull "$ext/bench_meta.txt" "perf\captures\$Name.meta.txt" 2>&1 | Out-Null
& $adb -s $d pull "$ext/bench.csv" "perf\captures\$Name.bench.csv" 2>&1 | Out-Null
& $adb -s $d shell "am force-stop $pkg"

# Gameplay only: the menu runs at 72 Hz, and including those samples produced misleading medians.
$lines = @(Get-Content $logpath -ErrorAction SilentlyContinue | Where-Object { $_ -match 'FPS=1[12]\d/' })
$gpu = @(); $app = @(); $fps = @()
foreach ($l in $lines) {
    if ($l -match 'FPS=(\d+)/') { $fps += [int]$Matches[1] }
    if ($l -match 'App=([\d.]+)ms') { $app += [double]$Matches[1] }
    if ($l -match 'GPU%=([\d.]+)') { $gpu += [double]$Matches[1] }
}
function Med($a) { if ($a.Count -eq 0) { return 0 }; $s = @($a | Sort-Object); $s[[int][Math]::Floor(($s.Count - 1) * 0.5)] }
"=== $Name ($($lines.Count) XR samples) ==="
"fps median {0:N0}  App median {1:N2} ms  GPU% median {2:N2}" -f (Med $fps), (Med $app), (Med $gpu)
