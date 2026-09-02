#!/usr/bin/env nu
#
# Install this repo from scratch in a container per distribution, and check the
# result.
#
#   nu tests/container/run.nu                      all of them
#   nu tests/container/run.nu --distro fedora      just one
#   nu tests/container/run.nu --keep               leave the containers behind
#
# This is the slow layer. It downloads real packages from real mirrors, so it
# takes minutes and needs network. It is also the only thing that can tell you
# whether "python313-pipx" is a package that exists on Leap -- the unit tests
# can only check that the mapping is internally consistent.
#
# To poke at one of these environments by hand instead, use try.nu.

const HERE = (path self | path dirname)
const REPO = (path self | path dirname | path dirname | path dirname)

use ../../lib/log.nu
use lib.nu

def run-one [distro: string, staging: path, nvim: string, --keep]: nothing -> record {
  let built = (lib build $distro $HERE)
  if not $built.ok {
    return { distro: $distro, stage: "build", ok: false, output: $built.output }
  }

  log step $"Installing into ($distro)"

  let flags = (if $keep { [] } else { ["--rm"] })
  let script = (lib install-script $nvim "nu tests/container/verify.nu")
  let args = (["run"] ++ $flags ++ (lib mounts $staging $nvim) ++ [$built.tag "sh" "-c" $script])

  let result = (lib stream $args)

  { distro: $distro, stage: "install", ok: $result.ok, output: $result.output }
}

def main [
  --distro: string = ""   # only this one
  --keep                  # do not remove the containers afterwards
] {
  if (which podman | is-empty) {
    error make { msg: "podman is not installed -- this is the layer that needs it" }
  }

  let targets = (if ($distro | is-empty) {
    $lib.DISTROS
  } else if ($distro in $lib.DISTROS) {
    [$distro]
  } else {
    error make { msg: $"unknown distro '($distro)' -- pick from ($lib.DISTROS | str join ', ')" }
  })

  let staging = (lib stage $REPO)
  log step $"Staged the working tree into ($staging)"

  let nvim = (lib nvim-source)
  if ($nvim | is-not-empty) {
    log info $"cloning the neovim config from ($nvim)"
  } else {
    log warn "no local neovim checkout found; the container will try GitHub"
  }

  let results = ($targets | each {|d| run-one $d $staging $nvim --keep=$keep })

  rm --recursive --force $staging

  print ""
  log step "Results"
  for r in $results {
    if $r.ok {
      print $"  (ansi green)pass(ansi reset)  ($r.distro)"
      # verify.nu's per-check report, which is the interesting part.
      print ($r.output | lines | where {|l| $l =~ '(pass|FAIL|checks,)' } | each {|l| $"        ($l)" } | str join "\n")
    } else {
      print $"  (ansi red)FAIL(ansi reset)  ($r.distro) \(during ($r.stage))"
      print ($r.output | lines | last 80 | each {|l| $"        ($l)" } | str join "\n")
    }
  }

  let failed = ($results | where {|r| not $r.ok })
  print ""
  print $"($results | length) distributions, ($failed | length) failed"
  if ($failed | is-not-empty) { exit 1 }
}
