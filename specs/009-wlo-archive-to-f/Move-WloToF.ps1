<#
.SYNOPSIS
  Move C:\WLO-Revival to F:\Dev\WLO-RI and leave a junction behind.

.DESCRIPTION
  Phased, because a 51 GB / 162k-file copy to a USB HDD is long and each
  checkpoint must be inspectable before the next destructive step.

    Inventory  record every reparse point (kind + absolute target) and the
               regular-file counts/bytes. Read-only.
    Copy       robocopy /E /XJ (junctions excluded), recreate the junctions
               one by one, verify the reparse inventory matches.
    Verify     file count, total bytes, sha256 of every regular file, and a
               second robocopy /L diff against the source. Refuses on any gap.
    Switch     rename C:\WLO-Revival -> *.moved-<stamp>, create the junction,
               test reads/git/venv through it; rolls back on failure.
    Delete     remove the *.moved-<stamp> tree (junctions first, never followed).
    Status     print what phase the machine is in.

  Spec: specs/009-wlo-archive-to-f/spec.md
#>
[CmdletBinding()]
param(
  [ValidateSet('Inventory','Copy','Junctions','Verify','Switch','Delete','Status')]
  [string]$Phase = 'Status',
  [string]$Source      = 'C:\WLO-Revival',
  [string]$Destination = 'F:\Dev\WLO-RI',
  [string]$WorkDir     = 'F:\WLO-Revival\moved\_wlo-move',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $WorkDir ("{0}-{1}.log" -f $Phase.ToLower(), $stamp)

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = "{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
  Write-Host $line
  Add-Content -LiteralPath $log -Value $line -Encoding utf8
}

function Get-ReparseInventory {
  param([string]$Root)
  $items = Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue -Attributes ReparsePoint
  foreach ($i in $items) {
    $kind = if ($i.LinkType -eq 'Junction') { 'Junction' }
            elseif ($i.LinkType -eq 'SymbolicLink') { if ($i.PSIsContainer) { 'DirSymlink' } else { 'FileSymlink' } }
            elseif (-not $i.LinkType) { 'Socket' }
            else { $i.LinkType }
    $target = if ($i.Target) { @($i.Target)[0] } else { $null }
    [pscustomobject]@{
      RelPath  = [System.IO.Path]::GetRelativePath($Root, $i.FullName)
      Kind     = $kind
      Target   = $target
      IsDir    = [bool]$i.PSIsContainer
    }
  }
}

function Get-FileManifest {
  param([string]$Root, [switch]$WithHash)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
      Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
      ForEach-Object {
        $o = [ordered]@{
          RelPath   = [System.IO.Path]::GetRelativePath($Root, $_.FullName)
          Length    = $_.Length
          WriteUtc  = $_.LastWriteTimeUtc.Ticks
        }
        if ($WithHash) {
          try {
            $fs = [System.IO.File]::OpenRead($_.FullName)
            try { $o.Sha256 = [Convert]::ToHexString($sha.ComputeHash($fs)) }
            finally { $fs.Dispose() }
          } catch { $o.Sha256 = 'ERROR:' + $_.Exception.Message }
        }
        [pscustomobject]$o
      }
  } finally { $sha.Dispose() }
}

