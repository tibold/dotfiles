# Get nushell onto this Windows machine, then hand over to install.nu.
#
# First time: unsigned scripts are blocked by default. Run this:
#   powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 [args]
# (ExecutionPolicy Bypass applies only to this one process; once PowerShell
# is configured to allow local scripts, .\bootstrap.ps1 will work directly.)
#
#   .\bootstrap.ps1                  bootstrap, then run the full install
#   .\bootstrap.ps1 --dry-run        bootstrap, then show what install.nu would do
#   .\bootstrap.ps1 --with claude    ... and install Claude Code first
#
# Every argument is passed through to install.nu.
#
# The Windows counterpart of bootstrap.sh, and as small: everything else lives
# in the nushell side where it can be read and tested. Written for Windows
# PowerShell 5.1, because that is all a fresh machine has -- pwsh 7 is one of
# the things install.nu installs.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

function Log($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Die($msg) { Write-Host "bootstrap: $msg" -ForegroundColor Red; exit 1 }

# Links need Developer Mode, or an elevated shell. Asking for admin rights to
# write into your own home directory would be the wrong trade, so without it
# the choice is to turn it on or to copy instead.
$devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($devMode -ne 1 -and -not ($args -contains '--copy')) {
    Die "Developer Mode is off, so links cannot be created without admin rights. Turn it on (Settings > System > For developers), or re-run with --copy."
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Die "winget is not installed -- install 'App Installer' from the Microsoft Store."
}

# winget does not update this session's PATH, so the known install location is
# tried before giving up on a nu that was installed a moment ago.
$nu = (Get-Command nu -ErrorAction SilentlyContinue).Source
$known = Join-Path $env:LOCALAPPDATA 'Programs\nu\bin\nu.exe'
if (-not $nu -and (Test-Path $known)) { $nu = $known }

if (-not $nu) {
    Log 'Installing nushell'
    winget install --exact --id Nushell.Nushell --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { Die "winget could not install nushell (exit $LASTEXITCODE)" }
    if (Test-Path $known) { $nu = $known } else { Die "nushell installed, but not where expected ($known) -- open a new shell and re-run." }
}

Log "Handing over to install.nu"

# PowerShell parses comma-separated args as arrays when invoked directly.
# Reconstruct them by joining array elements back with commas.
$pass = @(foreach ($a in $args) {
    if ($a -is [array]) { ($a | ForEach-Object { "$_" }) -join ',' } else { "$a" }
})

& $nu (Join-Path $repo 'install.nu') @pass
exit $LASTEXITCODE
