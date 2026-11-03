# Shared guard for every bench run.
#
# Three failures cost hours of measurements tonight:
#   1. the headset sleeps when the wear sensor says "unworn" and adb drops with it;
#   2. a long queue of heavy runs kept going regardless of the power state;
#   3. the device fallback picked ANY attached Android device. With the Quest asleep and a Pixel
#      phone paired for wireless debugging, the runners pushed flags to the phone and reported
#      "activity does not exist" - a silent wrong-target run, which is worse than a crash.
#
# So: only a device that identifies as a Quest is ever used.

$script:MinPercent = 20
$script:ResumePercent = 95
$script:Wireless = "192.168.86.250:5555"

function Write-Guard([string]$message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $message
    Add-Content -Path "$env:TEMP\toolchain\bench_guard.log" -Value $line -ErrorAction SilentlyContinue
    $line
}

# Returns the serial of an attached Quest, or $null. Never returns a phone.
function Get-QuestSerial($Adb) {
    $lines = @(& $Adb devices 2>&1 | Where-Object { $_ -match '\sdevice$' })
    foreach ($line in $lines) {
        $serial = ($line -split '\s+')[0]
        $model = (& $Adb -s $serial shell "getprop ro.product.model" 2>&1) -join ''
        if ($model -match 'Quest') { return $serial }
    }
    return $null
}

function Get-BatteryLevel($Adb, $Serial) {
    $out = & $Adb -s $Serial shell "dumpsys battery | grep level" 2>&1
    if ($out -match 'level:\s+(\d+)') { return [int]$Matches[1] }
    return -1
}

# Waits for a Quest, reconnecting adb and the known wireless address. Returns the serial or $null.
function Wait-DeviceReady($Adb, [int]$TimeoutSec = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $serial = Get-QuestSerial $Adb
        if ($serial) { return $serial }
        Write-Guard "no Quest attached; reconnecting adb and $($script:Wireless)"
        & $Adb reconnect offline 2>&1 | Out-Null
        & $Adb connect $script:Wireless 2>&1 | Out-Null
        Start-Sleep -Seconds 6
    }
    Write-Guard "no Quest came back within $TimeoutSec s"
    return $null
}

function Wait-ForBattery($Adb, $Serial) {
    $level = Get-BatteryLevel $Adb $Serial
    if ($level -lt 0) {
        Write-Guard "battery level unreadable; continuing"
        return
    }
    if ($level -ge $script:MinPercent) {
        Write-Guard "battery $level% - ok to run"
        return
    }
    Write-Guard "battery $level% is below $($script:MinPercent)%; pausing heavy runs"
    while ($true) {
        & $Adb -s $Serial shell "am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null 2>&1; svc power stayon true >/dev/null 2>&1" 2>&1 | Out-Null
        Start-Sleep -Seconds 60
        $level = Get-BatteryLevel $Adb $Serial
        if ($level -ge $script:ResumePercent) {
            Write-Guard "battery $level% - resuming heavy runs"
            return
        }
        Write-Guard "charging: $level%"
    }
}
