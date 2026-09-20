# The macOS defaults step.
#
# Everything asserted here is a pure function of the settings table, so it runs
# on any machine -- the point is that the list itself stays within the bounds
# the step promises, which is a claim about the table rather than about a Mac.

use ../../steps/macos.nu
use std/testing *
use std/assert

@test
export def "a boolean is compared the way defaults prints it back" [] {
  # `defaults write -bool false` stores a CFBoolean that reads back as 0.
  # Comparing "false" to "0" would make every boolean look permanently out of
  # date and rewrite it on every run, which is how a step that restarts Finder
  # turns into a step that restarts Finder every time.
  assert equal (macos normalize "bool" "true") "1"
  assert equal (macos normalize "bool" "false") "0"
  assert equal (macos normalize "int" "2") "2"
  assert equal (macos normalize "string" "Nlsv") "Nlsv"
}

@test
export def "a boolean that is not one is refused" [] {
  assert error {|| macos normalize "bool" "sometimes" }
}

@test
export def "the home directory is filled in wherever a path is wanted" [] {
  let rows = (macos resolved --home "/tmp/someone")
  let screenshots = ($rows | where key == "location" | first)

  assert equal $screenshots.value "/tmp/someone/Screenshots"
  assert not (($rows | get value | str join " ") =~ '\{home\}') "a placeholder survived into a value that would be written verbatim"
}

@test
export def "every setting says what it is for" [] {
  # These are someone else's machine's behaviour. A line of defaults with no
  # stated reason is one nobody can decide to remove later.
  for row in $macos.DEFAULTS {
    assert ($row.why | is-not-empty) $"($row.domain) ($row.key) has no reason given"
    assert ($row.type in ["bool" "int" "string"]) $"($row.key) has type ($row.type), which is not a defaults flag this step writes"
  }
}

@test
export def "no setting changes how the machine looks" [] {
  # The Dock stays where it was put, at the size it was put, and does not learn
  # to hide. Appearance is a preference this repo has no opinion about, and the
  # keys that would override one are named here so that adding one has to be a
  # decision rather than a drive-by.
  let keys = ($macos.DEFAULTS | get key)
  for forbidden in [
    "autohide"
    "orientation"
    "tilesize"
    "magnification"
    "AppleInterfaceStyle"
    "AppleAccentColor"
    "AppleHighlightColor"

    # Not appearance, but the same principle, and a decision that was actually
    # made rather than assumed: the Dock's recents section is used on these
    # machines, so it stays.
    "show-recents"
  ] {
    assert ($forbidden not-in $keys) $"($forbidden) changes how the machine looks or behaves visually, which this step stays out of"
  }
}

@test
export def "only the preferences of this user are written" [] {
  # No sudo, no /Library, no other user. The whole step is this user's own
  # preference domains, which is what makes it safe to run unattended.
  for row in $macos.DEFAULTS {
    let argv = (macos write-command $row)
    assert equal ($argv | first) "defaults"
    assert ("sudo" not-in $argv) $"($row.key) would be written with sudo"
    assert not ($row.domain | str starts-with "/") $"($row.domain) is a path, which writes a plist outside this user's domain"
  }
}

@test
export def "the write command names the type it is writing" [] {
  let row = { domain: "com.apple.finder", key: "ShowPathbar", type: "bool", value: "true", dir: false, why: "example" }
  assert equal (macos write-command $row) ["defaults" "write" "com.apple.finder" "ShowPathbar" "-bool" "true"]
}

@test
export def "a changed domain restarts only what reads it" [] {
  assert equal (macos restarts-for ["com.apple.finder"]) ["Finder"]
  assert equal (macos restarts-for ["com.apple.dock"]) ["Dock"]
  assert equal (macos restarts-for ["com.apple.screencapture"]) ["SystemUIServer"]

  # desktopservices is Finder's too, and naming Finder twice would kill it,
  # restart it, and kill it again.
  assert equal (macos restarts-for ["com.apple.finder" "com.apple.desktopservices"]) ["Finder"]
}

@test
export def "the step never restarts an application it might be running inside" [] {
  # This is the one that would hurt. The installer runs in a terminal, so
  # restarting a terminal to apply its press-and-hold setting would kill the
  # installer part way through, leaving the rest of the settings unwritten and
  # nothing on screen explaining it. Those changes are reported for someone to
  # act on instead.
  let restarts = (macos restarts-for ($macos.DEFAULTS | get domain | uniq))

  assert equal ($restarts | sort) ["Dock" "Finder" "SystemUIServer"] $"restarts-for named ($restarts | str join ', '), which is more than the three system services it is allowed to touch"

  for row in ($macos.DEFAULTS | where key == "ApplePressAndHoldEnabled") {
    assert equal (macos restarts-for [$row.domain]) [] $"($row.domain) is an application this may be running inside"
  }
}

@test
export def "press-and-hold is turned off per application rather than globally" [] {
  # The accent picker is a real feature and only misbehaves in a terminal,
  # where it cannot draw and leaks an Escape on dismissal. Setting it in
  # NSGlobalDomain would take it away from every application that handles it
  # correctly -- anything you write prose in.
  let rows = ($macos.DEFAULTS | where key == "ApplePressAndHoldEnabled")

  assert ($rows | is-not-empty) "press-and-hold is no longer configured at all"
  for row in $rows {
    assert ($row.domain != "NSGlobalDomain") "press-and-hold should be scoped to the applications where it misbehaves"
    assert ($row.domain | str contains ".") $"($row.domain) does not look like a bundle identifier"
  }
}

@test
export def "a global preference restarts nothing" [] {
  # NSGlobalDomain is read by every application as it launches. There is no
  # single process to restart, and killing the ones that happen to be running
  # would take unsaved work with it.
  assert equal (macos restarts-for ["NSGlobalDomain"]) []
  assert equal (macos restarts-for []) []
}

@test
export def "only a directory-valued setting asks for a directory" [] {
  # `dir` makes the step create the target before writing it. A boolean or an
  # integer that claimed one would have it try to mkdir "true".
  for row in ($macos.DEFAULTS | where dir) {
    assert equal $row.type "string" $"($row.key) is marked as a directory but its value is a ($row.type)"
  }
}
