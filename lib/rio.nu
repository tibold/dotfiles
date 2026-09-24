# Rio on Windows: installed for this user from its GitHub release, with a
# current ConPTY beside it.
#
# Two problems, one fix. Rio's only Windows installer is a per-machine MSI --
# Program Files, the system PATH, HKLM -- so installing or upgrading it needs
# an administrator. And Rio talks to its shell through ConPTY, which it loads
# with a bare LoadLibraryW("conpty.dll"): from beside rio.exe when there is one
# there, otherwise the copy built into Windows. That built-in copy predates
# image passthrough (ConPTY 1.22), so Sixel, iTerm2 and Kitty images never
# reach Rio -- nvim's snacks.image shows nothing -- until a current
# conpty.dll and the OpenConsole.exe it starts sit next to rio.exe. The MSI
# does not ship them, and a winget upgrade put back the MSI's own files.
#
# So Rio is not a winget package here. Its release also publishes the same
# rio.exe on its own ("portable" in the asset name only -- the binary is
# byte-for-byte the MSI's), and that goes into %LOCALAPPDATA%\Programs\Rio,
# where per-user applications live, with ConPTY from Microsoft's own NuGet
# package beside it. Nothing needs elevation, and every run brings both up to
# their latest stable release, which is the job winget upgrade used to do.
#
# Everything downloaded is checked before it is put in place: rio.exe against
# the checksums.txt in its release (Rio is not code-signed), the
# ConPTY files by their Authenticode signature, which must be Microsoft's. A
# file that fails either is not installed.

use log.nu
use fallback.nu

export const REPO = "raphamorim/rio"

# Release asset per CPU architecture, as $nu.os-info.arch names it.
export const ASSETS = {
  x86_64: "rio-portable-x86_64.exe"
  aarch64: "rio-portable-aarch64.exe"
}

export const CONPTY_PACKAGE = "microsoft.windows.console.conpty"

# Where each file sits inside the NuGet package. The package spells the
# architecture two ways, win-x64 for the DLL and x64 for OpenConsole.
export const CONPTY_FILES = {
  x86_64: {
    "conpty.dll": "runtimes/win-x64/native/conpty.dll"
    "OpenConsole.exe": "build/native/runtimes/x64/OpenConsole.exe"
  }
  aarch64: {
    "conpty.dll": "runtimes/win-arm64/native/conpty.dll"
    "OpenConsole.exe": "build/native/runtimes/arm64/OpenConsole.exe"
  }
}

export def install-dir []: nothing -> path {
  $env.LOCALAPPDATA | path join "Programs" "Rio"
}

# This user's Start menu, not the all-users one the MSI writes to.
export def shortcut-path []: nothing -> path {
  $env.APPDATA | path join "Microsoft" "Windows" "Start Menu" "Programs" "Rio.lnk"
}

# A version as numbers: "v0.5.28" -> [0 5 28]. Anything after a "-" is a
# pre-release label and is dropped; latest-stable keeps those out anyway.
export def version-key [version: string]: nothing -> list<int> {
  $version | str replace --regex '^v' '' | split row '-' | first | split row '.' | each {|part| $part | into int }
}

# -1, 0 or 1, as a is older than, the same as, or newer than b. Missing
# trailing parts count as 0, and parts compare as numbers, so 2607.1001 and
# 2607.01001 are the same version.
export def compare-versions [a: string, b: string]: nothing -> int {
  let x = (version-key $a)
  let y = (version-key $b)
  let n = ([($x | length) ($y | length)] | math max)
  for i in 0..<$n {
    let p = ($x | get --optional $i | default 0)
    let q = ($y | get --optional $i | default 0)
    if $p != $q { return (if $p > $q { 1 } else { -1 }) }
  }
  0
}

# The newest version without a pre-release label, from NuGet's version list.
export def latest-stable [versions: list<string>]: nothing -> string {
  let stable = ($versions | where {|v| not ($v | str contains '-') })
  if ($stable | is-empty) { error make { msg: "NuGet lists no stable ConPTY release" } }
  $stable | reduce {|v, best| if (compare-versions $v $best) > 0 { $v } else { $best } }
}

