use ../../lib/cleanup.nu
use ../../lib/packages.nu
use std/testing *
use std/assert

const ALL = [
  { id: "opensuse-tumbleweed", family: "suse" }
  { id: "opensuse-leap", family: "suse" }
  { id: "fedora", family: "fedora" }
  { id: "ubuntu", family: "debian" }
]

@test
export def "nothing is installed and removed at the same time" [] {
  # The invariant that makes this step safe to run on every install. Without
  # it, one edit could have the installer put a package on and take it straight
  # back off, or worse, uninstall something the environment needs.
  for distro in $ALL {
    let resolved = (packages resolve $distro)
    let overlap = ($resolved.removed | where {|p| $p in $resolved.install })
    assert equal $overlap [] $"($distro.id) both installs and removes: ($overlap | str join ', ')"
  }
}

@test
export def "only installed packages are considered" [] {
  # A machine that never had the package should not fail the step, and should
  # not have the name passed to the package manager at all.
  let plan = (cleanup plan ["powerline" "ghost"] --installed ["powerline"])

  assert equal $plan.remove ["powerline"]
  assert equal $plan.absent ["ghost"]
}

@test
export def "a package something else needs is kept" [] {
  # The guard that stops a cleanup from turning into an outage: removing
  # powerline here would take vim with it.
  let plan = (cleanup plan ["powerline"]
    --installed ["powerline"]
    --requires { powerline: ["vim"] })

  assert equal $plan.remove []
  assert equal ($plan.kept | get package) ["powerline"]
  assert str contains ($plan.kept | first | get reason) "vim"
}

@test
export def "a group that only depends on itself goes together" [] {
  # powerline's sub-packages require powerline. Treating that as a blocker
  # would make the whole set permanently unremovable, which is the obvious way
  # to get this wrong.
  let plan = (cleanup plan ["powerline" "tmux-powerline" "vim-plugin-powerline"]
    --installed ["powerline" "tmux-powerline" "vim-plugin-powerline"]
    --requires { powerline: ["tmux-powerline" "vim-plugin-powerline"] })

  assert equal ($plan.remove | sort) ["powerline" "tmux-powerline" "vim-plugin-powerline"]
  assert equal $plan.kept []
}

@test
export def "a protected package is never removed" [] {
  # Second line of defence behind the overlap test above: even if a bad edit
  # put a name on both lists, it must be inert here.
  let plan = (cleanup plan ["starship"]
    --installed ["starship"]
    --protected ["starship"])

  assert equal $plan.remove []
  assert str contains ($plan.kept | first | get reason) "install list"
}

@test
export def "removal never widens beyond what was asked" [] {
  # --clean-deps, --autoremove and friends pull in packages nobody listed.
  # That is the opposite of what this step is for.
  for family in ["suse" "fedora" "debian"] {
    let command = (cleanup remove-command $family ["powerline"] | str join " ")
    assert not ($command =~ 'clean-deps|autoremove|--purge') $"($family) removal widens the transaction: ($command)"
  }
}

@test
export def "an empty removal list produces no command" [] {
  assert equal (cleanup remove-command "suse" []) []
}

@test
export def "removal is non-interactive" [] {
  assert str contains (cleanup remove-command "suse" ["x"] | str join " ") "--non-interactive"
  assert str contains (cleanup remove-command "fedora" ["x"] | str join " ") "-y"
  assert str contains (cleanup remove-command "debian" ["x"] | str join " ") "-y"
}

@test
export def "an unknown family cannot remove anything" [] {
  assert error {|| cleanup remove-command "plan9" ["x"] }
  assert equal (cleanup installed? "plan9" "anything") false
}
