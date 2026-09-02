#!/usr/bin/env nu
#
# Install this repo into a container and drop you into it, so you can actually
# use the environment before putting it on a real machine.
#
#   nu tests/container/try.nu                     openSUSE Tumbleweed
#   nu tests/container/try.nu --distro ubuntu     somewhere else
#   nu tests/container/try.nu --shell nu          land in nushell instead of zsh
#   nu tests/container/try.nu --rebuild           reinstall from scratch
#
# The first run installs everything and takes a few minutes. It then snapshots
# the result as an image, so every later run starts in about a second. --rebuild
# throws that snapshot away, which is what you want after changing the repo.
#
# Nothing you do inside survives leaving the shell: the container is discarded
# on exit and the snapshot is rebuilt from the repo, not from your session. It
# is a place to try things, not to keep them.

const HERE = (path self | path dirname)
const REPO = (path self | path dirname | path dirname | path dirname)

use ../../lib/log.nu
use lib.nu

def snapshot-tag [distro: string]: nothing -> string {
  $"dotfiles-try:($distro)"
}

def snapshot-exists [tag: string]: nothing -> bool {
  (do { ^podman image exists $tag } | complete).exit_code == 0
}

# The working-tree fingerprint the snapshot was built from, or "" if there is
# no snapshot or it predates this labelling.
def snapshot-revision [tag: string]: nothing -> string {
  if not (snapshot-exists $tag) { return "" }

  let result = (do {
    ^podman image inspect --format '{{ index .Config.Labels "dotfiles.revision" }}' $tag
  } | complete)

  if $result.exit_code != 0 { return "" }

  let value = ($result.stdout | str trim)
  # podman prints "<no value>" for a label that was never set.
  if $value == "<no value>" { "" } else { $value }
}

# Install into a named container, then commit it as an image.
#
# Committing is what makes this pleasant to use twice. Reinstalling from
# mirrors every time you want to look at the prompt would make the whole thing
# not worth reaching for.
def prepare [distro: string, tag: string, revision: string]: nothing -> nothing {
  let built = (lib build $distro $HERE)
  if not $built.ok {
    error make { msg: $"could not build the ($distro) image" }
  }

  let staging = (lib stage $REPO)
  log step $"Staged the working tree into ($staging)"

  let nvim = (lib nvim-source)
  if ($nvim | is-not-empty) {
    log info $"cloning the neovim config from ($nvim)"
  } else {
    log warn "no local neovim checkout found; the container will try GitHub"
  }

  let name = $"dotfiles-try-($distro)"
  # A container left behind by an interrupted run would make `podman run
  # --name` fail with a name clash rather than doing anything useful.
  do { ^podman rm --force $name } | complete | ignore

  log step $"Installing into ($distro) -- this takes a few minutes the first time"

  let args = (["run" "--name" $name] ++ (lib mounts $staging $nvim) ++ [
    $built.tag "sh" "-c" (lib install-script $nvim)
  ])
  let result = (lib stream $args)

  rm --recursive --force $staging

  if not $result.ok {
    # Everything the install printed has already been on screen.
    do { ^podman rm --force $name } | complete | ignore
    error make { msg: $"the install failed inside the ($distro) container" }
  }

  log step $"Snapshotting as ($tag)"
  # The fingerprint rides along on the image, so the next run can tell whether
  # this snapshot still matches the repo without keeping state on the side.
  #
  # Deliberately not `complete | ignore`, which this once was. A commit that
  # fails has to fail loudly: swallowed, the snapshot silently never existed
  # and the next run reinstalled from scratch with nothing on screen to say
  # why. Should it fail, the container is left behind and removed by the
  # `podman rm --force` at the top of the next run.
  ^podman commit --change $"LABEL dotfiles.revision=($revision)" $name $tag
  do { ^podman rm --force $name } | complete | ignore
}

def main [
  --distro: string = "tumbleweed"   # which distribution to try
  --shell: string = "zsh"           # shell to land in: zsh, bash or nu
  --rebuild                         # discard the snapshot and install again
] {
  if (which podman | is-empty) {
    error make { msg: "podman is not installed" }
  }

  if $distro not-in $lib.DISTROS {
    error make { msg: $"unknown distro '($distro)' -- pick from ($lib.DISTROS | str join ', ')" }
  }

  let tag = (snapshot-tag $distro)
  let revision = (lib revision $REPO)
  let snapshot = (snapshot-revision $tag)

  # Reinstall when the repo has moved on. Reusing a snapshot silently is the
  # obvious way to make this tool lie: you change something, run it, and are
  # handed the environment from before the change with nothing on screen to say
  # so.
  let stale = ((snapshot-exists $tag) and ($snapshot != $revision))

  if ($rebuild or $stale) and (snapshot-exists $tag) {
    if $stale and (not $rebuild) {
      log step $"The repo has changed since ($tag) was built -- reinstalling"
    } else {
      log step $"Discarding the existing ($tag) snapshot"
    }
    do { ^podman rmi --force $tag } | complete | ignore
  }

  if not (snapshot-exists $tag) {
    prepare $distro $tag $revision
  } else {
    log skipped $"($tag) is up to date with the repo -- starting it"
  }

  # -l so the shell reads the profile and the prompt, which is the whole point.
  let command = match $shell {
    "zsh" => ["zsh" "-l"]
    "bash" => ["bash" "-l"]
    "nu" => ["nu" "--login"]
    _ => { error make { msg: $"unknown shell '($shell)' -- pick zsh, bash or nu" } }
  }

  log step $"Starting ($shell) in ($distro). Type exit when you are done."
  print ""

  # --interactive --tty, and not captured: this hands the terminal over.
  ^podman run --interactive --tty --rm ...(["--hostname" $"dotfiles-($distro)" $tag]) ...$command
}