function Restore-ReparsePoints {
  param($ReparsePoints, [string]$DestRoot)
  $made = 0; $failed = @()
  foreach ($r in ($ReparsePoints | Sort-Object { ($_.RelPath -split '\\').Count })) {
    $destPath = Join-Path $DestRoot $r.RelPath
    if ($r.Kind -eq 'Socket') { Write-Log "  skip unix socket $($r.RelPath)" 'WARN'; continue }
    if (Test-Path -LiteralPath $destPath) { Write-Log "  already present $($r.RelPath)" 'WARN'; continue }
    $parent = Split-Path -Parent $destPath
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    try {
      switch ($r.Kind) {
        'Junction'    { New-Item -ItemType Junction     -Path $destPath -Target $r.Target -ErrorAction Stop | Out-Null }
        'DirSymlink'  { New-Item -ItemType SymbolicLink -Path $destPath -Target $r.Target -ErrorAction Stop | Out-Null }
        'FileSymlink' { New-Item -ItemType SymbolicLink -Path $destPath -Target $r.Target -ErrorAction Stop | Out-Null }
        default       { throw "unknown reparse kind $($r.Kind)" }
      }
      $made++
    } catch {
      # New-Item refuses a target that does not exist; mklink /J accepts it.
      # Three junctions in this tree are dangling on purpose and must stay dangling.
      & cmd.exe /c mklink /J "$destPath" "$($r.Target)" | Out-Null
      if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $destPath)) {
        Write-Log ("  recreated dangling {0} (target missing)" -f $r.RelPath) 'WARN'
        $made++
      } else {
        $failed += $r.RelPath
        Write-Log ("  FAILED {0}: {1}" -f $r.RelPath, $_.Exception.Message) 'ERROR'
      }
    }
  }
  Write-Log ("recreated {0}; failures {1}" -f $made, $failed.Count)
  if ($failed.Count) { $failed | Set-Content (Join-Path $WorkDir 'junction-failures.txt') -Encoding utf8 }
  $destRp = @(Get-ReparseInventory -Root $DestRoot | Where-Object Kind -ne 'Socket')
  $srcRp  = @($ReparsePoints | Where-Object Kind -ne 'Socket')
  Write-Log ("reparse check: source(non-socket)={0} dest={1}" -f $srcRp.Count, $destRp.Count)
  $srcSet = $srcRp | ForEach-Object { "$($_.RelPath)|$($_.Kind)|$($_.Target)" } | Sort-Object
  $dstSet = $destRp | ForEach-Object { "$($_.RelPath)|$($_.Kind)|$($_.Target)" } | Sort-Object
  $onlySrc = @(Compare-Object $srcSet $dstSet | Where-Object SideIndicator -eq '<=' | Select-Object -ExpandProperty InputObject)
  if ($onlySrc.Count) { $onlySrc | Set-Content (Join-Path $WorkDir 'reparse-only-in-source.txt') -Encoding utf8; Write-Log ("MISMATCH: {0} reparse points only in source" -f $onlySrc.Count) 'ERROR' }
  else { Write-Log 'reparse inventories match' }
}

function Show-DiskState {
  foreach ($l in 'C','F') {
    $v = Get-Volume -DriveLetter $l
    Write-Log ("{0}: free {1:N1} GB of {2:N1} GB" -f $l, ($v.SizeRemaining/1GB), ($v.Size/1GB))
  }
}

Write-Log "phase=$Phase source=$Source destination=$Destination"
Show-DiskState

# ---------------------------------------------------------------- Inventory
if ($Phase -eq 'Inventory') {
  if (-not (Test-Path -LiteralPath $Source)) { throw "source missing: $Source" }
  $rp = @(Get-ReparseInventory -Root $Source)
  $rp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkDir 'reparse.json') -Encoding utf8
  $files = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -File -ErrorAction SilentlyContinue |
             Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) })
  $bytes = ($files | Measure-Object -Property Length -Sum).Sum
  Write-Log ("reparse points: {0} ({1})" -f $rp.Count, (($rp | Group-Object Kind | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))
  Write-Log ("regular files: {0}, bytes: {1:N0} ({2:N2} GB)" -f $files.Count, $bytes, ($bytes/1GB))
  $rp | Group-Object Kind | ForEach-Object { Write-Log ("  {0}: {1}" -f $_.Name, $_.Count) }
  Write-Log 'inventory written to reparse.json'
  return
}

# --------------------------------------------------------------------- Copy
if ($Phase -eq 'Copy') {
  if (-not (Test-Path -LiteralPath $Source)) { throw "source missing: $Source" }
  if (Test-Path -LiteralPath $Destination) {
    if (-not $Force) { throw "destination already exists: $Destination (use -Force to continue a partial copy)" }
    Write-Log 'destination exists, continuing (robocopy is restartable)' 'WARN'
  }
  $invPath = Join-Path $WorkDir 'reparse.json'
  if (-not (Test-Path $invPath)) { throw 'run -Phase Inventory first (no reparse.json)' }
  $rp = Get-Content -LiteralPath $invPath -Raw | ConvertFrom-Json

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $rcLog = Join-Path $WorkDir ("robocopy-copy-{0}.log" -f $stamp)
  Write-Log "robocopy starting -> $rcLog"
  $args = @(
    $Source, $Destination,
    '/E','/COPY:DAT','/DCOPY:T','/XJ','/R:0','/W:0','/MT:16',
    '/XF','*.sock','/NFL','/NDL','/NP',
    "/LOG:$rcLog"
  )
  $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru
  Write-Log ("robocopy exit code {0}" -f $p.ExitCode)
  if ($p.ExitCode -ge 8) {
    # Exit 8 also fires on dangling junctions (three exist in this tree, pointing at
    # scratch\sandbox-boot, scratch\sandbox-out and scratch\thai-run, which are gone).
    # Downgrade to a warning only when our own parity check proves nothing is missing.
    $srcDirs = @(Get-ChildItem $Source -Recurse -Force -Directory -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }).Count
    $dstDirs = @(Get-ChildItem $Destination -Recurse -Force -Directory -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }).Count
    $srcFiles = @(Get-ChildItem $Source -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }).Count
    $dstFiles = @(Get-ChildItem $Destination -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }).Count
    Write-Log ("parity after exit {0}: dirs {1}/{2}, files {3}/{4}" -f $p.ExitCode, $srcDirs, $dstDirs, $srcFiles, $dstFiles) 'WARN'
    if ($srcDirs -ne $dstDirs -or $srcFiles -ne $dstFiles) { throw "robocopy failed with $($p.ExitCode) and parity does not match; see $rcLog" }
    Write-Log 'exit 8 accepted: parity matches (dangling junctions only)' 'WARN'
  }

  Restore-ReparsePoints -ReparsePoints $rp -DestRoot $Destination
  return
}

