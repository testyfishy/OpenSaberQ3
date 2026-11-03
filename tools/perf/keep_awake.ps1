# Keeps the Quest awake and adb-reachable while the bench works.
#
# The headset sleeps on the WEAR sensor, not on battery: 'dumpsys battery' reports level 100 and
# status 3 (discharging, "Weak Charger: true"), so it was never a flat battery. Between runs
# nothing broadcast prox_close, the headset decided it was unworn, slept, and USB/adb dropped
# with it.
#
# Run this in the background for the whole session. It reconnects adb if the device vanishes and
# re-broadcasts prox_close so the wear sensor never sees "unworn" for long.

param(
    [int]$Hours = 12,
    [int]$IntervalSec = 3,
    [string]$Device = "2G0YC1ZF9J0G2V"
)

$adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
$end = (Get-Date).AddHours($Hours)
$reconnects = 0

while ((Get-Date) -lt $end) {
    $list = (& $adb devices 2>&1) -join "`n"
    if ($list -notmatch [regex]::Escape($Device)) {
        $reconnects++
        & $adb reconnect offline 2>&1 | Out-Null
        Start-Sleep -Seconds 4
        $list = (& $adb devices 2>&1) -join "`n"
        if ($list -notmatch [regex]::Escape($Device)) {
            # Last resort: the wireless endpoint the headset advertises.
            $svc = (& $adb mdns services 2>&1 | Select-String 'Quest|_adb-tls-connect' | Select-Object -First 1)
            if ($svc -and $svc.Line -match '(\d+\.\d+\.\d+\.\d+:\d+)') {
                & $adb connect $Matches[1] 2>&1 | Out-Null
            }
        }
        Start-Sleep -Seconds 4
    }
    & $adb -s $Device shell "am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null 2>&1; svc power stayon true >/dev/null 2>&1" 2>&1 | Out-Null
    Start-Sleep -Seconds $IntervalSec
}

"keep-awake finished after $Hours h, $reconnects reconnect attempts"