# The file version a ConPTY NuGet release stamps into its DLL, which splits the
# package's third number in two: 1.24.260710001 -> 1.24.2607.10001. Needed
# because the DLL is all there is to ask what is installed.
export def conpty-file-version [nuget: string]: nothing -> string {
  let parts = ($nuget | split row '.')
  let build = ($parts | get 2)
  if ($parts | length) != 3 or ($build | str length) <= 4 {
    error make { msg: $"unexpected ConPTY version '($nuget)'" }
  }
  $"($parts.0).($parts.1).($build | str substring 0..3).($build | str substring 4..)"
}

# What to do about one component, given what is there and what is current.
export def action-for [installed: any, latest: string]: nothing -> string {
  if $installed == null {
    "install"
  } else if (compare-versions $latest $installed) > 0 {
    "upgrade"
  } else {
    "current"
  }
}

# Whether an Authenticode result is a valid signature by Microsoft itself.
# Matched on the organisation, not the whole subject, which also names the
# signing service and changes when Microsoft rotates certificates.
export def microsoft-signed [status: string, subject: string]: nothing -> bool {
  $status == "Valid" and ($subject =~ 'O=Microsoft Corporation(,|$)')
}

# One asset's SHA-256 from the checksums.txt Rio attaches to every release,
# sha256sum's "<hash>  <name>" lines. From the same release as the binary, so
# it proves the download is whole and is the file upstream published, not that
# upstream is trustworthy -- the same trust a winget manifest's hash gives.
# The GitHub API has a digest too, but allows 60 unauthenticated calls an hour
# (see tests/unit/sources.nu).
export def checksum-for [checksums: string, name: string]: nothing -> any {
  let hash = ($checksums
    | lines
    | parse --regex '^(?<hash>[0-9a-fA-F]{64})\s+\*?(?<name>\S+)\s*$'
    | where name == $name
    | get --optional 0.hash)
  if $hash == null { null } else { $hash | str lowercase }
}

export def conpty-url [version: string]: nothing -> string {
  $"https://api.nuget.org/v3-flatcontainer/($CONPTY_PACKAGE)/($version)/($CONPTY_PACKAGE).($version).nupkg"
}

# pwsh for what nushell cannot do itself: read a file's version resource and
# signature, and write a shortcut. By path as well as by name, because this
# runs in the same step that installs pwsh, and this process's PATH predates
# that install.
def pwsh-exe []: nothing -> any {
  let found = (which pwsh | get --optional 0.path)
  if $found != null { return $found }
  let default = ($env.ProgramFiles | path join "PowerShell" "7" "pwsh.exe")
  if ($default | path exists) { $default } else { null }
}

# A PowerShell single-quoted string: nothing inside is interpreted except a
# doubled quote.
def ps-quote [text: string]: nothing -> string {
  let escaped = ($text | str replace --all "'" "''")
  $"'($escaped)'"
}

def pwsh-query [pwsh: string, script: string]: nothing -> string {
  let result = (do { ^$pwsh -NoProfile -NonInteractive -Command $script } | complete)
  if $result.exit_code != 0 { error make { msg: $"pwsh failed: ($result.stderr | str trim)" } }
  $result.stdout | str trim
}

def file-version [pwsh: string, file: path]: nothing -> any {
  if not ($file | path exists) { return null }
  let version = (pwsh-query $pwsh $"\(Get-Item -LiteralPath (ps-quote $file)).VersionInfo.FileVersion")
  if ($version | is-empty) { null } else { $version }
}

def signature [pwsh: string, file: path]: nothing -> record {
  let script = $"$s = Get-AuthenticodeSignature -LiteralPath (ps-quote $file); \"$\($s.Status)|$\($s.SignerCertificate.Subject)\""
  let fields = (pwsh-query $pwsh $script | split row '|')
  { status: ($fields | first), subject: ($fields | get --optional 1 | default "") }
}

