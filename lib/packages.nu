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

const EMPTY = { overrides: {}, extra: [], omitted: {}, removed: [] }

# The overlay for a distro is its family's, with its own laid on top.
#
# Two layers rather than one because Leap and Tumbleweed share a package
# manager and nearly every package name, and differ only in which newer tools
# their repos carry. Flattening that into per-distro files would duplicate the
# whole suse overlay to express four nulls.
export def overlay-for [distro: record]: nothing -> record {
  let family = match $distro.family {
    "suse" => { overrides: $suse.OVERRIDES, extra: $suse.EXTRA, omitted: $suse.OMITTED, removed: $suse.REMOVED }
    "fedora" => { overrides: $fedora.OVERRIDES, extra: $fedora.EXTRA, omitted: $fedora.OMITTED, removed: $fedora.REMOVED }
    "debian" => { overrides: $debian.OVERRIDES, extra: $debian.EXTRA, omitted: $debian.OMITTED, removed: $debian.REMOVED }
    _ => $EMPTY
  }

  let specific = match $distro.id {
    "opensuse-leap" => { overrides: $leap.OVERRIDES, extra: $leap.EXTRA, omitted: $leap.OMITTED, removed: $leap.REMOVED }
    _ => $EMPTY
  }

  {
    overrides: ($family.overrides | merge $specific.overrides)
    extra: ($family.extra ++ $specific.extra)
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

# What to install, and what this distro cannot give us.
#
# A tool the distro does not package splits two ways, and the difference is the
# whole point of tracking it:
#
#   fallback  we still want it, so lib/fallback.nu fetches the upstream release
#   omitted   we have decided to do without it here, and the overlay says why
#
# Anything nulled must land in one bucket or the other. tests/unit/packages.nu
# enforces that, so a tool can never be dropped from an environment by an
# override alone.
export def resolve [distro: record]: nothing -> record {
  let overlay = (overlay-for $distro)

  let mapped = $common.PACKAGES | each {|logical|
    if $logical in $overlay.overrides {
      { logical: $logical, packages: (expand ($overlay.overrides | get $logical)) }
    } else {
      { logical: $logical, packages: [$logical] }
    }
  }

  let unavailable = ($mapped | where {|m| $m.packages | is-empty } | get logical)
  let omitted_names = ($overlay.omitted | columns)

  {
    install: ($mapped | get packages | flatten | append $overlay.extra | uniq)
    fallback: ($unavailable | where {|t| $t not-in $omitted_names })
    omitted: ($unavailable | where {|t| $t in $omitted_names } | each {|t| { tool: $t, reason: ($overlay.omitted | get $t) } })
    pipx: $common.PIPX
    npm: $common.NPM
    removed: $overlay.removed
  }
}
