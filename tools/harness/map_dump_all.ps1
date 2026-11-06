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
    # A crash mid-map leaves a non-empty but truncated file, so require the END sentinel.
    # The process dies intermittently on some maps (thread teardown), so allow three attempts.
    $complete = $false
    for ($attempt = 0; $attempt -lt 3 -and -not $complete; $attempt++) {
        if ($attempt -gt 0) {
            Remove-Item $one -Force -ErrorAction SilentlyContinue
            & $Godot --headless --path . res://tools/harness/map_dump.tscn -- $d.FullName $one *> $null
        }
        $complete = (Test-Path $one) -and ((Get-Content $one -Tail 1 -ErrorAction SilentlyContinue) -eq "END")
    }
    if ($complete) {
        Get-Content $one | Add-Content $Out
        $ok++
    } else {
        $failed += $d.Name
    }
}
"maps dumped: $ok  failed: $($failed.Count)"
if ($failed.Count -gt 0) { "failed ids: $($failed -join ', ')" }
