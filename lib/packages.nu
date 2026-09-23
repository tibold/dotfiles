# Turning the logical tool list into actual package names for this machine.
#
# The overlays are imported statically because nushell resolves modules at
# parse time -- there is no dynamic `use`. That is a feature here: adding a
# distro means editing this file, so no overlay can be silently unreachable.

use ../packages/common.nu
use ../packages/suse.nu
use ../packages/leap.nu
use ../packages/fedora.nu
use ../packages/debian.nu
use ../packages/macos.nu
use ../packages/windows.nu

# The shape every overlay is read through, and the value of anything it does
# not define. An overlay names only the fields it has something to say about --
# casks and provided are Homebrew and macOS concepts, fonts is winget's, and an
# overlay that has none of its own should not have to restate that.
const EMPTY = { overrides: {}, casks: {}, fonts: {}, extra: [], provided: {}, omitted: {}, removed: [], winget_args: {} }

# The overlay for a distro is its family's, with its own laid on top.
#
# Two layers rather than one because Leap and Tumbleweed share a package
# manager and nearly every package name, and differ only in which newer tools
# their repos carry. Flattening that into per-distro files would duplicate the
# whole suse overlay to express four nulls.
export def overlay-for [distro: record]: nothing -> record {
  # Merged onto EMPTY inside each arm rather than around the match: a bare `{}`
  # in command position is a closure to nushell, not an empty record, so an
  # arm that said `{}` would typecheck and then fail at run time with "input
  # type not supported".
  let family = match $distro.family {
    "suse" => ($EMPTY | merge { overrides: $suse.OVERRIDES, extra: $suse.EXTRA, omitted: $suse.OMITTED, removed: $suse.REMOVED })
    "fedora" => ($EMPTY | merge { overrides: $fedora.OVERRIDES, extra: $fedora.EXTRA, omitted: $fedora.OMITTED, removed: $fedora.REMOVED })
    "debian" => ($EMPTY | merge { overrides: $debian.OVERRIDES, extra: $debian.EXTRA, omitted: $debian.OMITTED, removed: $debian.REMOVED })
    "macos" => ($EMPTY | merge {
      overrides: $macos.OVERRIDES, casks: $macos.CASKS, extra: $macos.EXTRA
      provided: $macos.PROVIDED, omitted: $macos.OMITTED, removed: $macos.REMOVED
    })
    "windows" => ($EMPTY | merge {
      overrides: $windows.OVERRIDES, fonts: $windows.FONTS, extra: $windows.EXTRA
      provided: $windows.PROVIDED, omitted: $windows.OMITTED, removed: $windows.REMOVED
      winget_args: $windows.WINGET_ARGS
    })
    _ => $EMPTY
  }

  let specific = match $distro.id {
    "opensuse-leap" => ($EMPTY | merge { overrides: $leap.OVERRIDES, extra: $leap.EXTRA, omitted: $leap.OMITTED, removed: $leap.REMOVED })
    _ => $EMPTY
  }

  {
    overrides: ($family.overrides | merge $specific.overrides)
    casks: ($family.casks | merge $specific.casks)
    fonts: ($family.fonts | merge $specific.fonts)
    extra: ($family.extra ++ $specific.extra)
    provided: ($family.provided | merge $specific.provided)
    omitted: ($family.omitted | merge $specific.omitted)
    removed: ($family.removed ++ $specific.removed | uniq)
    winget_args: ($family.winget_args | merge $specific.winget_args)
  }
}

# An override is a rename (string), a split (list), or "not here" (null). A
# FONTS entry is a record naming both what to install and what it is called.
def expand [value: any]: nothing -> list<any> {
  if $value == null {
    []
  } else if ($value | describe) == "string" or ($value | describe | str starts-with "record") {
    [$value]
  } else {
    $value
  }
}

# What to install, and where everything else comes from.
#
# A tool the package manager does not supply splits three ways, and the
# difference between them is the whole point of tracking it:
#
#   fallback  we still want it, so lib/fallback.nu fetches the upstream release
#   provided  it is already in the base system, and the overlay says which part
#   omitted   we have decided to do without it here, and the overlay says why
#
# Anything nulled must land in one of those buckets. tests/unit/packages.nu
# enforces it, so a tool can never be dropped from an environment by an
# override alone.
#
# `provided` exists because macOS made the two-bucket version dishonest: zsh,
# curl, tar, make and the compiler are all present there without Homebrew
# having anything to do with it. Calling that "omitted" would tell a reader the
# environment lacks a tool that is on their PATH.
#
# `--group databases` resolves the opt-in DATABASES list instead, through the
# same overlays and the same accounting, but without the base list's
# companions: no EXTRA, no pipx or npm, nothing to remove.
export def resolve [distro: record, --group: string = "base"]: nothing -> record {
  let overlay = (overlay-for $distro)
  let base = ($group == "base")
  let names = (match $group {
    "base" => $common.PACKAGES
    "databases" => $common.DATABASES
    _ => { error make { msg: $"unknown package group '($group)' -- base or databases" } }
  })

  let mapped = $names | each {|logical|
    # Fonts and casks first: a logical name mapped to either is answered by
    # that, and never also looked up as a formula or winget id.
    if $logical in $overlay.fonts {
      { logical: $logical, packages: [], casks: [], fonts: (expand ($overlay.fonts | get $logical)) }
    } else if $logical in $overlay.casks {
      { logical: $logical, packages: [], casks: (expand ($overlay.casks | get $logical)), fonts: [] }
    } else if $logical in $overlay.overrides {
      { logical: $logical, packages: (expand ($overlay.overrides | get $logical)), casks: [], fonts: [] }
    } else {
      { logical: $logical, packages: [$logical], casks: [], fonts: [] }
    }
  }

  let unavailable = ($mapped
    | where {|m| ($m.packages | is-empty) and ($m.casks | is-empty) and ($m.fonts | is-empty) }
    | get logical)

  let provided_names = ($overlay.provided | columns)
  let omitted_names = ($overlay.omitted | columns)

  {
    install: ($mapped | get packages | flatten | append (if $base { $overlay.extra } else { [] }) | uniq)
    casks: ($mapped | get casks | flatten | uniq)
    fonts: ($mapped | get fonts | flatten | uniq)
    fallback: ($unavailable | where {|t| $t not-in $omitted_names and $t not-in $provided_names })
    provided: ($unavailable | where {|t| $t in $provided_names } | each {|t| { tool: $t, reason: ($overlay.provided | get $t) } })
    omitted: ($unavailable | where {|t| $t in $omitted_names } | each {|t| { tool: $t, reason: ($overlay.omitted | get $t) } })
    # tmuxp, the one pipx application, drives tmux; Windows has no tmux to
    # drive (see packages/windows.nu's OMITTED for pipx), so there is nothing
    # for pipx to install there.
    pipx: (if $base and $distro.family != "windows" { $common.PIPX } else { [] })
    npm: (if $base { $common.NPM } else { [] })
    removed: (if $base { $overlay.removed } else { [] })
    winget_args: $overlay.winget_args
  }
}
