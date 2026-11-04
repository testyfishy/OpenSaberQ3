param(
    [int]$Duration = 60,
    [string]$Map = "ODDS",
    [int]$Diff = 5,
    [int]$Hz = 120,
    [string]$Tag = "bloom"
)

# Bloom A/B. The glow removal was reasoned from the tiled-GPU mechanism but never measured on its
# own, so this runs the same arm twice: once with glow off, once with the bench-only `glow=true`
# override. Both arms pin the shipped Performance preset so the comparison is about glow, not
# resolution.
#
# Output: perf/captures/<tag>-off.* and <tag>-on.*, plus a printed table.

$ErrorActionPreference = "Stop"
$perf = "render_scale=1.0`nmsaa=1`nfoveation=2"

& pwsh -NoProfile -File tools/perf/run-vrapi.ps1 -Name "$Tag-off" -Duration $Duration -Map $Map -Diff $Diff -Hz $Hz -Extra $perf
& pwsh -NoProfile -File tools/perf/run-vrapi.ps1 -Name "$Tag-on" -Duration $Duration -Map $Map -Diff $Diff -Hz $Hz -Extra "$perf`nglow=true"

python tools/perf/frame_stats.py "perf/captures/$Tag-off.bench.csv" "perf/captures/$Tag-on.bench.csv"
