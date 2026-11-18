# One-time hardening of the release signing key. Run once on the machine that holds
# bin\release.keystore (the file is git-ignored and has never been committed).
#
# It keeps the SAME key, so new builds still install over old ones, and:
#   1. copies the keystore as it is to the private folder (backup, old password),
#   2. replaces the well-known password with a random one that is never printed,
#   3. stores the new password and a copy of the keystore in the private folder.
# tools\dev\build.ps1 reads the password from that folder and passes it to Godot through
# GODOT_ANDROID_KEYSTORE_RELEASE_* environment variables, so it is in no repository file.
#
# Back up the private folder somewhere safe: without the keystore and its password, no update
# can ever be installed over a published build.
param(
    [string]$Keystore = (Join-Path $PSScriptRoot '..\..\bin\release.keystore'),
    [string]$Private = (Join-Path $env:USERPROFILE '.opensaber-signing'),
    [string]$Alias = 'androiddebugkey',
    [string]$OldPassword = 'android'
)
$ErrorActionPreference = 'Stop'
$Keystore = (Resolve-Path $Keystore).Path
$secret = Join-Path $Private 'release-password.txt'
if (Test-Path $secret) { throw "Already set up: $secret exists. Nothing changed." }
$keytool = (Get-Command keytool).Source
New-Item -ItemType Directory -Force $Private | Out-Null
Copy-Item $Keystore (Join-Path $Private 'release.keystore.original-password') -Force

$chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
$bytes = [byte[]]::new(40); [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$new = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })

& $keytool -storepasswd -keystore $Keystore -storepass $OldPassword -new $new 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'keytool -storepasswd failed; the keystore is unchanged.' }
# JKS keeps a separate key password; PKCS12 does not (keytool then reports that and exits non-zero).
& $keytool -keypasswd -keystore $Keystore -alias $Alias -storepass $new -keypass $OldPassword -new $new 2>&1 | Out-Null
& $keytool -list -keystore $Keystore -storepass $new -alias $Alias 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Copy-Item (Join-Path $Private 'release.keystore.original-password') $Keystore -Force
    throw 'The keystore did not open with the new password; restored the original.'
}
[IO.File]::WriteAllText($secret, $new)
Copy-Item $Keystore (Join-Path $Private 'release.keystore') -Force
"SIGNING password replaced. Keystore copy and password are in $Private - back that folder up."
