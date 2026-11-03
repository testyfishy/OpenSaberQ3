# Keeps the Quest awake and adb-reachable while the bench works.
#
# The headset sleeps on the WEAR sensor (battery was 100% when it kept dropping), so it must be
# told it is being worn. Two lessons are built in:
#
#   1. Resolve the device EVERY cycle. The first version addressed the USB serial only, so the
#      moment USB was unplugged (to use a stronger charger) nothing kept it awake and the headset
#      slept, taking the wireless adb endpoint with it.
#   2. Reconnect actively. If neither endpoint answers, try the known wireless address before
#      giving up, because a sleeping headset never reconnects on its own.

param(
    [int]$Hours = 12,
    [int]$IntervalSec = 3,
    [string]$UsbSerial = "2G0YC1ZF9J0G2V",
    [string]$Wireless = "192.168.86.250:5555"
)

$adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
$end = (Get-Date).AddHours($Hours)
$reconnects = 0

function Resolve-Target {
    param($Adb, $Usb, $Wifi)
    $list = (& $Adb devices 2>&1) -join "`n"
    if ($list -match [regex]::Escape($Usb) + '\s+device') { return $Usb }
    if ($list -match [regex]::Escape($Wifi) + '\s+device') { return $Wifi }
    return $null
}

while ((Get-Date) -lt $end) {
    $target = Resolve-Target -Adb $adb -Usb $UsbSerial -Wifi $Wireless
    if (-not $target) {
        $reconnects++
        & $adb reconnect offline 2>&1 | Out-Null
        & $adb connect $Wireless 2>&1 | Out-Null
        Start-Sleep -Seconds 5
        $target = Resolve-Target -Adb $adb -Usb $UsbSerial -Wifi $Wireless
    }
    if ($target) {
        & $adb -s $target shell "am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null 2>&1; svc power stayon true >/dev/null 2>&1" 2>&1 | Out-Null
    }
    Start-Sleep -Seconds $IntervalSec
}

"keep-awake finished after $Hours h, $reconnects reconnect attempts"
