# Which distribution we are on, and what that implies.
#
# Two identifiers matter downstream and they are deliberately not the same
# thing:
#
#   family  what the package manager and most package names key off. Leap and
#           Tumbleweed are both "suse"; Ubuntu and Debian are both "debian".
#   id      the exact ID= from os-release. Only consulted where two members of
#           a family genuinely diverge, which in practice is Leap vs Tumbleweed
#           -- Leap's repos are years behind and simply lack some of these
#           tools.

# Parse os-release into a flat record.
#
# The file is shell syntax in principle, but in practice a KEY=VALUE list with
# optional quotes and comments. Parsing it directly rather than sourcing it
# means this works identically inside a nushell script and inside a test, with
# no shell-out and no chance of the file executing something.
export def parse-os-release [text: string]: nothing -> record {
  $text
  | lines
  | each {|l| $l | str trim }
  | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "#")) and ($l | str contains "=") }
  | reduce --fold {} {|line, acc|
      let key = ($line | split row "=" | first | str trim)
      # Split on the FIRST "=" only: values such as CPE_NAME legitimately
      # contain more of them.
      let value = ($line
        | str replace --regex '^[^=]*=' ''
        | str trim
        | str trim --char '"'
        | str trim --char "'")
      $acc | insert $key $value
    }
}

# Collapse an ID plus its ID_LIKE list into one of the families we support.
#
# ID_LIKE is what makes derivatives work without listing every one of them:
# Linux Mint says ID_LIKE=ubuntu, Rocky says ID_LIKE="rhel centos fedora".
#
# macOS is deliberately not answerable here. It has no os-release file, so it
# never reaches this function -- `detect` recognises it before parsing anything
# and builds the record itself. Adding a "macos" case would be a branch nothing
# can take, which is worse than its absence: it would read as though something
# does.
export def family-of [id: string, id_like: list<string>]: nothing -> string {
  let names = ([$id] ++ $id_like)
  if (($names | any {|n| $n in ["opensuse" "opensuse-leap" "opensuse-tumbleweed" "suse" "sles" "sled"]})) {
    "suse"
  } else if (($names | any {|n| $n in ["fedora" "rhel" "centos" "rocky" "almalinux"]})) {
    "fedora"
  } else if (($names | any {|n| $n in ["debian" "ubuntu"]})) {
    "debian"
  } else {
    "unknown"
  }
}

export def manager-of [family: string]: nothing -> string {
  match $family {
    "suse" => "zypper"
    "fedora" => "dnf"
    "debian" => "apt-get"
    "macos" => "brew"
    _ => "unknown"
  }
}

# Turn a parsed os-release record into the shape the rest of the code uses.
export def describe [os: record]: nothing -> record {
  let id = ($os | get --optional ID | default "unknown")
  let id_like = ($os
    | get --optional ID_LIKE
    | default ""
    | split row " "
    | where {|s| $s | is-not-empty })
  let family = (family-of $id $id_like)

  {
    id: $id
    version: ($os | get --optional VERSION_ID | default "")
    pretty: ($os | get --optional PRETTY_NAME | default $id)
    family: $family
    manager: (manager-of $family)
  }
}

# The same record, for macOS, which has nothing to parse.
#
# There is one vendor, one package manager and one name, so the only thing
# actually read from the system is the version -- and that is taken as an
# argument rather than run in here, so the shape of the record can be tested
# without being on a Mac.
#
# "macos" is both the id and the family. The id/family split earns its keep on
# Linux, where Leap and Tumbleweed share a package manager and disagree about
# what is in it; there is no equivalent division here. Should one appear --
# some future release dropping a formula this list needs -- it is the same
# move the Leap overlay already makes: give the id its own entry in
# lib/packages.nu and leave the family alone.
export def describe-macos [version: string]: nothing -> record {
  {
    id: "macos"
    version: $version
    pretty: (if ($version | is-empty) { "macOS" } else { $"macOS ($version)" })
    family: "macos"
    manager: (manager-of "macos")
  }
}

export def detect [--file: path = "/etc/os-release"]: nothing -> record {
  # Asked of the running nushell rather than by looking for /etc/os-release and
  # inferring macOS from its absence. A Linux box with an unreadable or missing
  # os-release is a broken Linux box, and should say so, not be quietly treated
  # as a Mac.
  if $nu.os-info.name == "macos" {
    let version = (do { ^sw_vers -productVersion } | complete)
    return (describe-macos (if $version.exit_code == 0 { $version.stdout | str trim } else { "" }))
  }

  if not ($file | path exists) {
    error make { msg: $"($file) does not exist -- cannot identify this system" }
  }
  describe (parse-os-release (open --raw $file))
}

