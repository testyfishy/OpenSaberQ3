param(
    [string]$Root,
    [string]$Out,
    [string]$Godot = "$env:LOCALAPPDATA\Godot\4.6.3\Godot_v4.6.3-stable_win64_console.exe"
)
# One Godot process per map: a native crash in one map cannot take the whole baseline with it.
Remove-Item $Out -Force -ErrorAction SilentlyContinue
$one = "$env:TEMP\toolchain\dump_one.txt"
$ok = 0; $failed = @()
foreach ($d in Get-ChildItem $Root -Directory | Sort-Object Name) {
    Remove-Item $one -Force -ErrorAction SilentlyContinue
    & $Godot --headless --path . res://tools/harness/map_dump.tscn -- $d.FullName $one *> $null
    if (-not ((Test-Path $one) -and ((Get-Item $one).Length -gt 0))) {
        # A Godot process occasionally dies on exit after writing nothing; retry once before
        # declaring the map a failure. A real loader regression fails both times.
        Remove-Item $one -Force -ErrorAction SilentlyContinue
        & $Godot --headless --path . res://tools/harness/map_dump.tscn -- $d.FullName $one *> $null
    }
    if ((Test-Path $one) -and ((Get-Item $one).Length -gt 0)) {
        Get-Content $one | Add-Content $Out
        $ok++
    } else {
        $failed += $d.Name
    }
}
"maps dumped: $ok  failed: $($failed.Count)"
if ($failed.Count -gt 0) { "failed ids: $($failed -join ', ')" }