# ---------------------------------------------------------------- Junctions
if ($Phase -eq 'Junctions') {
  $invPath = Join-Path $WorkDir 'reparse.json'
  if (-not (Test-Path $invPath)) { throw 'run -Phase Inventory first (no reparse.json)' }
  if (-not (Test-Path -LiteralPath $Destination)) { throw "destination missing: $Destination" }
  $rp = Get-Content -LiteralPath $invPath -Raw | ConvertFrom-Json
  Restore-ReparsePoints -ReparsePoints $rp -DestRoot $Destination
  return
}

# ------------------------------------------------------------------- Verify
if ($Phase -eq 'Verify') {
  if (-not (Test-Path -LiteralPath $Destination)) { throw "destination missing: $Destination" }
  if (Test-Path -LiteralPath ($Source + '.moved-*')) { }
  $t0 = Get-Date
  Write-Log 'building source manifest + hashes'
  $srcM = @(Get-FileManifest -Root $Source -WithHash)
  Write-Log ("source: {0} files, {1:N2} GB" -f $srcM.Count, (($srcM | Measure-Object Length -Sum).Sum/1GB))
  Write-Log 'building destination manifest + hashes'
  $dstM = @(Get-FileManifest -Root $Destination -WithHash)
  Write-Log ("destination: {0} files, {1:N2} GB" -f $dstM.Count, (($dstM | Measure-Object Length -Sum).Sum/1GB))

  $fail = $false
  if ($srcM.Count -ne $dstM.Count) { Write-Log ("FILE COUNT MISMATCH: {0} vs {1}" -f $srcM.Count, $dstM.Count) 'ERROR'; $fail = $true }
  $sb = ($srcM | Measure-Object Length -Sum).Sum
  $db = ($dstM | Measure-Object Length -Sum).Sum
  if ($sb -ne $db) { Write-Log ("BYTE TOTAL MISMATCH: {0} vs {1}" -f $sb, $db) 'ERROR'; $fail = $true }

  $srcMap = @{}; foreach ($f in $srcM) { $srcMap[$f.RelPath] = $f }
  $missing = New-Object System.Collections.Generic.List[string]
  $mismatch = New-Object System.Collections.Generic.List[string]
  $checked = 0
  foreach ($f in $dstM) {
    $checked++
    if (-not $srcMap.ContainsKey($f.RelPath)) { $missing.Add($f.RelPath); continue }
    if ($srcMap[$f.RelPath].Sha256 -ne $f.Sha256) {
      $mismatch.Add(("{0}  src={1} dst={2}" -f $f.RelPath, $srcMap[$f.RelPath].Sha256, $f.Sha256))
    }
    if ($checked % 20000 -eq 0) { Write-Log ("  checked {0}/{1}" -f $checked, $dstM.Count) }
  }
  if ($missing.Count) { $missing | Set-Content (Join-Path $WorkDir 'missing-in-destination.txt') -Encoding utf8; Write-Log ("MISSING IN DEST: {0}" -f $missing.Count) 'ERROR'; $fail = $true }
  if ($mismatch.Count) { $mismatch | Set-Content (Join-Path $WorkDir 'hash-mismatches.txt') -Encoding utf8; Write-Log ("HASH MISMATCHES: {0}" -f $mismatch.Count) 'ERROR'; $fail = $true }
  Write-Log ("hashed and compared {0} files; missing={1} mismatched={2}" -f $checked, $missing.Count, $mismatch.Count)

  # Source unchanged during the copy?
  $dryLog = Join-Path $WorkDir ("robocopy-dryrun-{0}.log" -f $stamp)
  $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList @($Source,$Destination,'/L','/E','/XJ','/XF','*.sock','/NJH','/NFL','/NDL','/NP',"/LOG:$dryLog") -NoNewWindow -Wait -PassThru
  $summary = Get-Content -LiteralPath $dryLog -ErrorAction SilentlyContinue | Select-String -Pattern '^\s*(Files|Bytes|Dirs)\s*:' | ForEach-Object { $_.Line.Trim() }
  $summary | ForEach-Object { Write-Log "  dry-run $_" }
  $newOrChanged = Get-Content -LiteralPath $dryLog | Select-String -Pattern '^\s*(Newer|Older|Changed|\*EXTRA)' | Measure-Object
  if ($newOrChanged.Count -gt 0) { Write-Log ("DRY-RUN DIFFERENCES: {0} lines - source changed during copy" -f $newOrChanged.Count) 'ERROR'; $fail = $true }

  # Reparse inventory through both roots
  $srcRp = @(Get-ReparseInventory -Root $Source | Where-Object Kind -ne 'Socket')
  $dstRp = @(Get-ReparseInventory -Root $Destination | Where-Object Kind -ne 'Socket')
  $a = $srcRp | ForEach-Object { "$($_.RelPath)|$($_.Kind)|$($_.Target)" } | Sort-Object
  $b = $dstRp | ForEach-Object { "$($_.RelPath)|$($_.Kind)|$($_.Target)" } | Sort-Object
  $diff = @(Compare-Object $a $b)
  if ($diff.Count) { $diff | ForEach-Object { $_.ToString() } | Set-Content (Join-Path $WorkDir 'reparse-verify-diff.txt') -Encoding utf8; Write-Log ("REPARSE MISMATCH: {0}" -f $diff.Count) 'ERROR'; $fail = $true }
  else { Write-Log ("reparse inventories match ({0} junctions)" -f $dstRp.Count) }

  $dur = (Get-Date) - $t0
  Write-Log ("verify finished in {0}" -f $dur.ToString('hh\:mm\:ss'))
  if ($fail) { Write-Log 'VERIFY FAILED - C: untouched, do not switch' 'ERROR'; exit 2 }
  Write-Log 'VERIFY OK - safe to switch' 
  return
}

