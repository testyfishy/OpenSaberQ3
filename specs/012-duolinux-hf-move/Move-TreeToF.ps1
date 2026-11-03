<#
.SYNOPSIS
  Move a tree from C: to F:\Dev and leave a junction. Phased and verified.

.DESCRIPTION
  Phases: Copy -> Verify -> Switch -> Delete.
  Verification is source-driven: every source regular file must exist at the
  destination with equal size and sha256. Destination extras are listed and
  expected to be zero (LX symlinks are excluded by /XJ and recorded separately).

  Spec: specs/012-duolinux-hf-move/spec.md
#>
[CmdletBinding()]
param(
  [ValidateSet('Copy','Verify','Switch','Delete','Status')]
  [string]$Phase = 'Status',
  [Parameter(Mandatory)][string]$Source,
  [Parameter(Mandatory)][string]$Destination,
  [string]$WorkDir = "$env:TEMP\duolinux-move",
  [switch]$GitTests,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $WorkDir ("{0}-{1}.log" -f $Phase.ToLower(), $stamp)
$Name = Split-Path -Leaf $Source

function Write-Log {
  param([string]$Msg, [string]$Level = 'INFO')
  $line = "{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
  Write-Host $line
  Add-Content -LiteralPath $log -Value $line -Encoding utf8
}
function FreeGB { [math]::Round((Get-Volume -DriveLetter C).SizeRemaining/1GB, 2) }
function Get-Hash([string]$p) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $fs = [System.IO.File]::OpenRead($p); try { [Convert]::ToHexString($sha.ComputeHash($fs)) } finally { $fs.Dispose() } }
  finally { $sha.Dispose() }
}
function Get-Files([string]$root) {
  Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }
}

Write-Log "phase=$Phase source=$Source destination=$Destination"
Write-Log ("C: free {0:N2} GB" -f (FreeGB))

# ------------------------------------------------------------------ Copy
if ($Phase -eq 'Copy') {
  if (-not (Test-Path -LiteralPath $Source)) { throw "source missing: $Source" }
  if ((Test-Path -LiteralPath $Destination) -and -not $Force) { throw "destination exists: $Destination (use -Force to resume)" }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $rcLog = Join-Path $WorkDir ("robocopy-{0}-{1}.log" -f $Name, $stamp)
  # Direct invocation: PowerShell quotes native-command arguments that contain spaces.
  & robocopy.exe $Source $Destination '/E' '/COPY:DAT' '/DCOPY:T' '/XJ' '/R:0' '/W:0' '/MT:16' '/XF' '*.sock' '/NFL' '/NDL' '/NP' "/LOG:$rcLog" | Out-Null
  $code = $LASTEXITCODE
  Write-Log ("robocopy exit {0} (log {1})" -f $code, $rcLog)
  if ($code -ge 8) { throw "robocopy exit $code is >= 8: hard stop (FR-012)" }

  # recreate junctions/symlinks that have a LinkType (none expected here)
  $rp = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue | Where-Object { $_.LinkType })
  Write-Log ("reparse points with LinkType: {0}" -f $rp.Count)
  foreach ($r in $rp) {
    $rel = [System.IO.Path]::GetRelativePath($Source, $r.FullName)
    $dst = Join-Path $Destination $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    $t = @($r.Target)[0]
    try {
      if ($r.LinkType -eq 'Junction') { New-Item -ItemType Junction -Path $dst -Target $t -ErrorAction Stop | Out-Null }
      else { New-Item -ItemType SymbolicLink -Path $dst -Target $t -ErrorAction Stop | Out-Null }
      Write-Log "  recreated $rel"
    } catch { cmd.exe /c mklink /J "$dst" "$t" | Out-Null; Write-Log "  recreated (mklink) $rel" 'WARN' }
  }
  # how many untyped reparse points (LX symlinks) did robocopy leave out?
  $lxSrc = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue | Where-Object { -not $_.LinkType }).Count
  $lxDst = @(Get-ChildItem -LiteralPath $Destination -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue | Where-Object { -not $_.LinkType }).Count
  Write-Log ("untyped reparse points (LX symlinks): source={0} dest={1}" -f $lxSrc, $lxDst)
  Write-Log ("destination files: {0}" -f @(Get-Files $Destination).Count)
  return
}

