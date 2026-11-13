# Runs every headless check and prints one line per check. Exit code 0 only if all pass.
#   pwsh tools/dev/check.ps1
param([string]$Godot = "$env:LOCALAPPDATA\Godot\4.6.3\Godot_v4.6.3-stable_win64_console.exe")

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $root

# scene, the line that must appear in its output
$checks = @(
    @('tools/harness/verify_parse.tscn',           'PARSECHECK files=\d+ bad=0'),
    @('tools/harness/verify_settings_schema.tscn', 'VERIFYSCHEMA keys=\d+ bad=0'),
    @('tools/harness/settings_roundtrip.tscn',     'SETTINGSTEST PASS'),
    @('tools/harness/verify_settings_panel.tscn',  'VERIFYPANEL nulls=0 range_bad=0'),
    @('tools/harness/verify_io_fixes.tscn',        'IOFIX PASS'),
    @('tools/harness/verify_hand_path.tscn',       'HANDPATH PASS'),
    @('tools/harness/verify_scoring.tscn',         'SCORING PASS'),
    @('tools/harness/rotation_probe.tscn',         'LANEPROBE local transform kept.*PASS'),
    @('tools/tests/test_chain_cut.tscn',           'CHAINGCUT PASS')
)
if (Test-Path 'tools/harness/verify_noodle.tscn') { $checks += ,@('tools/harness/verify_noodle.tscn', 'NOODLE PASS') }

$failed = 0
foreach ($c in $checks) {
    $out = & $Godot --headless --path . "res://$($c[0])" 2>&1 | Out-String
    $ok = $out -match $c[1]
    if (-not $ok) { $failed++ }
    '{0}  {1}' -f ($(if ($ok) { 'ok  ' } else { 'FAIL' })), $c[0]
    if (-not $ok) { ($out -split "`n" | Where-Object { $_ -match 'FAIL|SCRIPT ERROR|Parse Error' } | Select-Object -First 8) | ForEach-Object { "      $_" } }
}

# The game itself must boot with no script or engine errors (OpenXR-runtime lines are expected on a PC).
$boot = & $Godot --headless --path . --quit 2>&1 | Out-String
$bootErrors = ($boot -split "`n" | Where-Object { $_ -match '^(SCRIPT ERROR|ERROR)' -and $_ -notmatch 'OpenXR|RID alloc|Pages in use|resources still' })
if ($bootErrors.Count -gt 0) { $failed++ }
'{0}  boot ({1} errors)' -f ($(if ($bootErrors.Count -eq 0) { 'ok  ' } else { 'FAIL' })), $bootErrors.Count
$bootErrors | Select-Object -First 8 | ForEach-Object { "      $_" }

if ($failed -eq 0) { 'CHECKS PASS' } else { "CHECKS FAIL ($failed)" }
exit $failed
