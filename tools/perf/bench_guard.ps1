# Shared guard for every bench run.
#
# Two failures cost hours of measurements tonight:
#   1. the headset sleeps when the wear sensor says "unworn" and adb drops with it;
#   2. a long queue of heavy runs kept going regardless of the power state.
#
# The battery was never the cause (level 100, status 3, "Weak Charger: true"), but the rule is
# still worth having: stop heavy runs below 20%, keep the device awake, wait for it to trickle
# back up, then resume. Resume threshold is deliberately high because these runs are 3-6 minutes
# each and a run that starts at 30% can end in the middle of a thermal/battery event.

$script:MinPercent = 20
$script:ResumePercent = 95
$script:LogPath = "$env:TEMP\toolchain\bench_guard.log"

function Write-Guard([string]$message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $message
    Add-Content -Path $script:LogPath -Value $line -ErrorAction SilentlyContinue
    $line
}

function Get-BatteryLevel($Adb, $Device) {
    $out = & $Adb -s $Device shell "dumpsys battery | grep level" 2>&1
    if ($out -match 'level:\s*(\d+)') { return [int]$Matches[1] }
    return -1
}

function Wait-DeviceReady($Adb, $Device, [int]$TimeoutSec = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $list = (& $Adb devices 2>&1) -join "`n"
        if ($list -match [regex]::Escape($Device) -and $list -match 'device\s*$') {
            return $true
        }
        Write-Guard "device not present; reconnecting adb"
        & $Adb reconnect offline 2>&1 | Out-Null
        Start-Sleep -Seconds 6
    }
    Write-Guard "device did not come back within $TimeoutSec s"
    return $false
}

function Wait-ForBattery($Adb, $Device) {
    $level = Get-BatteryLevel $Adb $Device
    if ($level -lt 0) {
        Write-Guard "battery level unreadable; continuing"
        return
    }
    if ($level -ge $script:MinPercent) {
        Write-Guard "battery $level% - ok to run"
        return
    }
    Write-Guard "battery $level% is below $($script:MinPercent)%; pausing heavy runs"
    # Keep the wear sensor quiet while charging so the device does not sleep into a deep state.
    while ($true) {
        & $Adb -s $Device shell "am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null 2>&1; svc power stayon true >/dev/null 2>&1" 2>&1 | Out-Null
        Start-Sleep -Seconds 60
        $level = Get-BatteryLevel $Adb $Device
        if ($level -ge $script:ResumePercent) {
            Write-Guard "battery $level% - resuming heavy runs"
            return
        }
        Write-Guard "charging: $level%"
    }
}
