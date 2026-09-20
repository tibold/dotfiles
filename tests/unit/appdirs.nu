# The applications that read their config from somewhere other than the place
# this repo keeps it.

use ../../steps/appdirs.nu
use std/testing *
use std/assert

const REPO = (path self | path dirname | path dirname | path dirname)

@test
export def "every listed source is a directory this repo actually has" [] {
  # An entry naming a directory that was renamed or removed would link nothing
  # and say nothing, and the application would quietly go back to its defaults
  # -- which is the failure this whole step exists to fix.
  for entry in $appdirs.PLACES {
    let dir = ($REPO | path join "home" $entry.source)
    assert ($dir | path exists) $"($entry.app) points at home/($entry.source), which does not exist"
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
