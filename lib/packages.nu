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

# The shape every overlay is read through, and the value of anything it does
# not define. An overlay names only the fields it has something to say about --
# casks and provided are Homebrew and macOS concepts, and the Linux overlays
# should not have to restate that they have none.
const EMPTY = { overrides: {}, casks: {}, extra: [], provided: {}, omitted: {}, removed: [] }

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
    _ => $EMPTY
  }

  let specific = match $distro.id {
    "opensuse-leap" => ($EMPTY | merge { overrides: $leap.OVERRIDES, extra: $leap.EXTRA, omitted: $leap.OMITTED, removed: $leap.REMOVED })
    _ => $EMPTY
  }

  {
    overrides: ($family.overrides | merge $specific.overrides)
    casks: ($family.casks | merge $specific.casks)
    extra: ($family.extra ++ $specific.extra)
    provided: ($family.provided | merge $specific.provided)
    omitted: ($family.omitted | merge $specific.omitted)
    removed: ($family.removed ++ $specific.removed | uniq)
  }
}

# An override is a rename (string), a split (list), or "not here" (null).
def expand [value: any]: nothing -> list<string> {
  if $value == null {
    []
  } else if ($value | describe) == "string" {
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
export def resolve [distro: record]: nothing -> record {
  let overlay = (overlay-for $distro)

  let mapped = $common.PACKAGES | each {|logical|
    # Casks first: a logical name mapped to a cask is answered by that, and
    # never also looked up as a formula.
    if $logical in $overlay.casks {
      { logical: $logical, packages: [], casks: (expand ($overlay.casks | get $logical)) }
    } else if $logical in $overlay.overrides {
      { logical: $logical, packages: (expand ($overlay.overrides | get $logical)), casks: [] }
    } else {
      { logical: $logical, packages: [$logical], casks: [] }
    }
  }

  let unavailable = ($mapped
    | where {|m| ($m.packages | is-empty) and ($m.casks | is-empty) }
    | get logical)

  let provided_names = ($overlay.provided | columns)
  let omitted_names = ($overlay.omitted | columns)

  {
    install: ($mapped | get packages | flatten | append $overlay.extra | uniq)
    casks: ($mapped | get casks | flatten | uniq)
    fallback: ($unavailable | where {|t| $t not-in $omitted_names and $t not-in $provided_names })
    provided: ($unavailable | where {|t| $t in $provided_names } | each {|t| { tool: $t, reason: ($overlay.provided | get $t) } })
    omitted: ($unavailable | where {|t| $t in $omitted_names } | each {|t| { tool: $t, reason: ($overlay.omitted | get $t) } })
    pipx: $common.PIPX
    npm: $common.NPM
    removed: $overlay.removed
  }
}
