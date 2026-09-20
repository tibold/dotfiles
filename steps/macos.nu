# macOS system settings that have no switch worth clicking twice.
#
# The Linux side of this repo has tools/gdm.nu for the same job and keeps it
# out of the installer. This one is a step instead, because unlike GDM's policy
# these are per-user preferences that a fresh Mac gets wrong in ways you feel
# on the first day: the key repeat that does not repeat, the Finder that hides
# what a file actually is.
#
# The rules it follows:
#
#   * Only this user's own preferences. Nothing here uses sudo, touches another
#     user's domain, or writes to /Library.
#   * Read before write. `defaults write` is idempotent, but running it anyway
#     means never being able to tell a run that changed something from one that
#     did not -- and it is the difference between "restart Finder" being
#     something this does once and something it does every time.
#   * Nothing about how the machine looks. Appearance, wallpaper, accent colour
#     and the Dock's position and behaviour are left exactly as they are found.
#
# `defaults read` is the check, so every value below has to be written in the
# form that command prints it back in -- see `normalize`.
#
# --- where these came from, and how far to trust them -------------------------
#
# Not from Apple. `defaults` is a documented command -- `man defaults` -- but
# the preference keys it writes are almost all undocumented. They are whatever
# plist an application happens to keep, found by reading it before and after
# toggling a switch in the interface. The names below therefore come from the
# long tradition of macOS dotfiles scripts that did exactly that
# (mathiasbynens/dotfiles is the one most of the rest descend from) and from
# macos-defaults.com, which tracks which keys still work on which release.
#
# The one exception is DSDontWriteNetworkStores, which Apple does document, in
# its note on SMB browsing behaviour: https://support.apple.com/en-us/102064
#
# Two things follow from that, and they are the reason this comment exists:
#
#   * a key can stop working with no warning and no error. `defaults write`
#     stores a setting whether or not anything still reads it, so a line here
#     that has quietly become a no-op looks identical to one that works. The
#     `defaults read` check this step does proves the value was stored, not
#     that anything acts on it.
#   * most of these have a switch in System Settings. Writing them here buys a
#     new machine arriving configured, not access to something the interface
#     hides. The ones with no switch at all are ApplePressAndHoldEnabled, the
#     screenshot type and shadow, the expanded save panel, and the Apple-
#     documented one above.
#
# To confirm any of them, or to find a new one, diff the domain around the
# change:
#
#   defaults read com.apple.finder > /tmp/before
#   # ...toggle the setting in System Settings or the Finder menu...
#   defaults read com.apple.finder > /tmp/after
#   diff /tmp/before /tmp/after
#
# That is where every name below ultimately comes from, and the only way to
# tell whether one still does what it says on this release of macOS.

use ../lib/log.nu

