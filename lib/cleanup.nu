# Removing packages this repo used to install and no longer wants.
#
# Uninstalling is the one thing here that can break a working machine, so it is
# built to be boring. Three rules, each enforced rather than merely intended:
#
#   1. Only names written down in an overlay's REMOVED list are ever passed to
#      the package manager. Nothing is inferred, and "looks unused" is not a
#      reason.
#   2. A package that something else still depends on is left alone. Removing
#      it would take the dependent with it, which is how a cleanup step turns
#      into an outage.
#   3. A package cannot be in both REMOVED and the install list.
#      tests/unit/cleanup.nu fails the build if that ever becomes true, so the
#      two lists cannot drift into fighting each other.

use log.nu

# Is this package installed right now?
#
# Asked before removing anything, so a clean machine does not fail the step by
# being told to remove something it never had.
export def installed? [family: string, package: string]: nothing -> bool {
  match $family {
    "suse" | "fedora" => ((do { ^rpm --query $package } | complete).exit_code == 0)
    "debian" => {
      let result = (do { ^dpkg-query --show --showformat '${Status}' $package } | complete)
      $result.exit_code == 0 and ($result.stdout | str contains "install ok installed")
    }
    _ => false
  }
}

# Installed packages that require this one.
#
# rpm answers this directly. dpkg needs apt-cache, which lists every reverse
# dependency it knows about, so --installed is doing real work there.
export def reverse-deps [family: string, package: string]: nothing -> list<string> {
  match $family {
    "suse" | "fedora" => {
      # --queryformat matters: rpm's default output is full NEVRA
      # ("tmux-powerline-2.8.4-3.5.noarch"), which would never compare equal to
      # the plain package names everywhere else, so every package would look
      # permanently blocked.
      let result = (do { ^rpm --query --whatrequires $package --queryformat '%{NAME}\n' } | complete)
      if $result.exit_code != 0 { return [] }   # "no package requires ..." exits non-zero
      $result.stdout | lines | each {|l| $l | str trim } | where {|l| $l | is-not-empty } | uniq
    }
    "debian" => {
      let result = (do { ^apt-cache rdepends --installed --no-recommends --no-suggests $package } | complete)
      if $result.exit_code != 0 { return [] }
      $result.stdout
      | lines
      | skip 2                                   # the header and the package's own name
      | each {|l| $l | str trim | str replace --regex '^\|' '' | str trim }
      | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "Reverse Depends")) }
      | uniq
    }
    _ => []
  }
}

# Everything the decision needs, read from the system once.
#
# Separated from `plan` so that the decision itself is a pure function of these
# facts, and can be tested without a package manager, a container, or any
# particular distribution being installed.
export def gather [family: string, candidates: list<string>]: nothing -> record {
  let present = ($candidates | where {|p| installed? $family $p })

  {
    installed: $present
    requires: ($present | reduce --fold {} {|package, acc|
      $acc | insert $package (reverse-deps $family $package)
    })
  }
}

# Decide what may actually go.
#
# Split rather than filtered, so the step can say out loud what it declined to
# touch. A cleanup that silently skips things teaches you to stop reading it.
export def plan [
  candidates: list<string>
  --installed: list<string> = []    # which candidates are actually present
  --requires: record = {}           # package -> installed packages needing it
  --protected: list<string> = []    # never remove these, whatever else is true
]: nothing -> record {
  let present = ($candidates | where {|p| $p in $installed })

  let decided = $present | each {|package|
    if $package in $protected {
      { package: $package, remove: false, reason: "it is on the install list for this system" }
    } else {
      # A dependent that is itself on the way out is not a reason to stop --
      # the whole group goes together. That is what lets the five powerline
      # packages, which depend on each other, be removed at all.
      let holders = ($requires
        | get --optional $package
        | default []
        | where {|d| $d not-in $present })

      if ($holders | is-not-empty) {
        { package: $package, remove: false, reason: $"($holders | str join ', ') still requires it" }
      } else {
        { package: $package, remove: true, reason: "" }
      }
    }
  }

  {
    remove: ($decided | where remove | get package)
    kept: ($decided | where {|d| not $d.remove } | select package reason)
    absent: ($candidates | where {|p| $p not-in $present })
  }
}

export def remove-command [family: string, packages: list<string>]: nothing -> list<string> {
  if ($packages | is-empty) { return [] }
  match $family {
    # No --clean-deps / --autoremove anywhere here on purpose. Those widen the
    # transaction beyond what was asked for, which is the opposite of what this
    # step is trying to be.
    "suse" => (["sudo" "zypper" "--non-interactive" "remove"] ++ $packages)
    "fedora" => (["sudo" "dnf" "remove" "-y"] ++ $packages)
    "debian" => (["sudo" "apt-get" "remove" "-y"] ++ $packages)
    _ => { error make { msg: $"no remove command for family '($family)'" } }
  }
}
