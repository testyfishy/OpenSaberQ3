# Exports the release APK, validates it, and optionally installs and launches it on the Quest.
# Run it from your own terminal: the Android export does not work from a sandboxed tool shell.
#
#   pwsh tools/dev/build.ps1                     export only
#   pwsh tools/dev/build.ps1 -Bump               0.7.26 -> 0.7.27 (and versionCode + 1) first
#   pwsh tools/dev/build.ps1 -Bump -Install      ... then install on the headset
#   pwsh tools/dev/build.ps1 -Install -Launch    ... and start the game
#
# The APK goes to F:\Dev\BeepSaberBin\OpenSaber-v<version>.apk. Nothing is pushed or tagged.
param(
    [switch]$Bump,
    [switch]$Install,
    [switch]$Launch,
    [string]$Device = '',
    [string]$OutDir = 'F:\Dev\BeepSaberBin',
    [string]$Godot = "$env:LOCALAPPDATA\Godot\4.6.3\Godot_v4.6.3-stable_win64_console.exe",
    [string]$Adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $root
$package = 'io.github.testyfishy.opensaberq3'

$project = Get-Content project.godot -Raw
if ($project -notmatch 'config/version="(\d+)\.(\d+)\.(\d+)"') { throw 'No config/version in project.godot' }
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"

if ($Bump) {
    $next = "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
    $presets = Get-Content export_presets.cfg -Raw
    if ($presets -notmatch 'version/code=(\d+)') { throw 'No version/code in export_presets.cfg' }
    $code = [int]$Matches[1] + 1
    $presets = $presets -replace 'version/code=\d+', "version/code=$code" -replace 'version/name="[^"]+"', "version/name=`"$next`""
    [IO.File]::WriteAllText((Join-Path $root 'export_presets.cfg'), $presets)
    [IO.File]::WriteAllText((Join-Path $root 'project.godot'), ($project -replace 'config/version="[^"]+"', "config/version=`"$next`""))
    "BUILD bumped $version -> $next (versionCode $code)"
    $version = $next
}

$apk = Join-Path $OutDir "OpenSaber-v$version.apk"
$log = Join-Path $env:TEMP "opensaber_export_$version.log"
# A stale exported scene cache has shipped an old scene before: always start clean.
if (Test-Path '.godot\exported') { Remove-Item '.godot\exported' -Recurse -Force }
if (Test-Path $apk) { Remove-Item $apk -Force }
"BUILD exporting $version (this takes several minutes) ..."
& $Godot --headless --path . --export-release 'Oculus Quest (RELEASE)' $apk *> $log
if (-not (Test-Path $apk)) {
    Select-String -Path $log -Pattern 'What went wrong|ERROR: (?!.*OpenXR)' -Context 0, 3 | Select-Object -First 6 | ForEach-Object { $_.ToString() }
    throw "Export failed; full log: $log"
}

$aapt = Get-ChildItem "$env:LOCALAPPDATA\Android\build-tools" -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
$manifest = & $aapt dump xmltree --file AndroidManifest.xml $apk 2>&1 | Out-String
$okVersion = $manifest -match [regex]::Escape("versionName") -and $manifest -match [regex]::Escape("`"$version`"")
$okHands = $manifest -match 'com\.oculus\.permission\.HAND_TRACKING'
'BUILD apk {0}  {1:N1} MB  version {2}  hand-tracking {3}' -f $apk, ((Get-Item $apk).Length / 1MB), $(if ($okVersion) { 'ok' } else { 'MISMATCH' }), $(if ($okHands) { 'declared' } else { 'MISSING' })
if (-not $okVersion) { throw 'APK version does not match project.godot' }

if ($Install -or $Launch) {
    if (-not $Device) {
        # Several devices may be attached; pick the Quest.
        $Device = (& $Adb devices -l | Select-String 'Quest' | Select-Object -First 1) -replace '\s.*', ''
        if (-not $Device) { throw 'No Quest found by adb; pass -Device <serial>' }
    }
    if ($Install) { 'BUILD install: ' + ((& $Adb -s $Device install -r $apk 2>&1 | Select-Object -Last 1)) }
    if ($Launch) {
        & $Adb -s $Device shell am force-stop $package | Out-Null
        & $Adb -s $Device shell monkey -p $package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
        'BUILD launched on ' + $Device
    }
}
'BUILD DONE'
