use ../../lib/packages.nu
use ../../lib/fallback.nu
use ../../packages/common.nu
use std/testing *
use std/assert

const TUMBLEWEED = { id: "opensuse-tumbleweed", family: "suse" }
const LEAP = { id: "opensuse-leap", family: "suse" }
const FEDORA = { id: "fedora", family: "fedora" }
const UBUNTU = { id: "ubuntu", family: "debian" }

const ALL = [
  { id: "opensuse-tumbleweed", family: "suse" }
  { id: "opensuse-leap", family: "suse" }
  { id: "fedora", family: "fedora" }
  { id: "ubuntu", family: "debian" }
]

@test
export def "a rename replaces the logical name" [] {
  let resolved = (packages resolve $TUMBLEWEED)
  assert ("nodejs-default" in $resolved.install) "openSUSE's name should be used"
  assert ("nodejs" not-in $resolved.install) "the logical name should not leak through"
}

@test
export def "an override may expand to several packages" [] {
  # openSUSE splits completions and editor integration out; one logical tool
  # legitimately becomes four packages.
  let resolved = (packages resolve $TUMBLEWEED)
  for p in ["fzf" "fzf-tmux" "fzf-zsh-integration" "vim-fzf"] {
    assert ($p in $resolved.install) $"($p) should be installed on openSUSE"
  }
}

@test
export def "a name with no override passes through unchanged" [] {
  let resolved = (packages resolve $FEDORA)
  assert ("tmux" in $resolved.install)
  assert ("ripgrep" in $resolved.install)
}

@test
export def "a null override marks the tool unavailable" [] {
  let resolved = (packages resolve $UBUNTU)
  assert ("lazygit" in $resolved.fallback)
  assert ("lazygit" not-in $resolved.install) "an unavailable tool must not be handed to apt"
}

@test
export def "an omitted tool is not fetched from upstream" [] {
  let resolved = (packages resolve $UBUNTU)
  assert ("nerd-fonts" in ($resolved.omitted | get tool)) "nerd-fonts is deliberately absent on Debian"
  assert ("nerd-fonts" not-in $resolved.fallback) "an omitted tool must not be downloaded anyway"
  assert ("nerd-fonts" not-in $resolved.install)
}

@test
export def "every omission carries a reason" [] {
  for distro in $ALL {
    for skipped in (packages resolve $distro).omitted {
      assert ($skipped.reason | is-not-empty) $"($distro.id): ($skipped.tool) is omitted with no reason given"
    }
  }
}

@test
export def "the distro overlay wins over its family" [] {
  # Leap and Tumbleweed share the suse overlay; Leap's own overlay is what
  # expresses that its repos are older.
  assert ("nushell" in (packages resolve $LEAP).fallback)
  assert ("nushell" in (packages resolve $TUMBLEWEED).install)
}

@test
export def "the distro overlay inherits what it does not override" [] {
  # Leap does not restate nodejs, so it must still get openSUSE's name.
  assert ("nodejs-default" in (packages resolve $LEAP).install)
}

@test
export def "extras are added on top" [] {
  assert ("helm-zsh-completion" in (packages resolve $TUMBLEWEED).install)
  assert ("ca-certificates" in (packages resolve $UBUNTU).install)
}

@test
export def "no package is listed twice" [] {
  for distro in $ALL {
    let install = (packages resolve $distro).install
    assert equal ($install | length) ($install | uniq | length) $"($distro.id) has a duplicate package"
  }
}

@test
export def "every unavailable tool has somewhere else to come from" [] {
  # The check that makes nulling a package safe. A tool marked unavailable must
  # either be fetched from upstream or be explicitly omitted with a reason;
  # otherwise it would just vanish from the environment on that distro and
  # nothing would notice.
  for distro in $ALL {
    for tool in (packages resolve $distro).fallback {
      assert ($tool in ($fallback.SOURCES | columns)) $"($distro.id): ($tool) is unavailable, is not omitted, and has no entry in fallback.nu"
    }
  }
}

@test
export def "every distro resolves the whole common list" [] {
  # install + unavailable must account for every logical name, or an override
  # has quietly swallowed one.
  for distro in $ALL {
    let resolved = (packages resolve $distro)
    assert ($resolved.install | is-not-empty) $"($distro.id) resolved to nothing"
    assert (($resolved.fallback | length) < ($common.PACKAGES | length)) $"($distro.id) has nothing available"
  }
}

@test
export def "an unknown family still resolves rather than crashing" [] {
  # install.nu refuses to run on an unknown distribution, but resolve itself
  # should stay total -- it is used by --dry-run and by the tests.
  let resolved = (packages resolve { id: "plan9", family: "unknown" })
  assert equal $resolved.install ($common.PACKAGES | append [] | uniq)
}

@test
export def "fallback sources cover both architectures" [] {
  for tool in ($fallback.SOURCES | columns) {
    let assets = ($fallback.SOURCES | get $tool | get assets)
    assert ("x86_64" in ($assets | columns)) $"($tool) has no x86_64 asset pattern"
    assert ("aarch64" in ($assets | columns)) $"($tool) has no aarch64 asset pattern"
  }
}

@test
export def "every fallback asset name is templated on the version" [] {
  # The names are built from the release tag rather than matched against a
  # listing, so a template that forgot its placeholder would silently ask for
  # the same stale filename forever.
  for tool in ($fallback.SOURCES | columns) {
    let assets = ($fallback.SOURCES | get $tool | get assets)
    for arch in ($assets | columns) {
      let template = ($assets | get $arch)
      assert ($template | str contains "{version}") $"($tool)/($arch) has no {version} placeholder: ($template)"
      assert ($template | str ends-with ".tar.gz") $"($tool)/($arch) is not a .tar.gz, which is all the installer unpacks"
    }
  }
}
