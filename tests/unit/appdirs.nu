# The applications that read their config from somewhere other than the place
# this repo keeps it.

use ../../steps/appdirs.nu
use std/testing *
use std/assert

const REPO = (path self | path dirname | path dirname | path dirname)

@test
export def "every listed source is something this repo actually has" [] {
  # An entry naming a file or directory that was renamed or removed would link
  # nothing and say nothing, and the application would quietly go back to its
  # defaults -- which is the failure this whole step exists to fix.
  for entry in $appdirs.PLACES {
    let path = ($REPO | path join "home" $entry.source)
    assert ($path | path exists) $"($entry.app) points at home/($entry.source), which does not exist"
  }
}

@test
export def "no application is listed twice" [] {
  let apps = ($appdirs.PLACES | get app)
  assert equal ($apps | length) ($apps | uniq | length) "an application appears more than once"
}

@test
export def "destinations are relative to home" [] {
  # They are joined onto $HOME, so an absolute path here would silently escape
  # the home directory and write somewhere nobody asked for.
  for entry in $appdirs.PLACES {
    for platform in ($entry.dirs | columns) {
      let dir = ($entry.dirs | get $platform)
      assert not ($dir | str starts-with "/") $"($entry.app) on ($platform) names an absolute path: ($dir)"
      assert not ($dir | str starts-with "~") $"($entry.app) on ($platform) names a path starting with ~: ($dir)"
    }
  }
}

@test
export def "a platform with nothing to say gets no work" [] {
  # Where the ordinary mirror already put the config where the application
  # looks, this step must do nothing at all rather than link it twice.
  assert equal (appdirs destination-for { app: "x", source: ".config/x", dirs: {} } "linux") ""
  assert equal (appdirs destination-for { app: "x", source: ".config/x", dirs: { macos: "Library/x" } } "linux") ""
  assert equal (appdirs destination-for { app: "x", source: ".config/x", dirs: { macos: "Library/x" } } "macos") "Library/x"
}

@test
export def "macOS is where lazygit and nushell need the second link" [] {
  # Both follow Apple's own convention there and XDG on Linux, so the Linux
  # side needs nothing.
  let mac = (appdirs plan-for { id: "macos", family: "macos" } | get app)
  assert ("lazygit" in $mac)
  assert ("nushell" in $mac)

  let linux = (appdirs plan-for { id: "ubuntu", family: "debian" } | get app)
  assert equal $linux [] $"Linux should need no second link, got: ($linux | str join ', ')"
}

@test
export def "Windows gets its shared configs from here" [] {
  let win = (appdirs plan-for { id: "windows", family: "windows" })
  for app in ["lazygit" "rio" "nushell" "tmux-themes" "git"] {
    assert ($app in ($win | get app)) $"($app) has no Windows entry"
  }
  assert equal ($win | where app == "nushell" | first | get dest) "AppData/Roaming/nushell"
  assert equal ($win | where app == "git" | first | get dest) ".gitconfig"
}

@test
export def "every app config in home is decided for Windows" [] {
  # Windows does not mirror home/, so a new home/.config/<app>/ would silently
  # never reach it. Each one needs a Windows entry or a reason not to.
  let apps = (ls ($REPO | path join "home" ".config") | where type == dir | get name | each {|d| $d | path basename })
  let covered = ($appdirs.PLACES
    | where {|e| "windows" in ($e.dirs | columns) }
    | get source
    | where {|s| $s | str starts-with ".config/" }
    | each {|s| $s | split row "/" | get 1 })
  for app in $apps {
    assert (($app in $covered) or ($app in ($appdirs.NOT_ON_WINDOWS | columns))) $"home/.config/($app) has no Windows entry in steps/appdirs.nu and no reason in NOT_ON_WINDOWS"
  }
}

# A throwaway repo root with home/.gitconfig and home/.zshrc, for testing how
# a file source (unlike every other PLACES entry, which names a directory) is
# planned. Built directly rather than trusting the real repo's home/ to keep
# just this shape.
def file-source-fixture []: nothing -> record {
  let base = (mktemp --directory --tmpdir "dotfiles-appdirs-XXXXXX")
  let root = ($base | path join "repo")
  let home = ($base | path join "home")

  mkdir ($root | path join "home")
  "gitconfig contents" | save ($root | path join "home" ".gitconfig")
  "zshrc contents" | save ($root | path join "home" ".zshrc")
  mkdir $home

  { base: $base, root: $root, home: $home }
}

def cleanup [f: record]: nothing -> nothing {
  rm --recursive --force $f.base
}

@test
export def "a file source plans to just that one file" [] {
  # links plan only knows how to mirror a directory. A file entry (git) must
  # still end up as exactly one row -- naming its sibling .zshrc, or every
  # file in home/, would be the parent-directory mirror leaking through.
  let f = (file-source-fixture)
  let plan = (appdirs plan-entry { app: "git", source: ".gitconfig", dest: ".gitconfig" } --root $f.root --home $f.home)

  assert equal ($plan | get relative) [".gitconfig"]
  assert equal ($plan | first | get target) ($f.home | path join ".gitconfig")

  cleanup $f
}

@test
export def "Rio on Windows is pointed at the config this repo keeps" [] {
  # RIO_CONFIG_HOME names a directory, and Rio reads config.toml inside it, so
  # the directory must be the one holding the real file for its watch to see
  # edits.
  let dir = (appdirs rio-config-home $REPO)
  assert ($dir | path join "config.toml" | path exists) $"($dir) holds no config.toml for Rio to read"
  assert equal ($dir | path basename) "rio"
}