# Put a file in place even while Rio is running it. Windows will not delete
# or overwrite an executable or DLL that is in use, but it will rename one, so
# the old copy steps aside under a name no later run collides with, and
# sweep-leftovers removes it once nothing holds it.
def replace [source: path, dest: path]: nothing -> nothing {
  if ($dest | path exists) {
    mv --force $dest $"($dest).old-(date now | format date '%Y%m%d%H%M%S%f')"
  }
  cp $source $dest
}

def sweep-leftovers [dir: path]: nothing -> nothing {
  for old in (ls $dir | where {|f| ($f.name | path basename) =~ '\.old-\d+$' } | get name) {
    try { rm --force $old } catch { }
  }
}

def install-rio [dir: path, installed: any, --dry-run]: nothing -> nothing {
  let tag = (fallback latest-tag $REPO)
  let latest = ($tag | str replace --regex '^v' '')
  let action = (action-for $installed $latest)
  if $action == "current" { log skipped $"Rio ($installed) is the latest release"; return }

  let name = ($ASSETS | get --optional (fallback arch))
  if $name == null { error make { msg: $"Rio publishes no Windows build for ($nu.os-info.arch)" } }
  let verb = (if $action == "install" { "install" } else { $"upgrade from ($installed) to" })
  if $dry_run { log info $"would ($verb) Rio ($latest) in ($dir)"; return }

  # Unverified is not a fallback -- if the checksum cannot be had, Rio waits.
  let release = $"https://github.com/($REPO)/releases/download/($tag)"
  let digest = (try {
    checksum-for (http get --raw $"($release)/checksums.txt" | decode utf-8) $name
  } catch { null })
  if ($digest | is-empty) {
    error make { msg: $"could not read the SHA-256 of ($name) from the release's checksums.txt -- not installing an unverified Rio; re-run later" }
  }

  let work = (mktemp --directory --tmpdir "dotfiles-rio-XXXXXX")
  let download = ($work | path join "rio.exe")
  http get --raw $"($release)/($name)" | save --raw --force $download
  let actual = (open --raw $download | hash sha256)
  if $actual != $digest {
    rm --recursive --force $work
    error make { msg: $"($name) does not match its published digest \(expected ($digest), got ($actual)) -- not installed" }
  }

  mkdir $dir
  replace $download ($dir | path join "rio.exe")
  rm --recursive --force $work
  log ok $"Rio ($latest) -> ($dir)"
}

def install-conpty [pwsh: string, dir: path, --dry-run]: nothing -> nothing {
  let files = ($CONPTY_FILES | get --optional (fallback arch))
  if $files == null { error make { msg: $"ConPTY has no ($nu.os-info.arch) build" } }

  let latest = (latest-stable (http get $"https://api.nuget.org/v3-flatcontainer/($CONPTY_PACKAGE)/index.json" | get versions))
  let stamped = (conpty-file-version $latest)
  # Both files come from the same package; either one missing means the pair
  # has to be put down again.
  let installed = (if ($dir | path join "OpenConsole.exe" | path exists) { file-version $pwsh ($dir | path join "conpty.dll") } else { null })
  let action = (action-for $installed $stamped)
  if $action == "current" { log skipped $"ConPTY ($installed) is the latest stable release"; return }

  let verb = (if $action == "install" { "install" } else { $"upgrade from ($installed) to" })
  if $dry_run { log info $"would ($verb) ConPTY ($latest) beside rio.exe"; return }

  let work = (mktemp --directory --tmpdir "dotfiles-conpty-XXXXXX")
  let package = ($work | path join "conpty.nupkg")
  let payload = ($work | path join "payload")
  mkdir $payload
  http get --raw (conpty-url $latest) | save --raw --force $package
  # A .nupkg is a zip. Windows' own tar is bsdtar, which reads zip; a GNU tar
  # earlier on PATH -- Git Bash puts one there -- does not, hence the path.
  ^($env.WINDIR | path join "System32" "tar.exe") -xf $package -C $payload

  # Every file checked before any is placed, so a bad package leaves the
  # working pair alone rather than half-replaced.
  for file in ($files | transpose name inner) {
    let path = ($payload | path join $file.inner)
    if not ($path | path exists) {
      rm --recursive --force $work
      error make { msg: $"the ConPTY ($latest) package has no ($file.inner)" }
    }
    let sig = (signature $pwsh $path)
    if not (microsoft-signed $sig.status $sig.subject) {
      rm --recursive --force $work
      error make { msg: $"($file.name) from ConPTY ($latest) is not validly signed by Microsoft \(($sig.status), ($sig.subject)) -- not installed" }
    }
  }

  mkdir $dir
  for file in ($files | transpose name inner) {
    replace ($payload | path join $file.inner) ($dir | path join $file.name)
  }
  rm --recursive --force $work
  log ok $"ConPTY ($latest) -> ($dir)"
}

