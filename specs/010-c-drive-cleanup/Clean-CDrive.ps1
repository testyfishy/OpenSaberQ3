<#
.SYNOPSIS
  Clean C: junk and put OneDrive fully online-only.

.DESCRIPTION
  Phases:
    Junk      Temp items >24 h, rotated Godot logs, C:\tmp, CrashDumps,
              regenerable dev caches (tool-native commands), closed-browser caches.
    OneDrive  unpin every cloud placeholder (attrib +U -P) after a sync check.
    Report    show the attribute cross-tab and disk state.

  Spec: specs/010-c-drive-cleanup/spec.md
  Every deletion is logged to %TEMP%\c-cleanup-<stamp>.log (FR-007).
#>
[CmdletBinding()]
param(
  [ValidateSet('Junk','OneDrive','Report')]
  [string]$Phase = 'Report',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log   = Join-Path $env:TEMP "c-cleanup-$stamp.log"
function Write-Log {
  param([string]$Msg, [string]$Level = 'INFO')
  $line = "{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
  Write-Host $line
  Add-Content -LiteralPath $log -Value $line -Encoding utf8
}
function Get-PathGB {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $i = Get-Item -LiteralPath $Path -Force
  if ($i.PSIsContainer) {
    return [math]::Round((Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB, 3)
  }
  [math]::Round($i.Length / 1GB, 3)
}
function Remove-Safely {
  param([string]$Path)
  # rd/del never follow a junction; Remove-Item -Recurse can.
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  $i = Get-Item -LiteralPath $Path -Force
  if ($i.PSIsContainer) { cmd /c rd /s /q "$Path" 2>$null } else { cmd /c del /f /q "$Path" 2>$null }
  -not (Test-Path -LiteralPath $Path)
}
function Show-Disk {
  Get-Volume -DriveLetter C | ForEach-Object {
    Write-Log ("C: free {0:N2} GB of {1:N1} GB" -f ($_.SizeRemaining/1GB), ($_.Size/1GB))
    $script:cFree = [math]::Round($_.SizeRemaining/1GB, 2)
  }
}

Write-Log "phase=$Phase log=$log"
Show-Disk
$before = $script:cFree

# ------------------------------------------------------------------- Junk
if ($Phase -eq 'Junk') {
  $freed = 0.0; $skipped = @()

  # 1. Temp items older than 24 h
  Write-Log '--- Temp items older than 24 h ---'
  $cut = (Get-Date).AddHours(-24)
  $items = Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut -and $_.Name -notlike 'c-cleanup-*' }
  foreach ($it in $items) {
    $gb = Get-PathGB $it.FullName
    if (Remove-Safely $it.FullName) { $freed += $gb; Write-Log ("  deleted {0:N3} GB  {1}" -f $gb, $it.FullName) }
    else { $skipped += $it.FullName; Write-Log ("  in use, kept {0:N3} GB  {1}" -f $gb, $it.FullName) 'WARN' }
  }
  Write-Log ("Temp done: {0:N2} GB freed, {1} skipped" -f $freed, $skipped.Count)

  # 2. Godot rotated logs (never godot.log -- Godot is running)
  Write-Log '--- Godot rotated logs ---'
  $glog = "$env:APPDATA\Godot\app_userdata\Open Saber Q3\logs"
  if (Test-Path $glog) {
    foreach ($l in Get-ChildItem $glog -File -Filter 'godot*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'godot.log' }) {
      $gb = [math]::Round($l.Length/1GB, 3)
      if (Remove-Safely $l.FullName) { $freed += $gb; Write-Log ("  deleted {0:N3} GB  {1}" -f $gb, $l.Name) }
      else { Write-Log ("  locked, kept {0}" -f $l.Name) 'WARN' }
    }
  }
  if (Test-Path "$glog\godot.log") { Write-Log ('  kept live godot.log ({0:N2} GB)' -f (Get-PathGB "$glog\godot.log")) }

  # 3. C:\tmp and CrashDumps (older than 24 h, same rule)
  Write-Log '--- C:\tmp and CrashDumps ---'
  foreach ($dir in 'C:\tmp', "$env:LOCALAPPDATA\CrashDumps") {
    if (-not (Test-Path $dir)) { continue }
    foreach ($it in Get-ChildItem $dir -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut }) {
      $gb = Get-PathGB $it.FullName
      if (Remove-Safely $it.FullName) { $freed += $gb; Write-Log ("  deleted {0:N3} GB  {1}" -f $gb, $it.FullName) }
      else { Write-Log ("  kept (in use) {0}" -f $it.FullName) 'WARN' }
    }
  }

  # 4. Dev caches via their own commands (FR-011)
  Write-Log '--- dev caches (tool-native commands) ---'
  foreach ($cmd in @(
      @{ exe='npm';   args=@('cache','clean','--force'); name='npm' },
      @{ exe='pip';   args=@('cache','purge');           name='pip' },
      @{ exe='uv';    args=@('cache','clean');           name='uv'  })) {
    $exe = Get-Command $cmd.exe -ErrorAction SilentlyContinue
    if (-not $exe) { Write-Log ("  {0}: not installed, skipped" -f $cmd.name) 'WARN'; continue }
    try {
      $out = & $exe.Source @($cmd.args) 2>&1
      Write-Log ("  {0}: {1}" -f $cmd.name, (($out | Select-Object -Last 2) -join ' '))
    } catch { Write-Log ("  {0}: failed {1}" -f $cmd.name, $_.Exception.Message) 'WARN' }
  }

  # 5. Browser caches only when that browser is closed (FR-012)
  Write-Log '--- browser caches ---'
  $edge = @(Get-Process msedge -ErrorAction SilentlyContinue).Count
  if ($edge -gt 0) { Write-Log ("  Edge running ({0} processes): cache skipped" -f $edge) 'WARN' }
  else {
    foreach ($p in "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache") {
      if (Test-Path $p) { $gb = Get-PathGB $p; if (Remove-Safely $p) { $freed += $gb; Write-Log ("  deleted Edge cache {0:N2} GB  {1}" -f $gb, $p) } }
    }
  }
  $ff = @(Get-Process firefox -ErrorAction SilentlyContinue).Count
  if ($ff -gt 0) { Write-Log ("  Firefox running ({0} processes): cache skipped" -f $ff) 'WARN' }
  else {
    Get-ChildItem "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      foreach ($c in 'cache2') {
        $p = Join-Path $_.FullName $c
        if (Test-Path $p) { $gb = Get-PathGB $p; if (Remove-Safely $p) { $freed += $gb; Write-Log ("  deleted Firefox {0} {1:N2} GB" -f $c, $gb) } }
      }
    }
  }

  Write-Log ("JUNK TOTAL accounted: {0:N2} GB" -f $freed)
  Show-Disk
  Write-Log ("measured delta: {0:N2} GB" -f ($script:cFree - $before))
  return
}

