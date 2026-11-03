# What a map actually asks the runtime to do.
#
# Prints, per map and difficulty: notes, bombs, walls, arcs, chains, duration, notes-per-second
# and the peak notes in a one-second window. Those are the inputs we can correlate against the
# per-map frame results, so "this map feels worse" becomes "this map has X".

param([string]$Root = "F:\Dev\OpenSaberQ3\game\data\maps\Songs")

function Read-MapInfo([string]$dir) {
    foreach ($n in @('Info.dat', 'info.dat')) {
        $p = Join-Path $dir $n
        if (Test-Path $p) { return Get-Content $p -Raw | ConvertFrom-Json }
    }
    return $null
}

function Get-Diffs($info) {
    $out = @()
    if ($info.PSObject.Properties.Name -contains '_difficultyBeatmapSets') {
        foreach ($set in $info._difficultyBeatmapSets) {
            foreach ($d in $set._difficultyBeatmaps) {
                $out += [pscustomobject]@{
                    name = $d._difficulty
                    file = $d._beatmapFilename
                    characteristic = $set._beatmapCharacteristicName
                    njs = $d._noteJumpMovementSpeed
                }
            }
        }
    } elseif ($info.PSObject.Properties.Name -contains 'difficultyBeatmaps') {
        foreach ($d in $info.difficultyBeatmaps) {
            $out += [pscustomobject]@{
                name = $d.difficulty
                file = $d.beatmapDataFilename
                characteristic = $d.characteristic
                njs = $d.noteJumpMovementSpeed
            }
        }
    }
    return $out
}

function Bpm($info) {
    if ($info.PSObject.Properties.Name -contains '_beatsPerMinute') { return [double]$info._beatsPerMinute }
    if ($info.PSObject.Properties.Name -contains 'audio') { return [double]$info.audio.bpm }
    return 120.0
}

"{0,-34} {1,-11} {2,6} {3,5} {4,6} {5,5} {6,6} {7,8} {8,7} {9,7}" -f `
    'map', 'difficulty', 'notes', 'bomb', 'walls', 'arcs', 'chains', 'duration', 'nps', 'peak/s'

foreach ($dir in (Get-ChildItem $Root -Directory)) {
    $info = Read-MapInfo $dir.FullName
    if (-not $info) { continue }
    $name = if ($info.PSObject.Properties.Name -contains '_songName') { $info._songName } else { $info.song.title }
    $bpm = Bpm $info
    foreach ($d in (Get-Diffs $info)) {
        if (-not $d.file) { continue }
        $p = Join-Path $dir.FullName $d.file
        if (-not (Test-Path $p)) { continue }
        $data = Get-Content $p -Raw | ConvertFrom-Json

        # v2 uses _notes/_obstacles/_sliders/_burstSliders; v3/v4 use colorNotes/obstacles/sliders/burstSliders
        $notes = if ($data.PSObject.Properties.Name -contains '_notes') { @($data._notes | Where-Object { $_ -and [int]$_._type -ne 3 }) } else { @($data.colorNotes) }
        $bombs = if ($data.PSObject.Properties.Name -contains '_notes') { @($data._notes | Where-Object { $_ -and [int]$_._type -eq 3 }) } else { @($data.bombNotes) }
        $walls = if ($data.PSObject.Properties.Name -contains '_obstacles') { @($data._obstacles) } else { @($data.obstacles) }
        $arcs = if ($data.PSObject.Properties.Name -contains '_sliders') { @($data._sliders) } else { @($data.sliders) }
        $chains = if ($data.PSObject.Properties.Name -contains '_burstSliders') { @($data._burstSliders) } else { @($data.burstSliders) }

        $beats = @()
        foreach ($n in $notes) {
            if ($null -eq $n) { continue }
            if ($n.PSObject.Properties.Name -contains '_time') { $beats += [double]$n._time } else { $beats += [double]$n.b }
        }
        $duration = if ($beats.Count -gt 0) { (($beats | Measure-Object -Maximum).Maximum / $bpm) * 60.0 } else { 0 }
        $nps = if ($duration -gt 0) { $notes.Count / $duration } else { 0 }
        # peak notes landing in any 1 s window
        $peak = 0
        if ($beats.Count -gt 0) {
            $sorted = @($beats | Sort-Object)
            $j = 0
            for ($i = 0; $i -lt $sorted.Count; $i++) {
                $windowEnd = $sorted[$i] + ($bpm / 60.0)   # one second in beats
                while ($j -lt $sorted.Count -and $sorted[$j] -le $windowEnd) { $j++ }
                $peak = [Math]::Max($peak, $j - $i)
            }
        }
        "{0,-34} {1,-11} {2,6} {3,5} {4,6} {5,5} {6,6} {7,8:N0} {8,7:N2} {9,7}" -f `
            $name.Substring(0, [Math]::Min(34, $name.Length)), ($d.name + '/' + $d.characteristic.Substring(0,[Math]::Min(3,$d.characteristic.Length))), `
            $notes.Count, $bombs.Count, $walls.Count, $arcs.Count, $chains.Count, $duration, $nps, $peak
    }
}
