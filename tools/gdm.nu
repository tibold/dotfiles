#!/usr/bin/env nu
#
# Toggle GNOME desktop features that have no convenient switch in Settings,
# optionally per session kind.
#
#   nu tools/gdm.nu                       show every feature and its state
#   nu tools/gdm.nu screenlock            show one feature's state
#   nu tools/gdm.nu screenlock off        set it
#   nu tools/gdm.nu session               report this session's kind
#   nu tools/gdm.nu apply                 apply the policy for this session
#
# WHY "apply" EXISTS
#
# gsettings live in dconf, which is per USER and not per session, so nothing
# here can be scoped to the headless RDP session by configuration alone. The
# only place a per-session difference can be made is at session start: "apply"
# reads the session's kind from logind and sets each feature to whatever POLICY
# says it should be there. An autostart entry runs it on login.
#
# Consequence worth knowing: if a remote and a local session are logged in at
# the same time, the one that started last has set the values, because there is
# only one dconf database behind both.
#
# To add a feature, add an entry to `features` below with its on/off/status
# behaviour, and give it POLICY entries if it should differ by session kind.
# Nothing else changes.

use ../lib/log.nu

# What each feature should be, per session kind, when "apply" runs.
#
# A feature with no entry for a kind is left alone.
const POLICY = {
  screenlock: { remote: "off", local: "on" }
}

# --- features -----------------------------------------------------------------
#
# A record of closures rather than functions named after the feature. The bash
# version had to build function names by string concatenation to dispatch;
# holding the behaviour as data makes the dispatch a lookup and means an
# unknown feature fails at the lookup rather than as a "command not found".
def features []: nothing -> record {
  {
    # Off means the desktop never blanks and never locks itself. Super+L still
    # locks on demand: suppressing that would need
    # org.gnome.desktop.lockdown disable-lock-screen, which removes the ability
    # altogether and is deliberately not touched here.
    screenlock: {
      off: {||
        ^gsettings set org.gnome.desktop.session idle-delay 0
        ^gsettings set org.gnome.desktop.screensaver lock-enabled false
        ^gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
      }

      on: {||
        # reset rather than hardcoding the defaults, so this follows GNOME's
        # own values instead of freezing whatever they happened to be when this
        # was written.
        ^gsettings reset org.gnome.desktop.session idle-delay
        ^gsettings reset org.gnome.desktop.screensaver lock-enabled
        ^gsettings reset org.gnome.desktop.screensaver idle-activation-enabled
      }

      status: {||
        let locking = (^gsettings get org.gnome.desktop.screensaver lock-enabled | str trim)
        if $locking == "false" {
          "off"
        } else {
          # "uint32 300" -> "300". Taking the last field rather than stripping
          # non-digits, which would also eat the digits shared with the type
          # name and turn 300 into 00.
          let idle = (^gsettings get org.gnome.desktop.session idle-delay | str trim | split row " " | last)
          $"on \(locks after ($idle)s idle)"
        }
      }
    }
  }
}

# --- session detection --------------------------------------------------------

# This user's graphical sessions, as logind knows them.
#
# XDG_SESSION_ID is preferred when set, but it is absent in a shell started a
# few processes deep, so we fall back to listing. Class=user excludes the
# systemd manager sessions and the gdm greeter.
def sessions []: nothing -> table {
  let listing = (do { ^loginctl list-sessions --no-legend } | complete)
  if $listing.exit_code != 0 { return [] }

  let me = (^id -un | str trim)

  $listing.stdout
  | lines
  | each {|line| $line | str trim | split row --regex '\s+' }
  | where {|fields| ($fields | length) >= 3 and ($fields | get 2) == $me }
  | each {|fields| $fields | first }
  | where {|id| (session-property $id "Class") == "user" }
  | each {|id| { id: $id, remote: ((session-property $id "Remote") == "yes") } }
}

def session-property [id: string, property: string]: nothing -> string {
  let result = (do { ^loginctl show-session $id -p $property --value } | complete)
  if $result.exit_code == 0 { $result.stdout | str trim } else { "" }
}

# remote, local, or unknown.
#
# logind's Remote property is the discriminator, and it is the honest one: a
# gnome-remote-desktop session reports Remote=yes with a RemoteHost, while a
# session on the physical seat reports no. XDG_SESSION_TYPE cannot be used --
# both are "wayland".
export def session-kind []: nothing -> string {
  let current = ($env.XDG_SESSION_ID? | default "")

  let session = if ($current | is-not-empty) {
    { id: $current, remote: ((session-property $current "Remote") == "yes") }
  } else {
    sessions | first
  }

  if $session == null {
    "unknown"
  } else if $session.remote {
    "remote"
  } else {
    "local"
  }
}

# --- commands -----------------------------------------------------------------

def show [name: string]: nothing -> nothing {
  let feature = (features | get $name)
  print $"(($name | fill --width 16)) (do $feature.status)"
}

def main [
  feature?: string    # which feature to show or change
  state?: string      # on|off|true|false|1|0|yes|no|enable|disable
] {
  if $feature == null {
    for name in (features | columns) { show $name }
    return
  }

  let known = (features | columns)
  if $feature not-in $known {
    error make { msg: $"unknown feature: ($feature) \(try: ($known | str join ', '))" }
  }

  # No state given: report rather than change. A toggle script that changes
  # something when asked a question is a trap.
  if $state == null {
    show $feature
    return
  }

  let wanted = match $state {
    "on" | "true" | "1" | "yes" | "enable" => "on"
    "off" | "false" | "0" | "no" | "disable" => "off"
    _ => { error make { msg: $"expected on|off|true|false|1|0, got: ($state)" } }
  }

  do (features | get $feature | get $wanted)
  show $feature
}

def "main list" [] {
  for name in (features | columns) { show $name }
}

def "main session" [] {
  print (session-kind)
}

def "main apply" [] {
  let kind = (session-kind)

  # Never guess. An unrecognised session gets the values it already had rather
  # than one kind's policy applied to the other by accident.
  if $kind == "unknown" {
    error make { msg: "could not determine the session kind -- nothing applied" }
  }

  # Remote wins when both kinds are logged in at once.
  #
  # A local login and a headless remote session can coexist -- the remote one
  # has no seat, so GDM has nothing to switch to and makes a second session --
  # and there is still only one dconf database behind both. Without this,
  # logging in locally would run its own "apply", set the local policy, and
  # silently reinstate screen locking in the remote session somebody is
  # working in.
  #
  # Remote is deferred to because it is the one being used; a local login is
  # normally somebody standing at the machine briefly.
  if $kind == "local" and ((sessions | where remote | is-not-empty)) {
    log warn "a remote session is also logged in -- leaving its settings alone"
    return
  }

  for name in (features | columns) {
    let wanted = ($POLICY | get --optional $name | default {} | get --optional $kind)
    if $wanted == null { continue }
    do (features | get $name | get $wanted)
    print $"(($name | fill --width 16)) (($wanted | fill --width 4)) \(($kind) session)"
  }
}