# The settings, one row each, with the reason in the row rather than in a
# comment above it: the reason is the part worth reading when one of these
# turns out to be wrong, and it stays attached to the value when the list is
# printed.
#
#   domain   the preference domain, as `defaults` names it
#   key      the preference
#   type     bool, int or string -- becomes the -bool/-int/-string flag
#   value    written as text, in the form `defaults read` returns it
#   dir      the value names a directory that has to exist first
#   why      what this buys, in one line
export const DEFAULTS = [
  # -- Press and hold, per terminal --
  #
  # Holding a key on macOS opens the accent picker rather than repeating it.
  # That is a good feature -- it is how you type é without knowing a key
  # combination -- and it is only wrong in a terminal, where the picker cannot
  # draw itself over the grid and dismissing it leaks an Escape through. In
  # neovim that reads as: one character, then normal mode.
  #
  # So this is set per application rather than in NSGlobalDomain. Apps read
  # their own domain first and fall back to the global one, so naming the
  # terminals here turns it off exactly where it misbehaves and leaves the
  # picker working in every application where it does not -- Notes, Slack, a
  # browser, anything you write prose in.
  #
  # Only keys with accent variants are affected: the vowels plus c, n, s, y, z
  # and a few more. j and k repeat fine either way, which is why this can go
  # unnoticed for a long time and then be baffling -- it is `u` and the vowels
  # in insert mode that break.
  #
  # The list is spelled out rather than discovered. An entry for an application
  # that is not installed is inert, and means the setting is already right the
  # day it is. Add a line to extend it; the bundle identifier of an app is:
  #
  #   defaults read /Applications/Foo.app/Contents/Info CFBundleIdentifier
  #
  # Nothing here is restarted by this step -- see restarts-for. The installer
  # is running inside one of these.
  {
    domain: "com.raphaelamorim.rio", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", dir: false
    why: "Rio: hold a key to repeat it rather than opening the accent picker"
  }
  {
    domain: "net.kovidgoyal.kitty", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", dir: false
    why: "kitty: hold a key to repeat it rather than opening the accent picker"
  }
  {
    domain: "co.zeit.hyper", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", dir: false
    why: "Hyper: hold a key to repeat it rather than opening the accent picker"
  }
  {
    domain: "com.apple.Terminal", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", dir: false
    why: "Terminal.app: hold a key to repeat it rather than opening the accent picker"
  }
  {
    domain: "com.termius.mac", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", dir: false
    why: "Termius: hold a key to repeat it rather than opening the accent picker"
  }
  {
    domain: "com.microsoft.VSCode", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", dir: false
    why: "VS Code: its integrated terminal and its editor have the same problem"
  }

  # -- Keyboard --
  {
    domain: "NSGlobalDomain", key: "KeyRepeat", type: "int", value: "2", dir: false
    why: "repeat rate, in 15ms units; 2 is the fastest position of the System Settings slider"
  }
  {
    domain: "NSGlobalDomain", key: "InitialKeyRepeat", type: "int", value: "15", dir: false
    why: "delay before a held key starts repeating, in 15ms units; 15 is the shortest the slider offers"
  }
  {
    domain: "NSGlobalDomain", key: "NSAutomaticQuoteSubstitutionEnabled", type: "bool", value: "false", dir: false
    why: "stop smart quotes turning \" into a character no shell or compiler accepts"
  }
  {
    domain: "NSGlobalDomain", key: "NSAutomaticDashSubstitutionEnabled", type: "bool", value: "false", dir: false
    why: "stop -- becoming an em dash in anything that is really a command line"
  }

  # -- Finder --
  {
    domain: "NSGlobalDomain", key: "AppleShowAllExtensions", type: "bool", value: "true", dir: false
    why: "show every file extension, so what a file is does not depend on an icon"
  }
  {
    domain: "com.apple.finder", key: "ShowPathbar", type: "bool", value: "true", dir: false
    why: "show where the current folder actually is"
  }
  {
    domain: "com.apple.finder", key: "ShowStatusBar", type: "bool", value: "true", dir: false
    why: "item count and free space at the bottom of the window"
  }
  {
    domain: "com.apple.finder", key: "FXPreferredViewStyle", type: "string", value: "Nlsv", dir: false
    why: "open new windows in list view -- Nlsv is the code for it"
  }
  {
    domain: "com.apple.finder", key: "FXDefaultSearchScope", type: "string", value: "SCcf", dir: false
    why: "search the folder you are in rather than the whole Mac"
  }
  {
    domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", type: "bool", value: "true", dir: false
    why: "no .DS_Store files scattered across network shares"
  }
  {
    domain: "NSGlobalDomain", key: "NSNavPanelExpandedStateForSaveMode", type: "bool", value: "true", dir: false
    why: "save panels open expanded, showing the full file browser"
  }

  # -- Screenshots --
  {
    domain: "com.apple.screencapture", key: "location", type: "string", value: "{home}/Screenshots", dir: true
    why: "keep screenshots out of the Desktop, which is also a folder full of everything else"
  }
  {
    domain: "com.apple.screencapture", key: "type", type: "string", value: "png", dir: false
    why: "png rather than a lossy format, for screenshots that are mostly text"
  }
  {
    domain: "com.apple.screencapture", key: "disable-shadow", type: "bool", value: "true", dir: false
    why: "no 60px of transparent drop shadow around every window capture"
  }

  # -- Dock --
  #
  # Deliberately nothing about autohide, position or size. The Dock is where
  # someone put it.
  #
  # show-recents is deliberately absent too, and for a better reason than
  # taste: the recents section is used here. It is the obvious candidate for a
  # list like this -- it is the one part of the Dock that changes width on its
  # own, so every unpinned application you open shifts the pinned ones along --
  # and it was tried and rejected. Getting back to something just closed is
  # worth more than the icons staying still. tests/unit/macos.nu fails if it
  # reappears.
  {
    domain: "com.apple.dock", key: "mru-spaces", type: "bool", value: "false", dir: false
    why: "keep Spaces in the order they were made, so a desktop stays where muscle memory left it"
  }
]