# Rio's entry point, since this puts nothing on PATH: the MSI added Program
# Files\Rio to the system PATH, but nothing here starts Rio by name, and the
# Start menu is how it is opened.
def install-shortcut [pwsh: string, dir: path, --dry-run]: nothing -> nothing {
  let link = (shortcut-path)
  if ($link | path exists) { log skipped $"($link) already exists"; return }
  let target = ($dir | path join "rio.exe")
  let script = ([
    "$link = (New-Object -ComObject WScript.Shell).CreateShortcut(" (ps-quote $link) ");"
    "$link.TargetPath = " (ps-quote $target) ";"
    "$link.Description = 'Rio terminal';"
    "$link.Save()"
  ] | str join "")
  log shell [$pwsh "-NoProfile" "-NonInteractive" "-Command" $script] --dry-run=$dry_run
}

# Rio turns OSC 9 and OSC 777 into Windows toasts, sent as the app ID "Rio".
# Windows drops a toast from an app ID it does not know, without a word -- the
# call succeeds and nothing appears -- and nothing registers this one: the MSI
# never did, and a shortcut only would if it carried the ID. The per-user
# registration is one key with a display name, and needs no administrator.
const TOAST_KEY = 'HKCU\Software\Classes\AppUserModelId\Rio'

def register-toasts [--dry-run]: nothing -> nothing {
  let known = (try { registry query --hkcu 'Software\Classes\AppUserModelId\Rio' DisplayName | get value } catch { "" })
  if $known == "Rio" { log skipped "Rio's notifications are already registered"; return }
  log shell ["reg" "add" $TOAST_KEY "/v" "DisplayName" "/t" "REG_SZ" "/d" "Rio" "/f"] --dry-run=$dry_run
}

export def install [--dry-run]: nothing -> nothing {
  log step "Rio, for this user, from its GitHub release, with ConPTY beside it"

  let pwsh = (pwsh-exe)
  if $pwsh == null {
    log warn "pwsh is not installed yet -- open a new shell and re-run `nu install.nu --only packages` for Rio"
    return
  }

  let dir = (install-dir)
  if not $dry_run and ($dir | path exists) { sweep-leftovers $dir }

  # Separately, so that Rio failing to download still leaves ConPTY current,
  # and the other way round.
  try {
    install-rio $dir (file-version $pwsh ($dir | path join "rio.exe")) --dry-run=$dry_run
  } catch {|e|
    log warn $"Rio did not install: ($e.msg)"
  }
  try {
    install-conpty $pwsh $dir --dry-run=$dry_run
  } catch {|e|
    log warn $"ConPTY did not install: ($e.msg) -- Rio still runs, but shows no images"
  }
  try {
    install-shortcut $pwsh $dir --dry-run=$dry_run
  } catch {|e|
    log warn $"the Start menu shortcut was not created: ($e.msg)"
  }
  try {
    register-toasts --dry-run=$dry_run
  } catch {|e|
    log warn $"Rio's notifications were not registered: ($e.msg) -- OSC 9 will show nothing"
  }

  # Not removed from here: uninstalling it needs the administrator this exists
  # to avoid. Until it goes, the Start menu has two Rios, and the machine-wide
  # PATH entry points at the old one.
  let msi = ($env.ProgramFiles | path join "Rio" "rio.exe")
  if ($msi | path exists) {
    log warn $"the machine-wide Rio from winget is still installed \(($msi)) -- `winget uninstall --exact --id raphamorim.rio`, as an administrator, leaves only this one"
  }
}