# --------------------------------------------------------------- OneDrive
if ($Phase -eq 'OneDrive') {
  $od = "$env:OneDrive"
  if (-not $od -or -not (Test-Path $od)) { throw 'OneDrive folder not found' }
  $proc = @(Get-Process OneDrive -ErrorAction SilentlyContinue).Count
  if ($proc -eq 0) { throw 'OneDrive.exe is not running - cannot verify sync; abort (FR-005)' }

  $files = Get-ChildItem $od -Recurse -Force -File -ErrorAction SilentlyContinue
  $last = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  $mins = [math]::Round(((Get-Date) - $last).TotalMinutes, 1)
  Write-Log ("OneDrive: {0} files, newest write {1:N1} min ago" -f $files.Count, $mins)
  if ($mins -lt 15 -and -not $Force) {
    Write-Log ("refusing: a file changed {0:N1} min ago; sync may still be in flight. Re-run with -Force only after the tray says Up to date." -f $mins) 'ERROR'
    exit 4
  }

  $pre = $files | ForEach-Object { $a=[int]$_.Attributes; [pscustomobject]@{ Pinned=[bool]($a -band 0x80000); Reparse=[bool]($a -band 0x400); Dehydrated=[bool]($a -band 0x400000); GB=[math]::Round($_.Length/1GB,3) } }
  Write-Log 'pre-check cross-tab:'
  $pre | Group-Object { "pinned=$($_.Pinned) reparse=$($_.Reparse) dehydrated=$($_.Dehydrated)" } | ForEach-Object {
    Write-Log ("  {0}: {1} files, {2:N2} GB" -f $_.Name, $_.Count, (($_.Group | Measure-Object GB -Sum).Sum))
  }

  # Only cloud placeholders (ReparsePoint) may be unpinned (FR-010).
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CloudAttr {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern bool SetFileAttributes(string lpFileName, uint dwFileAttributes);
}
'@
  $PINNED = 0x80000; $UNPINNED = 0x100000
  $targets = @($files | Where-Object { ([int]$_.Attributes) -band 0x400 })
  Write-Log ("unpinning {0} cloud placeholders" -f $targets.Count)
  $done = 0; $failed = 0; $failList = New-Object System.Collections.Generic.List[string]
  foreach ($f in $targets) {
    $cur = [uint32][System.IO.File]::GetAttributes($f.FullName)
    $new = [uint32](($cur -band (-bnot [uint32]$PINNED)) -bor [uint32]$UNPINNED)
    if ($new -eq $cur -and ($cur -band $UNPINNED)) { $done++; continue }
    if ([CloudAttr]::SetFileAttributes($f.FullName, $new)) { $done++ }
    else { $failed++; $failList.Add($f.FullName) }
    if (($done + $failed) % 20000 -eq 0) { Write-Log ("  {0}/{1}" -f ($done + $failed), $targets.Count) }
  }
  Write-Log ("unpinned {0}; failed {1}" -f $done, $failed)
  if ($failed) { $failList | Set-Content (Join-Path $env:TEMP "c-cleanup-unpin-failures-$stamp.txt") -Encoding utf8; Write-Log ("failures listed in %TEMP%\c-cleanup-unpin-failures-{0}.txt" -f $stamp) 'WARN' }
  Show-Disk
  return
}

# ------------------------------------------------------------------ Report
$od = "$env:OneDrive"
if ($od -and (Test-Path $od)) {
  $files = Get-ChildItem $od -Recurse -Force -File -ErrorAction SilentlyContinue
  $tab = $files | ForEach-Object { $a=[int]$_.Attributes; [pscustomobject]@{ Pinned=[bool]($a -band 0x80000); Reparse=[bool]($a -band 0x400); Dehydrated=[bool]($a -band 0x400000); GB=[math]::Round($_.Length/1GB,3) } }
  Write-Log 'OneDrive cross-tab now:'
  $tab | Group-Object { "pinned=$($_.Pinned) reparse=$($_.Reparse) dehydrated=$($_.Dehydrated)" } | ForEach-Object {
    Write-Log ("  {0}: {1} files, {2:N2} GB" -f $_.Name, $_.Count, (($_.Group | Measure-Object GB -Sum).Sum))
  }
  $stillPinned = @($tab | Where-Object Pinned)
  Write-Log ("still pinned: {0} files, {1:N2} GB (non-reparse only is expected)" -f $stillPinned.Count, (($stillPinned | Measure-Object GB -Sum).Sum))
}
Show-Disk
