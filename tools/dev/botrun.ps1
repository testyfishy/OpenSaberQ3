# Plays a song on the headset with the built-in bot and prints the result: no hands needed.
#   pwsh tools/dev/botrun.ps1 -Map "ODDS" -DifficultyIndex 5 -Seconds 45
# The headset can stay on the desk; its proximity sensor is overridden for the run and restored.
param(
    [string]$Map = 'ODDS',
    [int]$DifficultyIndex = 0,
    [int]$Seconds = 45,
    [int]$MissPercent = 0,
    [string]$Device = '',
    [string]$Adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
)
$package = 'io.github.testyfishy.opensaberq3'
$files = "/sdcard/Android/data/$package/files"
if (-not $Device) { $Device = (& $Adb devices -l | Select-String 'Quest' | Select-Object -First 1) -replace '\s.*', '' }
if (-not $Device) { throw 'No Quest found by adb; pass -Device <serial>' }

$flag = Join-Path $env:TEMP 'bench.flag'
@"
[bench]
map = "$Map"
difficulty_index = $DifficultyIndex
duration = $Seconds
max_duration = $($Seconds + 40)

[bot]
enabled = true
miss_percent = $MissPercent
sway = false
"@ | Set-Content $flag -Encoding ascii
& $Adb -s $Device push $flag "$files/bench.flag" | Out-Null
& $Adb -s $Device shell am broadcast -a com.oculus.vrpowermanager.prox_close | Out-Null
& $Adb -s $Device shell am force-stop $package | Out-Null
& $Adb -s $Device logcat -c
& $Adb -s $Device shell monkey -p $package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
"BOTRUN started '$Map' difficulty $DifficultyIndex for $Seconds s ..."
$deadline = (Get-Date).AddSeconds($Seconds + 120)
do {
    Start-Sleep -Seconds 5
    $log = & $Adb -s $Device logcat -d -s godot:V | Out-String
} until ($log -match 'BENCH: exit=' -or (Get-Date) -gt $deadline)
& $Adb -s $Device shell am broadcast -a com.oculus.vrpowermanager.automation_disable | Out-Null

$lines = $log -split "`n"
$errors = @($lines | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Node not found' })
$lines | Where-Object { $_ -match 'MAP motion|BENCH: (map=|no map|samples|frame_us|exit)|BOT:|FAIL:' } | ForEach-Object { ($_ -replace '^.*godot\s*:\s*', '  ') }
(& $Adb -s $Device shell cat "$files/bench_meta.txt") | Where-Object { $_ -match 'bot_score' } | ForEach-Object { "  $_" }
"BOTRUN script errors: $($errors.Count)"
$errors | Select-Object -First 6 | ForEach-Object { "  $_" }
if ($errors.Count -eq 0 -and $log -match 'BENCH: exit=duration') { 'BOTRUN PASS' } else { 'BOTRUN FAIL'; exit 1 }
