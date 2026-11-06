param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("debris", "glow", "environment")]
    [string]$Feature,
    [int]$Duration = 60,
    [string]$Map = "ODDS",
    [int]$Diff = 5,
    [int]$Hz = 120,
    [string]$Tag = ""
)

# One A/B per feature, on the same map, bot and preset. See docs/v03-ab-plan.md.
#   debris      -> defaults vs visual_off="debris"
#   glow        -> glow=false vs glow=true (bench-only override)
#   environment -> environment="classic" vs environment="map"
#
# String values MUST be quoted: ConfigFile parses a bare identifier as a Variant and fails.
#
# Refuses to run below 40% battery: overnight runs must not strand the headset.

$ErrorActionPreference = "Stop"
if ($Tag -eq "") { $Tag = $Feature }
$perf = "render_scale=1.0`nmsaa=1`nfoveation=2"

$adb = "$env:LOCALAPPDATA\Android\platform-tools\adb.exe"
$level = [int]((& $adb -s 2G0YC1ZF9J0G2V shell "dumpsys battery | grep level" 2>&1) -replace '\D', '')
if ($level -lt 40) {
    throw "headset battery is ${level}%; refusing to run arms. Charge to 40% first."
}

switch ($Feature) {
    "debris" {
        $off = 'visual_off="debris"'
        $on = ""
    }
    "glow" {
        $off = "glow=false"
        $on = "glow=true"
    }
    "environment" {
        $off = 'environment="classic"'
        $on = 'environment="map"'
    }
}

& pwsh -NoProfile -File tools/perf/run-vrapi.ps1 -Name "$Tag-off" -Duration $Duration -Map $Map -Diff $Diff -Hz $Hz -Extra "$perf`n$off"
& pwsh -NoProfile -File tools/perf/run-vrapi.ps1 -Name "$Tag-on" -Duration $Duration -Map $Map -Diff $Diff -Hz $Hz -Extra "$perf`n$on"

python tools/perf/frame_stats.py "perf/captures/$Tag-off.bench.csv" "perf/captures/$Tag-on.bench.csv"