# ---------------------------------------------------------------- Verify
if ($Phase -eq 'Verify') {
  $t0 = Get-Date
  $srcFiles = @(Get-Files $Source)
  $dstMap = @{}
  foreach ($f in (Get-Files $Destination)) { $dstMap[[System.IO.Path]::GetRelativePath($Destination, $f.FullName)] = $f }
  Write-Log ("source files {0}; destination files {1}" -f $srcFiles.Count, $dstMap.Count)
  $missing = New-Object System.Collections.Generic.List[string]
  $mismatch = New-Object System.Collections.Generic.List[string]
  $n = 0
  foreach ($f in $srcFiles) {
    $n++
    $rel = [System.IO.Path]::GetRelativePath($Source, $f.FullName)
    if (-not $dstMap.ContainsKey($rel)) { $missing.Add($rel); continue }
    $d = $dstMap[$rel]
    if ($d.Length -ne $f.Length) { $mismatch.Add("$rel size $($f.Length) -> $($d.Length)"); continue }
    if ((Get-Hash $f.FullName) -ne (Get-Hash $d.FullName)) { $mismatch.Add("$rel sha256") }
    if ($n % 1000 -eq 0) { Write-Log ("  checked {0}/{1}" -f $n, $srcFiles.Count) }
  }
  $extras = @($dstMap.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Source $_)) })
  Write-Log ("missing={0} mismatched={1} extras={2}" -f $missing.Count, $mismatch.Count, $extras.Count)
  if ($missing.Count) { $missing | Set-Content (Join-Path $WorkDir "missing-$Name.txt") -Encoding utf8; Write-Log 'MISSING FILES - do not switch' 'ERROR' }
  if ($mismatch.Count) { $mismatch | Set-Content (Join-Path $WorkDir "mismatch-$Name.txt") -Encoding utf8; Write-Log 'HASH/SIZE MISMATCH - do not switch' 'ERROR' }
  if ($extras.Count) { $extras | Set-Content (Join-Path $WorkDir "extras-$Name.txt") -Encoding utf8; Write-Log ("extras listed in extras-{0}.txt" -f $Name) 'WARN' }
  $dur = (Get-Date) - $t0
  if ($missing.Count -or $mismatch.Count) { Write-Log ("VERIFY FAILED in {0}" -f $dur.ToString('hh\:mm\:ss')) 'ERROR'; exit 2 }
  Write-Log ("VERIFY OK in {0} (extras allowed only if listed)" -f $dur.ToString('hh\:mm\:ss'))
  return
}

# ---------------------------------------------------------------- Switch
if ($Phase -eq 'Switch') {
  if ((Get-Item -LiteralPath $Source -Force).LinkType) { throw "$Source is already a reparse point" }
  $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Source\*" })
  if ($procs.Count) { throw 'processes hold files in the source' }
  $old = "$Source.moved-$stamp"
  Write-Log "renaming -> $old"
  Rename-Item -LiteralPath $Source -NewName (Split-Path -Leaf $old) -ErrorAction Stop
  try {
    New-Item -ItemType Junction -Path $Source -Target $Destination -ErrorAction Stop | Out-Null
    $tests = [ordered]@{
      'junction resolves' = { (Get-Item -LiteralPath $Source -Force).LinkType -eq 'Junction' }
      'root lists'        = { @(Get-ChildItem -LiteralPath $Source -Force).Count -gt 0 }
      'sample hash equal' = {
        $s = Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1
        if (-not $s) { return $false }
        $rel = [System.IO.Path]::GetRelativePath($Source, $s.FullName)
        (Get-Hash $s.FullName) -eq (Get-Hash (Join-Path $Destination $rel))
      }
    }
    if ($GitTests) {
      $tests['git status'] = {
        $null = & git -C $Source status --porcelain 2>&1
        if ($LASTEXITCODE -ne 0) {
          $msg = (& git -C $Source status 2>&1) -join ' '
          if ($msg -match 'dubious ownership') {
            & git config --global --add safe.directory $Source | Out-Null
            & git -C $Source status --porcelain 2>&1 | Out-Null
          }
        }
        $LASTEXITCODE -eq 0
      }
      $tests['git remote'] = { ((& git -C $Source remote -v 2>&1) -join "`n") -match 'duolinux' }
    }
    $fails = @()
    foreach ($k in $tests.Keys) {
      try { $ok = [bool](& $tests[$k]) } catch { $ok = $false }
      Write-Log ("  test {0}: {1}" -f $k, $(if ($ok) { 'PASS' } else { 'FAIL' }))
      if (-not $ok) { $fails += $k }
    }
    if ($fails.Count) { throw "tests failed: $($fails -join ', ')" }
    Set-Content -LiteralPath (Join-Path $WorkDir "switch-$Name.json") -Value (@{ old = $old; source = $Source; destination = $Destination; at = (Get-Date).ToString('o') } | ConvertTo-Json) -Encoding utf8
    Write-Log 'SWITCH OK'
    return
  } catch {
    Write-Log ("switch failed: {0} - rolling back" -f $_.Exception.Message) 'ERROR'
    if ((Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue).LinkType) { cmd.exe /c rmdir "$Source" | Out-Null }
    if (Test-Path -LiteralPath $old) { Rename-Item -LiteralPath $old -NewName (Split-Path -Leaf $Source) }
    exit 3
  }
}

# ---------------------------------------------------------------- Delete
if ($Phase -eq 'Delete') {
  $sw = Join-Path $WorkDir "switch-$Name.json"
  if (-not (Test-Path $sw)) { throw "no switch-$Name.json: switch not verified" }
  $old = (Get-Content $sw -Raw | ConvertFrom-Json).old
  if (-not (Test-Path -LiteralPath $old)) { throw "old copy missing: $old" }
  if ((Get-Item -LiteralPath $Source -Force).LinkType -ne 'Junction') { throw "$Source is not the junction; refusing" }
  foreach ($j in @(Get-ChildItem -LiteralPath $old -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)) { cmd.exe /c rmdir "$($j.FullName)" 2>$null | Out-Null }
  cmd.exe /c rd /s /q "$old"
  Write-Log ("old copy still present: {0}" -f (Test-Path -LiteralPath $old))
  Write-Log ("C: free {0:N2} GB" -f (FreeGB))
  return
}

# ---------------------------------------------------------------- Status
Write-Log ("source exists {0}; is link: {1}" -f (Test-Path $Source), (if (Test-Path $Source) { (Get-Item $Source -Force).LinkType } else { 'n/a' }))
Write-Log ("destination exists {0}" -f (Test-Path $Destination))
Write-Log ("C: free {0:N2} GB" -f (FreeGB))