# The names a platform directory can carry for this system, least specific
# first.
#
# platform/<name>/ mirrors $HOME exactly the way home/ does, and is linked only
# where <name> matches the machine. Three names can match, from broad to exact:
#
#   linux, macos                      the operating system
#   debian, suse, fedora, macos       the package manager family
#   ubuntu, opensuse-leap, macos      the distribution itself
#
# Returned in that order, and applied in it, so a file in the more specific
# directory wins over the same path in a broader one. On macOS all three are
# "macos", which collapses to a single entry.
#
# This is what makes a per-system setting possible at all for the file formats
# that have no condition of their own. git is the case in hand: includeIf can
# ask about a directory, a branch or a remote, but not about which machine it
# is running on -- while a plain `[include] path` of a file that does not exist
# is silently ignored. So the platform directory decides which file exists.
export def config-names [system: record]: nothing -> list<string> {
  let os = (if $system.family == "macos" { "macos" } else { "linux" })
  [$os, $system.family, $system.id] | uniq
}

# argv to refresh the package index before installing.
#
# Only apt genuinely requires this -- it will fail to find packages that exist
# if the lists are stale, which is the normal state of a fresh container image.
# zypper and dnf refresh themselves as needed, so they get a no-op rather than
# an expensive redundant sync.
#
# So does brew: it auto-updates before an install unless told not to, so a
# `brew update` here would be the same fetch run twice.
export def refresh-command [family: string]: nothing -> list<string> {
  match $family {
    "debian" => ["sudo" "apt-get" "update"]
    _ => []
  }
}

export def install-command [family: string, packages: list<string>]: nothing -> list<string> {
  if ($packages | is-empty) { return [] }
  match $family {
    "suse" => (["sudo" "zypper" "--non-interactive" "install" "--auto-agree-with-licenses"] ++ $packages)
    "fedora" => (["sudo" "dnf" "install" "-y"] ++ $packages)
    "debian" => (["sudo" "apt-get" "install" "-y" "--no-install-recommends"] ++ $packages)
    # No sudo, and that is not an oversight: Homebrew refuses to run as root,
    # and does not need to -- its prefix is owned by the user who installed it.
    # Nor is there a --yes to pass: installing a formula asks nothing.
    "macos" => (["brew" "install"] ++ $packages)
    _ => { error make { msg: $"no install command for family '($family)'" } }
  }
}

# Homebrew's other half.
#
# Casks are applications and fonts rather than command-line packages, and they
# are installed by a different subcommand, so they cannot simply be appended to
# the list above. Only macOS has them; anywhere else, being asked for one is a
# bug in an overlay rather than something to paper over.
export def cask-install-command [family: string, casks: list<string>]: nothing -> list<string> {
  if ($casks | is-empty) { return [] }
  match $family {
    # --adopt, because a cask refuses to install over files it did not put
    # there and a font is exactly the thing someone has already installed by
    # hand:
    #
    #   Error: It seems there is already a Font at
    #   '~/Library/Fonts/MesloLGLDZNerdFont-Bold.ttf'
    #
    # --adopt takes ownership of the artifacts that are byte-identical to the
    # ones in the cask, which turns that into a normal install and makes a
    # machine with the font already on it converge rather than fail.
    #
    # Deliberately not --force, which is the other way out of the same message:
    # it overwrites whatever is there. Nothing else in this repo destroys a file
    # it did not create -- that is what ~/.dotfiles-backup exists for -- and a
    # font that is *not* identical is a font someone chose, so it should stop
    # and say so.
    "macos" => (["brew" "install" "--cask" "--adopt"] ++ $casks)
    _ => { error make { msg: $"casks are a Homebrew concept -- family '($family)' has none, so this list should be empty" } }
  }
}

# Installing a global npm package.
#
# Whether this needs sudo is a property of where npm's prefix is, which is a
# property of how node was installed -- so it belongs next to the other
# per-family commands rather than inline in the step.
#
# On the Linux side node comes from the distro and its prefix is /usr, which
# needs root. Homebrew's prefix is owned by this user, and running npm under
# sudo there writes root-owned files into it that the next un-elevated npm
# cannot update.
export def npm-global-command [family: string, packages: list<string>]: nothing -> list<string> {
  if ($packages | is-empty) { return [] }
  # -g matters wherever it runs: without it npm treats the current directory as
  # a project and writes a node_modules tree into whatever we happen to be
  # standing in.
  let install = ["npm" "install" "--global"]
  match $family {
    "macos" => ($install ++ $packages)
    _ => (["sudo"] ++ $install ++ $packages)
  }
}
