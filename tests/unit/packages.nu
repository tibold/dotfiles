use ../../lib/packages.nu
use ../../lib/fallback.nu
use ../../packages/common.nu
use std/testing *
use std/assert

const TUMBLEWEED = { id: "opensuse-tumbleweed", family: "suse" }
const LEAP = { id: "opensuse-leap", family: "suse" }
const FEDORA = { id: "fedora", family: "fedora" }
const UBUNTU = { id: "ubuntu", family: "debian" }
const MACOS = { id: "macos", family: "macos" }

const ALL = [
  { id: "opensuse-tumbleweed", family: "suse" }
  { id: "opensuse-leap", family: "suse" }
  { id: "fedora", family: "fedora" }
  { id: "ubuntu", family: "debian" }
  { id: "macos", family: "macos" }
]

# The four that install from a Linux distribution's archive. Separated out
# because several properties below are about that archive rather than about
# package resolution, and are simply not claims about Homebrew.
const LINUX = [
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

# --- macOS --------------------------------------------------------------------

@test
export def "macOS takes everything from Homebrew rather than from a download" [] {
  # The property that lets lib/fallback.nu stay Linux-only. Homebrew carries
  # every tool in common.nu, so nothing on a Mac should ever resolve to an
  # upstream release -- and the assets there are all ELF binaries, so if this
  # ever stops being true it has to be noticed here rather than at run time.
  assert equal (packages resolve $MACOS).fallback []
}

@test
export def "a cask is never handed to brew as a formula" [] {
  let resolved = (packages resolve $MACOS)
  assert ("font-meslo-lg-nerd-font" in $resolved.casks) "the Nerd Font should be installed as a cask"
  assert ("font-meslo-lg-nerd-font" not-in $resolved.install) "a cask token is not a formula name"
  assert ("nerd-fonts" not-in $resolved.install) "the logical name should not leak through either"
}

@test
export def "casks exist only where Homebrew does" [] {
  for distro in $LINUX {
    assert equal (packages resolve $distro).casks [] $"($distro.id) has no casks to install"
  }
}

@test
export def "a tool already in the base system is not reported as absent" [] {
  # The distinction `provided` exists for. zsh is not missing from a Mac in any
  # sense -- it is the login shell -- and calling it omitted would send someone
  # looking for a tool that is already on their PATH.
  let resolved = (packages resolve $MACOS)
  let provided = ($resolved.provided | get tool)

  assert ("zsh" in $provided)
  assert ("zsh" not-in $resolved.fallback)
  assert ("zsh" not-in ($resolved.omitted | get tool))
  assert ("zsh" not-in $resolved.install) "Homebrew zsh would be a second copy of a shell that is already here"
}

@test
export def "every provision carries a reason" [] {
  for distro in $ALL {
    for present in (packages resolve $distro).provided {
      assert ($present.reason | is-not-empty) $"($distro.id): ($present.tool) is called provided with no reason given"
    }
  }
}

@test
export def "a tool is provided or omitted but never both" [] {
  # They are opposite claims -- "you already have this" and "you are doing
  # without this" -- and a tool that made both would print two contradictory
  # lines during an install.
  for distro in $ALL {
    let resolved = (packages resolve $distro)
    let both = ($resolved.provided | get tool | where {|t| $t in ($resolved.omitted | get tool) })
    assert equal $both [] $"($distro.id) calls ($both | str join ', ') both provided and omitted"
  }
}

@test
export def "the nushell plugins come with the shell on macOS" [] {
  # Homebrew's nushell formula builds every nu_plugin_* crate from the same
  # source tree, so both logical names map to the one formula -- and the name
  # must appear once, not twice.
  let install = (packages resolve $MACOS).install
  assert ("nushell" in $install)
  assert equal ($install | where {|p| $p == "nushell" } | length) 1
}

# --- archive layouts ----------------------------------------------------------

@test
export def "every source declares a layout the installer understands" [] {
  for tool in ($fallback.SOURCES | columns) {
    let layout = (fallback layout-of $tool)
    assert ($layout in ["binaries" "directory"]) $"($tool) has layout '($layout)', which lib/fallback.nu cannot install"
  }
}

@test
export def "a tool that cannot run alone keeps its whole archive" [] {
  # git-credential-manager's Linux archive is the executable plus
  # libSkiaSharp.so and libHarfBuzzSharp.so, which it loads from beside itself.
  # Lifting out the binary the way the Go and Rust tools are handled produces a
  # command that works until it has to draw something.
  assert equal (fallback layout-of "git-credential-manager") "directory"

  # And the ordinary case is still ordinary.
  assert equal (fallback layout-of "gh") "binaries"
  assert equal (fallback layout-of "lazygit") "binaries"
}

@test
export def "an unknown tool has a layout rather than an error" [] {
  # layout-of is consulted before anything has checked that the tool exists.
  assert equal (fallback layout-of "not-a-tool") "binaries"
}

@test
export def "a kept archive lives beside bin-dir rather than inside it" [] {
  # ~/.local/bin is a directory of commands. Two hundred files of bundled .NET
  # runtime unpacked into it would make it something else.
  let share = (fallback share-dir "git-credential-manager" --bin-dir "/home/someone/.local/bin")
  assert equal $share "/home/someone/.local/share/git-credential-manager"
}

@test
export def "a kept archive is installed whole and linked from bin-dir" [] {
  # Exercises the real file handling with a fabricated archive, since the
  # download path cannot run in a unit test. The shape is git-credential-
  # manager's: one executable that does not work without the libraries beside
  # it.
  let base = (mktemp --directory --tmpdir "dotfiles-fallback-XXXXXX")
  let payload = ($base | path join "payload")
  let bin = ($base | path join ".local" "bin")

  mkdir $payload
  "binary" | save ($payload | path join "git-credential-manager")
  "library" | save ($payload | path join "libSkiaSharp.so")
  "notice" | save ($payload | path join "NOTICE")

  fallback install-directory "git-credential-manager" {
    name: "gcm-linux-x64-2.9.1.tar.gz"
    binaries: ["git-credential-manager"]
  } --payload $payload --bin-dir $bin

  let share = (fallback share-dir "git-credential-manager" --bin-dir $bin)

  # Everything travelled, not just the executable.
  assert ($share | path join "libSkiaSharp.so" | path exists) "the library beside the binary was left behind"
  assert ($share | path join "NOTICE" | path exists) "the archive was not kept whole"

  # And bin-dir holds a link to it rather than a copy.
  let link = ($bin | path join "git-credential-manager")
  assert ($link | path exists) "nothing was linked into bin-dir"
  # Both expanded: on macOS /var is itself a link to /private/var, so the
  # resolved link and the path it was made from are spelled differently.
  assert equal ($link | path expand) ($share | path join "git-credential-manager" | path expand)

  rm --recursive --force $base
}

@test
export def "reinstalling a kept archive does not leave the old files behind" [] {
  # A half-old, half-new set of runtime files is worse than either version, so
  # the directory is replaced rather than merged.
  let base = (mktemp --directory --tmpdir "dotfiles-fallback-XXXXXX")
  let bin = ($base | path join ".local" "bin")
  let asset = { name: "gcm.tar.gz", binaries: ["git-credential-manager"] }

  let first = ($base | path join "first")
  mkdir $first
  "old" | save ($first | path join "git-credential-manager")
  "old" | save ($first | path join "libOld.so")
  fallback install-directory "git-credential-manager" $asset --payload $first --bin-dir $bin

  let second = ($base | path join "second")
  mkdir $second
  "new" | save ($second | path join "git-credential-manager")
  fallback install-directory "git-credential-manager" $asset --payload $second --bin-dir $bin

  let share = (fallback share-dir "git-credential-manager" --bin-dir $bin)
  assert not ($share | path join "libOld.so" | path exists) "a file from the previous version survived the reinstall"
  assert equal (open --raw ($share | path join "git-credential-manager")) "new"

  rm --recursive --force $base
}