# ------------------------------------------------------------------- Switch
if ($Phase -eq 'Switch') {
  $oldPath = "$Source.moved-$stamp"
  if (-not (Test-Path -LiteralPath $Source)) { throw "source missing: $Source" }
  $item = Get-Item -LiteralPath $Source -Force
  if ($item.LinkType) { throw "$Source is already a reparse point ($($item.LinkType)); refusing" }
  if (-not (Test-Path -LiteralPath $Destination)) { throw "destination missing: $Destination" }

  $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Source\*" })
  if ($procs.Count) { $procs | Select-Object Id, ProcessName, Path | Format-Table | Out-String | Write-Host; throw 'processes hold files in the source; refusing' }

  Write-Log "renaming $Source -> $oldPath"
  Rename-Item -LiteralPath $Source -NewName (Split-Path -Leaf $oldPath) -ErrorAction Stop
  try {
    Write-Log "creating junction $Source -> $Destination"
    New-Item -ItemType Junction -Path $Source -Target $Destination -ErrorAction Stop | Out-Null

    $tests = [ordered]@{}
    $tests['junction resolves'] = { (Get-Item -LiteralPath $Source -Force).LinkType -eq 'Junction' }
    $tests['root lists']        = { @(Get-ChildItem -LiteralPath $Source -Force).Count -gt 10 }
    $tests['user WLO junction'] = { Test-Path -LiteralPath 'C:\Users\user\WLO\wlo-revival\Wlo.slnx' }
    $tests['sample byte-equal'] = {
      $a = Join-Path $Source 'lab-accounts.json'
      $b = Join-Path $Destination 'lab-accounts.json'
      (Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash
    }
    $tests['git status']        = {
      $out = & git -C (Join-Path $Source 'wlo-revival') status --porcelain 2>&1
      $LASTEXITCODE -eq 0
    }
    $tests['git worktree list'] = {
      $out = & git -C (Join-Path $Source 'wlo-revival') worktree list 2>&1
      ($LASTEXITCODE -eq 0) -and (($out -join "`n") -match 'wlo-lane2')
    }
    $tests['venv python']       = {
      $exe = Join-Path $Source 'telemetry-venv\Scripts\python.exe'
      if (-not (Test-Path -LiteralPath $exe)) { return $false }
      $v = & $exe -V 2>&1
      ($LASTEXITCODE -eq 0) -and ($v -match 'Python 3')
    }
    $tests['reparse count']     = {
      @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue -Attributes ReparsePoint).Count -ge 1450
    }

    $fails = @()
    foreach ($k in $tests.Keys) {
      try { $ok = [bool](& $tests[$k]) } catch { $ok = $false; Write-Log ("  test threw: {0}" -f $_.Exception.Message) 'WARN' }
      Write-Log ("  test {0}: {1}" -f $k, $(if ($ok) { 'PASS' } else { 'FAIL' }))
      if (-not $ok) { $fails += $k }
    }
    if ($fails.Count) {
      Write-Log ("TESTS FAILED: {0} - rolling back" -f ($fails -join ', ')) 'ERROR'
      cmd /c rmdir "$Source"
      Rename-Item -LiteralPath $oldPath -NewName 'WLO-Revival'
      Write-Log 'rolled back: source restored, no junction left' 'ERROR'
      exit 3
    }
    Set-Content -LiteralPath (Join-Path $WorkDir 'switch-complete.json') -Encoding utf8 -Value (@{
      oldPath = $oldPath; source = $Source; destination = $Destination; at = (Get-Date).ToString('o')
    } | ConvertTo-Json)
    Write-Log 'SWITCH OK - all tests passed'
    Show-DiskState
    return
  } catch {
    Write-Log ("switch error: {0}" -f $_.Exception.Message) 'ERROR'
    if ((Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue).LinkType) { cmd /c rmdir "$Source" }
    if (Test-Path -LiteralPath $oldPath) { Rename-Item -LiteralPath $oldPath -NewName 'WLO-Revival' }
    Write-Log 'rolled back' 'ERROR'
    exit 3
  }
}

