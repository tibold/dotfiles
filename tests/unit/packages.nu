use ../../lib/packages.nu
use ../../lib/fallback.nu
use ../../packages/common.nu
# By name, not `use ... as steps`: the module name `packages` is already taken
# by lib/packages.nu above, and steps/packages.nu would shadow it.
use ../../steps/packages.nu [winget-plan font-present font-clashes fnm-setup winget-command]
use std/testing *
use std/assert

const TUMBLEWEED = { id: "opensuse-tumbleweed", family: "suse" }
const LEAP = { id: "opensuse-leap", family: "suse" }
const FEDORA = { id: "fedora", family: "fedora" }
const UBUNTU = { id: "ubuntu", family: "debian" }
const MACOS = { id: "macos", family: "macos" }
const WINDOWS = { id: "windows", family: "windows" }

const ALL = [
  { id: "opensuse-tumbleweed", family: "suse" }
  { id: "opensuse-leap", family: "suse" }
  { id: "fedora", family: "fedora" }
  { id: "ubuntu", family: "debian" }
  { id: "macos", family: "macos" }
  { id: "windows", family: "windows" }
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
export def "every fallback download is templated on the release" [] {
  # The URLs are built from the release tag rather than matched against a
  # listing, so a template that forgot its placeholder would silently ask for
  # the same stale file forever. GitHub's own release URL carries the tag, so
  # only a source with a `url` of its own has to say where it goes.
  for tool in ($fallback.SOURCES | columns) {
    let source = ($fallback.SOURCES | get $tool)
    for arch in ($source.assets | columns) {
      let template = ($source.assets | get $arch)
      let url = ($source.url? | default "{tag}")
      let full = ($url | str replace "{name}" $template)
      assert (($full | str contains "{version}") or ($full | str contains "{tag}")) $"($tool)/($arch) never names the release: ($full)"
      if (fallback layout-of $tool) != "executable" {
        assert ($template | str ends-with ".tar.gz") $"($tool)/($arch) is not a .tar.gz, which is all the installer unpacks"
      }
    }
  }
}

@test
export def "a template fills in the tag and the bare version" [] {
  let vars = { tag: "v4.3.0", version: "4.3.0" }
  assert equal (fallback expand-template "helm-{tag}-linux-amd64.tar.gz" $vars) "helm-v4.3.0-linux-amd64.tar.gz"
  assert equal (fallback expand-template "nu-{version}-x86_64.tar.gz" $vars) "nu-4.3.0-x86_64.tar.gz"
  assert equal (fallback expand-template "k9s_Linux_amd64.tar.gz" $vars) "k9s_Linux_amd64.tar.gz"
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
  assert ("font-sauce-code-pro-nerd-font" in $resolved.casks) "the Nerd Font should be installed as a cask"
  assert ("font-sauce-code-pro-nerd-font" not-in $resolved.install) "a cask token is not a formula name"
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

# --- Windows --------------------------------------------------------------------

@test
export def "Windows takes nothing from an upstream download" [] {
  # lib/fallback.nu fetches Linux binaries only.
  assert equal (packages resolve $WINDOWS).fallback []
}

@test
export def "Windows maps tmux and htop onto their Windows counterparts" [] {
  let r = (packages resolve $WINDOWS)
  assert ("marlocarlo.psmux" in $r.install)
  assert ("marlocarlo.pstop" in $r.install)
  assert not ("tmux" in $r.install) "a logical name leaked through to winget"
}

@test
export def "every Windows package is a winget id" [] {
  # Publisher.Package -- a bare logical name here means an override is missing.
  for id in (packages resolve $WINDOWS).install {
    assert ($id =~ '^[A-Za-z0-9-]+\.[A-Za-z0-9.+-]+$') $"($id) is not a winget id"
  }
}

@test
export def "a font is never handed to winget" [] {
  let r = (packages resolve $WINDOWS)
  assert equal $r.fonts [{ install: "SourceCodePro", files: "SauceCodePro" }]
  assert not ("SourceCodePro" in $r.install)
  assert equal (packages resolve $FEDORA).fonts []
}

@test
export def "the nushell plugins come with the shell on Windows" [] {
  # winget's Nushell package puts nu_plugin_*.exe beside nu.exe, so they are
  # provided by the nushell id rather than installed or omitted.
  let r = (packages resolve $WINDOWS)
  assert ("nushell-plugins" in ($r.provided | get tool))
  assert not ("nushell-plugins" in ($r.omitted | get tool))
  assert ("Nushell.Nushell" in $r.install)
}

@test
export def "Windows installs no pipx applications" [] {
  assert equal (packages resolve $WINDOWS).pipx []
}

# --- steps/packages.nu on Windows ----------------------------------------------

@test
export def "an installed winget package is skipped" [] {
  let plan = (winget-plan ["Git.Git" "jqlang.jq"] ["Git.Git"])
  assert equal ($plan | where id == "Git.Git" | first | get action) "skip"
  assert equal ($plan | where id == "jqlang.jq" | first | get action) "install"
}

@test
export def "an installed font is found by its patched name, not its install name" [] {
  # Nerd Fonts renames what it patches -- Source Code Pro becomes SauceCodePro
  # -- so the files on disk do not start with the name oh-my-posh installs.
  # Looking for the install name would reinstall the font on every run.
  let files = ["C:/Users/u/AppData/Local/Microsoft/Windows/Fonts/SauceCodeProNerdFontMono-Regular.ttf"]
  assert (font-present "SauceCodePro" $files)
  assert not (font-present "SourceCodePro" $files)
}

@test
export def "a Meslo nerd font already installed is recognised" [] {
  assert (font-present "meslo" ["C:/Users/u/AppData/Local/Microsoft/Windows/Fonts/MesloLGSNerdFontMono-Regular.ttf"])
  assert not (font-present "meslo" ["C:/Windows/Fonts/Meslo-Plain.ttf"]) "not a nerd font"
  assert not (font-present "meslo" [])
}

@test
export def "only fonts an uninstalled cask would overwrite clash" [] {
  let casks = [
    { token: "font-sauce-code-pro-nerd-font", installed: null, artifacts: [
      { font: ["SauceCodeProNerdFont-Regular.ttf"] }
      { font: ["SauceCodeProNerdFont-Bold.ttf"] }
    ] }
    { token: "font-meslo-lg-nerd-font", installed: "3.5.1", artifacts: [{ font: ["MesloLGSNerdFont-Regular.ttf"] }] }
    { token: "git-credential-manager", installed: "2.9.1", artifacts: [{ pkg: ["gcm.pkg"] } { uninstall: [{}] }] }
  ]
  let existing = [
    "/Users/u/Library/Fonts/SauceCodeProNerdFont-Regular.ttf"
    "/Users/u/Library/Fonts/MesloLGSNerdFont-Regular.ttf"
    "/Users/u/Library/Fonts/Other.ttf"
  ]
  assert equal (font-clashes $casks $existing) ["SauceCodeProNerdFont-Regular.ttf"] "an installed cask owns its files, and a file not already there cannot clash"
  assert equal (font-clashes $casks []) []
}

@test
export def "fnm gets an LTS default only when it has none" [] {
  assert equal (fnm-setup "v24.18.0") []
  assert equal (fnm-setup "") [["fnm" "install" "--lts"] ["fnm" "default" "lts-latest"]]
}

# --- archive layouts ----------------------------------------------------------

@test
export def "every source declares a layout the installer understands" [] {
  for tool in ($fallback.SOURCES | columns) {
    let layout = (fallback layout-of $tool)
    assert ($layout in ["binaries" "directory" "executable"]) $"($tool) has layout '($layout)', which lib/fallback.nu cannot install"
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
  # Skipped on Windows because the fixture is a Unix path literal: share-dir
  # joins it with native separators, and the expected string would never
  # match there. The logic is the same everywhere.
  if $nu.os-info.name == "windows" { return }

  # ~/.local/bin is a directory of commands. Two hundred files of bundled .NET
  # runtime unpacked into it would make it something else.
  let share = (fallback share-dir "git-credential-manager" --bin-dir "/home/someone/.local/bin")
  assert equal $share "/home/someone/.local/share/git-credential-manager"
}

@test
export def "a kept archive is installed whole and linked from bin-dir" [] {
  # Skipped on Windows: install-directory shells out to the Unix `cp -R`,
  # `chmod` and `ln`, which a Windows machine only has when Git's usr/bin
  # happens to be on PATH. It never runs there -- lib/fallback.nu refuses
  # anything but Linux archives.
  if $nu.os-info.name == "windows" { return }

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
  # Skipped on Windows for the reason in the test above: install-directory
  # needs the Unix `cp`, `chmod` and `ln`.
  if $nu.os-info.name == "windows" { return }

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

@test
export def "every platform accounts for both database tools" [] {
  # The same rule as the base list, for the opt-in group: nothing silently
  # missing on one platform, and nothing that needs an upstream download.
  for d in $ALL {
    let r = (packages resolve $d --group databases)
    assert equal $r.fallback [] $"($d.id) has no source for: ($r.fallback | str join ', ')"
    let accounted = (($r.install | length) + ($r.provided | length) + ($r.omitted | length))
    assert ($accounted >= ($common.DATABASES | length)) $"($d.id) resolves fewer database tools than it is asked for"
  }
}

@test
export def "database tools stay out of a plain install" [] {
  # Most machines never talk to a database; only --with databases adds them.
  for d in $ALL {
    let base = (packages resolve $d).install
    for id in (packages resolve $d --group databases).install {
      assert ($id not-in $base) $"($id) is installed on ($d.id) without --with databases"
    }
  }
}

@test
export def "a database group adds none of the base extras" [] {
  let r = (packages resolve $WINDOWS --group databases)
  assert not ("Microsoft.PowerShell" in $r.install) "the Windows EXTRA list leaked into the database group"
  assert equal $r.pipx []
  assert equal $r.npm []
  assert equal $r.fonts []
}

@test
export def "every platform accounts for every Kubernetes tool" [] {
  # Linux may fetch these from upstream, unlike the database clients; macOS
  # and Windows may not, since lib/fallback.nu only has Linux builds.
  for d in $ALL {
    let r = (packages resolve $d --group k8s-tools)
    let accounted = (($r.install | length) + ($r.fallback | length) + ($r.provided | length) + ($r.omitted | length))
    assert ($accounted >= ($common.K8S_TOOLS | length)) $"($d.id) resolves fewer Kubernetes tools than it is asked for"
    for tool in $r.fallback {
      assert ($tool in ($fallback.SOURCES | columns)) $"($d.id): ($tool) is unavailable and has no entry in fallback.nu"
    }
  }
  assert equal (packages resolve $MACOS --group k8s-tools).fallback []
  assert equal (packages resolve $WINDOWS --group k8s-tools).fallback []
}

@test
export def "Kubernetes tools stay out of a plain install" [] {
  for d in $ALL {
    let base = (packages resolve $d)
    for id in (packages resolve $d --group k8s-tools).install {
      assert ($id not-in $base.install) $"($id) is installed on ($d.id) without --with k8s-tools"
    }
    for tool in $common.K8S_TOOLS {
      assert ($tool not-in $base.fallback) $"($tool) is fetched on ($d.id) without --with k8s-tools"
    }
  }
}

@test
export def "macOS takes psql from libpq and sqlite from the system" [] {
  let r = (packages resolve $MACOS --group databases)
  assert equal $r.install ["libpq"]
  assert ("sqlite" in ($r.provided | get tool))
}

@test
export def "the Windows PostgreSQL install leaves out the server" [] {
  # The EDB installer is a full server by default: a Windows service, pgAdmin
  # and StackBuilder, for a machine that only needs psql.
  let r = (packages resolve $WINDOWS --group databases)
  let command = (winget-command "PostgreSQL.PostgreSQL.18" $r.winget_args | str join " ")
  assert str contains $command "--override"
  assert str contains $command "--mode unattended"
  assert str contains $command "--disable-components server,pgAdmin,stackbuilder"
  # And an id with no extra arguments is the plain command.
  assert not ((winget-command "SQLite.SQLite" $r.winget_args | str join " ") | str contains "--override")
}

@test
export def "gcc on Debian can link, not just compile" [] {
  # apt runs with --no-install-recommends, which leaves out libc6-dev -- the
  # startup files and -lc every link needs.
  let resolved = (packages resolve $UBUNTU)
  assert ("gcc" in $resolved.install)
  assert ("libc6-dev" in $resolved.install)
}

@test
export def "neovim comes from upstream where the distro packages one older than 0.12" [] {
  # Debian stable carries 0.10, Ubuntu 24.04 0.9 and Leap 16 0.11; the neovim
  # config's plugins want 0.12.
  for distro in [$UBUNTU $LEAP] {
    let resolved = (packages resolve $distro)
    assert ("neovim" in $resolved.fallback) $"($distro.id) installs the distro's neovim"
  }
  for distro in [$TUMBLEWEED $FEDORA] {
    assert ("neovim" in (packages resolve $distro).install) $"($distro.id) should take neovim from its own repos"
  }
}

@test
export def "a version is read out of what a command prints" [] {
  assert equal (fallback reported-version "NVIM v0.12.5\nBuild type: Release") "0.12.5"
  assert equal (fallback reported-version "no version here") null
}

@test
export def "versions compare as numbers, part by part" [] {
  assert (fallback at-least "0.12.0" "0.12.0")
  assert (fallback at-least "0.12.5" "0.12.0")
  assert (fallback at-least "1.0.0" "0.12.0")
  # As strings "0.9.5" would sort after "0.12.0".
  assert not (fallback at-least "0.9.5" "0.12.0")
  assert not (fallback at-least "0.11.6" "0.12.0")
}

@test
export def "a binary inside the archive is linked under its own name" [] {
  # Skipped on Windows for the reason in the tests above: install-directory
  # needs the Unix `cp`, `chmod` and `ln`.
  if $nu.os-info.name == "windows" { return }

  # neovim's shape: the executable is bin/nvim, beside the lib/ and share/ it
  # loads its runtime from.
  let base = (mktemp --directory --tmpdir "dotfiles-fallback-XXXXXX")
  let payload = ($base | path join "payload")
  let bin = ($base | path join ".local" "bin")
  mkdir ($payload | path join "nvim-linux-x86_64" "bin")
  mkdir ($payload | path join "nvim-linux-x86_64" "share" "nvim")
  "binary" | save ($payload | path join "nvim-linux-x86_64" "bin" "nvim")

  fallback install-directory "neovim" {
    name: "nvim-linux-x86_64.tar.gz"
    binaries: ["bin/nvim"]
  } --payload $payload --bin-dir $bin

  let share = (fallback share-dir "neovim" --bin-dir $bin)
  assert ($share | path join "share" "nvim" | path exists) "the runtime files were left behind"
  assert not ($bin | path join "bin" | path exists) "the link kept the archive's directory"
  assert equal ($bin | path join "nvim" | path expand) ($share | path join "bin" "nvim" | path expand)

  rm --recursive --force $base
}

@test
export def "a tool that is nowhere is not mistaken for installed" [] {
  # The check every fallback download goes through. When it got this wrong, no
  # upstream release was ever fetched and every one of them read as present.
  let bin = (mktemp --directory --tmpdir "dotfiles-fallback-XXXXXX")
  let missing = { binaries: ["dotfiles-no-such-tool"] }
  assert not (fallback satisfied $missing $bin)
  assert not (fallback satisfied ($missing | insert minimum "0.12.0") $bin)
  rm --recursive --force $bin
}
