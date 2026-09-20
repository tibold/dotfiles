# Applications that do not read their configuration where they keep it on
# every other system.
#
# Everything this repo configures lives under home/.config/<app>/, so there is
# one place to look for it and one convention to remember. Some applications
# then read it from somewhere else entirely, and they do not agree with each
# other about where -- so this is a list rather than a rule:
#
#   lazygit   ~/.config on Linux, ~/Library/Application Support on macOS
#   nushell   the same split, for the same reason: both follow the platform's
#             own convention, which is what Apple's differs about
#   rio       ~/.config even on macOS, ignoring the convention above, and
#             %LOCALAPPDATA% on Windows
#   git       ~/.gitconfig everywhere, Windows included
#
# There is no deriving that. Each project decided separately, and the only
# honest way to hold it is to write down the ones that deviate.
#
# Left as a link rather than moving the file: the copy under ~/.config stays,
# so a config is always findable where the rest of them are, and the second
# link is what the application actually opens.
#
# Files, never the directory. Applications keep state beside their config --
# lazygit writes github_pull_requests.json there, nushell its history and
# plugin registry -- and linking the directory itself would make this repo the
# home of all of it.

use ../lib/log.nu
use ../lib/links.nu
use ../lib/distro.nu

# source is relative to home/ in this repo; each platform names a directory
# relative to $HOME. A platform absent from `dirs` needs nothing done -- the
# ordinary home/ mirror already put the config where that system looks.
#
# Windows entries are inert until this repo installs there at all, and are
# recorded because they were established at the same time as the rest. Only
# paths confirmed from the application's own source or documentation appear.
export const PLACES = [
  {
    app: "lazygit"
    source: ".config/lazygit"
    dirs: {
      macos: "Library/Application Support/lazygit"
      windows: "AppData/Local/lazygit"
    }
  }
  {
    app: "nushell"
    source: ".config/nushell"
    dirs: {
      macos: "Library/Application Support/nushell"
    }
  }
  {
    app: "rio"
    source: ".config/rio"
    dirs: {
      windows: "AppData/Local/rio"
    }
  }
]

# Where this application wants its config on this system, or "" when it is
# content with the ordinary location.
export def destination-for [entry: record, os: string]: nothing -> string {
  $entry.dirs | get --optional $os | default ""
}

# The entries that apply to this system, resolved.
export def plan-for [system: record]: nothing -> table {
  let os = (distro config-names $system | first)
  $PLACES
  | each {|entry| {
      app: $entry.app
      source: $entry.source
      dest: (destination-for $entry $os)
    } }
  | where {|entry| $entry.dest | is-not-empty }
}

export def install [
  system: record
  --root: path
  --home: path
  --copy
  --dry-run
]: nothing -> nothing {
  let wanted = (plan-for $system)
  if ($wanted | is-empty) { return }

  log step $"Application config directories \(($wanted | get app | str join ', '))"

  for entry in $wanted {
    let from = (["home" $entry.source] | path join)
    if not ($root | path join $from | path exists) {
      log warn $"($entry.app): ($from) is not in this repo -- nothing to link"
      continue
    }

    let dest_root = ($home | path join $entry.dest)
    log info $"($entry.app) -> ($entry.dest)"

    let plan = (links plan --root $root --home $dest_root --from $from --copy=$copy)
    # Backed up under the application's own name. The paths here are relative
    # to that application's directory, so several of them displacing a file
    # called config.yml would otherwise land on top of each other in one
    # timestamped directory.
    links apply $plan --copy=$copy --dry-run=$dry_run --backup-root ($home | path join ".dotfiles-backup" $entry.app)

    # Scoped to this application's own directory, so a stale link here can only
    # ever be one of ours: links prune removes a link only when it points into
    # this repository and its target is gone.
    links prune (links stale --root $root --home $dest_root --from $from --managed ($plan | get target)) --dry-run=$dry_run
  }
}