# ------------------------------------------------------------------- Delete
if ($Phase -eq 'Delete') {
  $sw = Join-Path $WorkDir 'switch-complete.json'
  if (-not (Test-Path $sw)) { throw 'no switch-complete.json: switch has not been verified' }
  $oldPath = (Get-Content $sw -Raw | ConvertFrom-Json).oldPath
  if (-not (Test-Path -LiteralPath $oldPath)) { throw "old copy not found: $oldPath" }
  if ((Get-Item -LiteralPath $Source -Force).LinkType -ne 'Junction') { throw "$Source is not the junction; refusing to delete" }

  $rp = @(Get-ChildItem -LiteralPath $oldPath -Recurse -Force -ErrorAction SilentlyContinue -Attributes ReparsePoint)
  $junctions = @($rp | Where-Object { $_.LinkType -eq 'Junction' })
  Write-Log ("removing {0} junctions from the old copy first (never followed)" -f $junctions.Count)
  $n = 0
  foreach ($j in $junctions) {
    cmd /c rmdir "$($j.FullName)" 2>$null
    if ($LASTEXITCODE -eq 0) { $n++ }
  }
  Write-Log ("removed {0}/{1} junctions" -f $n, $junctions.Count)
  Write-Log "deleting $oldPath"
  $t0 = Get-Date
  cmd /c rd /s /q "$oldPath"
  $rc = $LASTEXITCODE
  Write-Log ("rd exit code {0} after {1}" -f $rc, ((Get-Date)-$t0).ToString('hh\:mm\:ss'))
  Write-Log ("old copy still present: {0}" -f (Test-Path -LiteralPath $oldPath))
  Show-DiskState
  return
}

# ------------------------------------------------------------------- Status
Write-Log "source exists: {0}" (Test-Path -LiteralPath $Source)
if (Test-Path -LiteralPath $Source) {
  $it = Get-Item -LiteralPath $Source -Force
  Write-Log ("source link: {0} -> {1}" -f $it.LinkType, ($it.Target -join ','))
}
Write-Log ("destination exists: {0}" -f (Test-Path -LiteralPath $Destination))
Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object { Write-Log ("  {0}  {1:N1} KB" -f $_.Name, ($_.Length/1KB)) }
