# Keeps the Quest reachable over ADB during a long unattended run.
#   pwsh tools/dev/adb_keepalive.ps1              runs for 10 hours, then exits
#   pwsh tools/dev/adb_keepalive.ps1 -Hours 4
#
# Every 45 seconds it sends the headset a no-op command, which keeps the USB debugging link in
# use. If the headset stops answering it asks ADB to reconnect, and after three misses in a row
# it restarts the ADB server. It changes nothing on the headset: no settings, no wake lock.
# State changes and an hourly battery reading go to the console and to a log file.
param(
    [double]$Hours = 10,
    [int]$IntervalSeconds = 45,
    [string]$Device = '',
    [string]$Adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe",
    [string]$Log = (Join-Path $env:TEMP 'adb_keepalive.log')
)

function Note([string]$text) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $text
    $line
    Add-Content -Path $Log -Value $line
}

function Find-Quest {
    (& $Adb devices -l 2>$null | Select-String 'Quest' | Select-Object -First 1) -replace '\s.*', ''
}

if (-not $Device) { $Device = Find-Quest }
Note "keepalive started for $Hours h, device '$Device', log $Log"
$until = (Get-Date).AddHours($Hours)
$misses = 0
$wasUp = $true
$lastBattery = Get-Date '2000-01-01'

while ((Get-Date) -lt $until) {
    if (-not $Device) { $Device = Find-Quest }
    $state = if ($Device) { (& $Adb -s $Device get-state 2>$null) } else { '' }
    $alive = $false
    if ($state -eq 'device') {
        $alive = ((& $Adb -s $Device shell echo ok 2>$null) -join '').Trim() -eq 'ok'
    }
    if ($alive) {
        if (-not $wasUp) { Note "headset is back after $misses missed checks" }
        $wasUp = $true
        $misses = 0
        if (((Get-Date) - $lastBattery).TotalMinutes -ge 60) {
            $lastBattery = Get-Date
            $level = ((& $Adb -s $Device shell dumpsys battery 2>$null | Select-String '^\s*level:') -replace '\D', '')
            Note "ok, battery $level%"
        }
    }
    else {
        $misses++
        if ($wasUp) { Note "headset not answering (state '$state')" }
        $wasUp = $false
        if ($misses % 3 -eq 0) {
            Note 'restarting the ADB server'
            & $Adb kill-server 2>$null | Out-Null
            & $Adb start-server 2>$null | Out-Null
            $Device = Find-Quest
        }
        else {
            & $Adb reconnect offline 2>$null | Out-Null
        }
    }
    Start-Sleep -Seconds $IntervalSeconds
}
Note 'keepalive finished'
