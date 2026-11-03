# Runs the same 120 Hz capture across several maps so "performance holds" becomes a table
# instead of a single map's opinion.
#
# Each map is a fresh app launch, 90 s, shipped default settings, bot playing.
#
# Maps arrive as ONE comma-separated string: `pwsh -File ... -Maps "a,b,c"`. A PowerShell array
# parameter cannot be passed through `-File` (the comma list arrives as a single string), which
# silently produced a matrix of one invalid map name the first time this ran.

param(
    [int]$Duration = 90,
    [string]$Maps = "ODDS,Empires,Void Hornet,Gloom,Somewhere Out There,HEARTATTACK"
)

$list = $Maps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
if ($list.Count -eq 0) { throw "no maps given" }
Write-Output "matrix over $($list.Count) maps: $($list -join ' | ')"

foreach ($m in $list) {
    $slug = ($m -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower()
    Write-Output "=== $m ==="
    & pwsh -NoProfile -File "$env:TEMP\toolchain\run-arm.ps1" `
        -Name "map-$slug" -Extra "max_duration=300" -Duration $Duration -Map $m -Diff 5 -Hz 120
}
