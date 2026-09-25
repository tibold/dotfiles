# The .NET SDK: the newest supported release and the newest LTS, which is one
# SDK whenever those are the same release. Opt-in: see OPT_IN in lib/steps.nu.
#
# Which releases those are is read from Microsoft's release index on every run
# rather than written down here, so a new major arrives by re-running the step,
# not by editing this file.
#
# Windows takes winget's per-major packages, machine-wide under Program Files,
# where `winget upgrade` finds them later. Everywhere else takes Microsoft's
# dotnet-install script into ~/.dotnet: it is the one method that works the
# same way on every distribution here -- no Microsoft package repository to add
# on openSUSE, no dependence on which majors Ubuntu happens to carry, and brew
# only packages the newest. ~/.profile and ~/.zshrc put it on PATH.

use ../lib/log.nu
use ../lib/distro.nu

export const INDEX = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json"
const SCRIPT = "https://dot.net/v1/dotnet-install.sh"

# Released and supported. "preview" and "go-live" are the release candidates of
# the next major, which are not what "latest" means here.
const SUPPORTED = ["active" "maintenance"]

def rank [channel: string]: nothing -> int {
  let parts = ($channel | split row "." | each {|p| $p | into int })
  ($parts | first) * 1000 + ($parts | get --optional 1 | default 0)
}

# The channels to install, LTS first, from the index's `releases-index` list.
# Sorted here rather than trusting the index's own order, which is newest
# first today but is not promised anywhere.
export def channels [index: list]: nothing -> list<string> {
  let supported = ($index
    | where {|r| ($r | get support-phase) in $SUPPORTED }
    | sort-by --reverse {|r| rank ($r | get channel-version) })
  if ($supported | is-empty) {
    error make { msg: "the .NET release index lists no supported release" }
  }
  let lts = ($supported | where {|r| ($r | get release-type) == "lts" } | get --optional 0)
  let latest = ($supported | first)
  [$lts $latest] | compact | each {|r| $r | get channel-version } | uniq
}

# winget has one package per major: Microsoft.DotNet.SDK.10, .9, .8 ...
export def winget-id [channel: string]: nothing -> string {
  let major = ($channel | split row "." | first)
  $"Microsoft.DotNet.SDK.($major)"
}

# The script is bash, not sh. The channel and directory go in as positional
# parameters rather than spliced into the script text, so no path needs quoting.
# The script skips a version that is already there, so re-running it only ever
# adds the newest patch of the channel.
export def installer-command [channel: string, dir: path]: nothing -> list<string> {
  [
    "bash" "-c"
    $"set -e; script=$\(curl -fsSL ($SCRIPT)\); printf '%s' \"$script\" | bash -s -- --channel \"$1\" --install-dir \"$2\" --no-path"
    "dotnet-install" $channel $dir
  ]
}

export def install [family: string, --dry-run]: nothing -> nothing {
  log step ".NET SDK"
  # A failure anywhere here warns rather than aborts, for the reason the
  # Claude Code step gives: an opt-in download is not worth the rest of the run.
  let wanted = (try {
    channels (http get --raw $INDEX | from json | get releases-index)
  } catch {|e|
    log warn $"could not read the .NET release index \(($e.msg)) -- rerun with `--only dotnet` later"
    []
  })
  if ($wanted | is-empty) { return }
  log info $"channels: ($wanted | str join ', ') \(newest LTS and newest release)"

  let dir = ($nu.home-dir | path join ".dotnet")
  for channel in $wanted {
    if $family == "windows" {
      let id = (winget-id $channel)
      let argv = (distro winget-list-command $id)
      if (do { ^($argv | first) ...($argv | slice 1..) } | complete).exit_code == 0 {
        log skipped $"($id) already installed -- `winget upgrade` keeps it current"
        continue
      }
      try {
        log shell (distro winget-install-command $id) --dry-run=$dry_run
      } catch {
        log warn $"($id) did not install -- rerun with `--only dotnet` later"
      }
    } else {
      try {
        log shell (installer-command $channel $dir) --dry-run=$dry_run
      } catch {
        log warn $".NET ($channel) did not install -- rerun with `--only dotnet` later"
      }
    }
  }
  if $family != "windows" and not $dry_run {
    log ok $"in ($dir); open a new shell for PATH and DOTNET_ROOT"
  }
}
