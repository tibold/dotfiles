#!/usr/bin/env nu
#
# Set this machine up.
#
#   nu install.nu                     everything
#   nu install.nu --dry-run           show what would happen, change nothing
#   nu install.nu --only links        just one part
#   nu install.nu --only packages,links
#   nu install.nu --copy              copy files instead of symlinking them
#
# Run bootstrap.sh first on a machine that does not have nushell yet; it
# installs nushell and then calls this.

use lib/log.nu
use lib/distro.nu
use lib/links.nu
use steps/packages.nu
use steps/plugins.nu
use steps/cleanup.nu
use steps/zsh.nu
use steps/neovim.nu
use steps/githooks.nu

# Order matters. Packages come first because later steps need the tools they
# install -- git for the clones, gitleaks for the hook check, the plugin
# binaries for the registration.
const STEPS = ["packages" "plugins" "cleanup" "links" "zsh" "neovim" "hooks"]

def parse-only [only: string]: nothing -> list<string> {
  if ($only | is-empty) { return $STEPS }

  let wanted = ($only | split row "," | each {|s| $s | str trim } | where {|s| $s | is-not-empty })
  let unknown = ($wanted | where {|s| $s not-in $STEPS })

  if ($unknown | is-not-empty) {
    error make {
      msg: $"unknown step\(s): ($unknown | str join ', ') -- pick from ($STEPS | str join ', ')"
    }
  }

  # Keep the canonical order regardless of the order they were typed in.
  $STEPS | where {|s| $s in $wanted }
}

def main [
  --only: string = ""     # comma-separated subset of the steps to run
  --copy                  # copy files into place instead of symlinking them
  --dry-run               # print what would be done without doing it
  --home: path            # destination root; defaults to this user's home
  --nvim-repo: string = "" # clone the neovim config from here instead of GitHub
] {
  let root = $env.FILE_PWD
  let target = ($home | default $nu.home-dir)
  let bin_dir = ($target | path join ".local" "bin")
  let steps = (parse-only $only)
  let system = (distro detect)

  log step $"($system.pretty) \(($system.id), family ($system.family), ($system.manager))"
  if $dry_run { log warn "dry run: nothing will be changed" }
  if $target != $nu.home-dir { log warn $"installing into ($target), not ($nu.home-dir)" }

  if $system.family == "unknown" {
    error make {
      msg: $"($system.pretty) is not a distribution this repo knows how to install on. Add an overlay in packages/ and a branch in lib/packages.nu."
    }
  }

  for step in $steps {
    match $step {
      "packages" => (packages install $system --bin-dir $bin_dir --dry-run=$dry_run)
      "plugins" => (plugins install --home $target --bin-dir $bin_dir --dry-run=$dry_run)
      "cleanup" => (cleanup install $system --dry-run=$dry_run)
      "links" => {
        log step (if $copy { "Copying dotfiles into place" } else { "Linking dotfiles into place" })
        let plan = (links plan --root $root --home $target --copy=$copy)
        links apply $plan --copy=$copy --dry-run=$dry_run --backup-root ($target | path join ".dotfiles-backup")

        # After linking, not before: a link that is about to be repointed is
        # not stale, it is just out of date.
        links prune (links stale --root $root --home $target --managed ($plan | get target)) --dry-run=$dry_run
      }
      "zsh" => (zsh install --home $target --dry-run=$dry_run)
      "neovim" => {
        if ($nvim_repo | is-empty) {
          neovim install --home $target --dry-run=$dry_run
        } else {
          neovim install --home $target --repo $nvim_repo --dry-run=$dry_run
        }
      }
      "hooks" => (githooks install --root $root --dry-run=$dry_run)
    }
  }

  log step "Done"
  if "packages" in $steps {
    log info $"tools fetched from upstream live in ($bin_dir) -- make sure it is on PATH"
  }
}