# What `defaults read` prints back for a value we are about to write.
#
# Booleans are the only ones that differ: `defaults write -bool false` stores a
# CFBoolean, which reads back as 0. Comparing "false" to "0" would make every
# boolean look permanently out of date and rewrite it on every run.
export def normalize [type: string, value: string]: nothing -> string {
  if $type != "bool" { return $value }
  match ($value | str lowercase) {
    "true" | "yes" | "1" => "1"
    "false" | "no" | "0" => "0"
    _ => { error make { msg: $"($value) is not a boolean" } }
  }
}

# The settings with {home} filled in.
#
# Taken as an argument rather than read from $nu.home-dir here, so the list can
# be checked against a temporary directory in a test.
export def resolved [--home: path]: nothing -> table {
  $DEFAULTS | each {|row| $row | update value ($row.value | str replace --all "{home}" $home) }
}

# What this setting is set to now, or "" if it has never been set.
export def read-current [domain: string, key: string]: nothing -> string {
  let result = (do { ^defaults read $domain $key } | complete)
  if $result.exit_code != 0 { return "" }
  $result.stdout | str trim
}

# The settings, each with what it is now and whether that needs changing.
#
# Separate from `apply` so the whole decision can be looked at -- `--dry-run`
# prints this -- and so the comparison itself is testable without a Mac.
export def plan [--home: path]: nothing -> table {
  resolved --home $home
  | each {|row|
      let wanted = (normalize $row.type $row.value)
      let current = (read-current $row.domain $row.key)
      $row | insert wanted $wanted | insert current $current | insert change ($current != $wanted)
    }
}

# argv to write one setting.
export def write-command [row: record]: nothing -> list<string> {
  ["defaults" "write" $row.domain $row.key $"-($row.type)" $row.value]
}

# Which applications have to be restarted for a change to be visible.
#
# A preference domain is read by its application at launch, so a running Finder
# or Dock goes on showing the old value indefinitely. Only the ones that
# actually changed are restarted -- this is why `plan` bothers to read first.
#
# NSGlobalDomain is not in the table on purpose: it is read by every
# application as it starts, so there is nothing to restart, and the settings
# above that live in it reach an already-running application at its next
# launch. The keyboard ones are the exception that needs a full log out, which
# `apply` says out loud rather than restarting anything.
#
# Neither are the terminals, and that one is not a nicety: this step runs
# inside one of them. Restarting the application the installer is running in
# would kill the installer, mid-way through, with the remaining settings
# unwritten and no output saying why. They are reported instead, for someone to
# restart when they are not in the middle of using them. Only the three system
# services above are ever named here, and tests/unit/macos.nu holds it to that.
export def restarts-for [domains: list<string>]: nothing -> list<string> {
  $domains
  | each {|domain|
      match $domain {
        "com.apple.finder" | "com.apple.desktopservices" => "Finder"
        "com.apple.dock" => "Dock"
        "com.apple.screencapture" => "SystemUIServer"
        _ => null
      }
    }
  | where {|app| $app != null }
  | uniq
}

export def install [--home: path, --dry-run]: nothing -> nothing {
  log step "macOS defaults"

  let plan = (plan --home $home)
  let changing = ($plan | where change)

  for row in ($plan | where {|r| not $r.change }) {
    log skipped $"($row.domain) ($row.key) is already ($row.wanted)"
  }

  if ($changing | is-empty) {
    log info "nothing to change"
    return
  }

  for row in $changing {
    log info $row.why

    if $row.dir {
      if $dry_run {
        log info $"would create ($row.value)"
      } else {
        mkdir $row.value
      }
    }

    log shell (write-command $row) --dry-run=$dry_run
  }

  # Restarting Finder and the Dock is disruptive enough to be worth naming: it
  # closes open Finder windows. It happens only when something actually
  # changed, which on a second run is nothing.
  for app in (restarts-for ($changing | get domain | uniq)) {
    if $dry_run {
      log info $"would restart ($app)"
    } else {
      # Tolerated rather than checked: killall exits non-zero when the
      # application is not running, which is a normal state on a machine being
      # set up, and not a reason to fail the step.
      let result = (do { ^killall $app } | complete)
      if $result.exit_code == 0 {
        log ok $"restarted ($app)"
      } else {
        log skipped $"($app) is not running"
      }
    }
  }

  if "NSGlobalDomain" in ($changing | get domain) {
    log info "these reach each application as it next launches; a full log-out picks up the stragglers"
  }

  # Named rather than restarted, deliberately -- one of these is very likely the
  # window this is printing into.
  let relaunch = ($changing | where key == "ApplePressAndHoldEnabled" | get domain)
  if ($relaunch | is-not-empty) {
    log info $"quit and reopen these for press-and-hold to change: ($relaunch | str join ', ')"
  }
}
