#!/usr/bin/env nu
#
# Set this machine up.
#
#   nu install.nu                     everything
#   nu install.nu --dry-run           show what would happen, change nothing
#   nu install.nu --only links        just one part
#   nu install.nu --only packages,links
#   nu install.nu --with claude       everything, plus an opt-in step
#   nu install.nu --copy              copy files instead of symlinking them
#
# Run bootstrap.sh first on a machine that does not have nushell yet; it
# installs nushell and then calls this.

use lib/log.nu
use lib/distro.nu
use lib/links.nu
use lib/steps.nu
use lib/winpath.nu
use steps/packages.nu
use steps/plugins.nu
use steps/cleanup.nu
use steps/zsh.nu
use steps/neovim.nu
use steps/githooks.nu
use steps/macos.nu
use steps/appdirs.nu
use steps/powershell.nu
use steps/claude.nu

# home/, then whichever platform/ directories match this machine.
#
# One step rather than two, and not by preference: pruning has to see every
# link this repo is about to own at once. Pruned after linking home/ alone, a
# link belonging to a platform directory looks abandoned; pruned per directory,
# each pass would tidy away the others.
#
# Applied in the order `config-names` returns -- linux, then the family, then
# the distribution -- so the more specific directory's file lands last and
# wins. See lib/distro.nu for what that order means.
def link-everything [
  system: record
  --root: path
  --home: path
  --copy
  --dry-run
]: nothing -> nothing {
  log step (if $copy { "Copying dotfiles into place" } else { "Linking dotfiles into place" })

  # Windows does not mirror home/: most of it is zsh, tmux and POSIX shell
  # config with nothing to read it there. What Windows shares arrives through
  # steps/appdirs.nu, one named application at a time.
  let base = (if $system.family == "windows" { [] } else { ["home"] })
  let sources = ($base ++ (distro config-names $system
    | each {|name| $"platform/($name)" }
    | where {|dir| ($root | path join $dir) | path exists }))

  let plans = $sources | each {|dir|
    if $dir != "home" { log info $"($dir) \(this system only)" }
    let plan = (links plan --root $root --home $home --from $dir --copy=$copy)
    links apply $plan --copy=$copy --dry-run=$dry_run --backup-root ($home | path join ".dotfiles-backup")
    { dir: $dir, targets: ($plan | get target) }
  }

  # After linking, not before: a link that is about to be repointed is not
  # stale, it is just out of date. `managed` is every directory's targets, for
  # the reason in the comment above.
  let managed = ($plans | get targets | flatten)
  for entry in $plans {
    links prune (links stale --root $root --home $home --from $entry.dir --managed $managed) --dry-run=$dry_run
  }
}

def --env main [
  --only: string = ""     # comma-separated subset of the steps to run
  --with: string = ""     # comma-separated opt-in steps to add, e.g. claude
  --copy                  # copy files into place instead of symlinking them
  --dry-run               # print what would be done without doing it
  --home: path            # destination root; defaults to this user's home
  --nvim-repo: string = "" # clone the neovim config from here instead of GitHub
] {
  let root = $env.FILE_PWD
  let target = ($home | default $nu.home-dir)
  let bin_dir = ($target | path join ".local" "bin")
  let system = (distro detect)

  # Tools installed during this run land in ~/.local/bin (the Claude Code
  # installer, the upstream fallbacks) or, on Windows, in winget's link
  # directory. Neither reaches an already-running process's PATH, and later
  # steps look for what earlier ones installed -- neovim for claude, the
  # packages step for fnm.
  let prepends = (if $nu.os-info.name == "windows" {
    [($env.LOCALAPPDATA | path join "Microsoft" "WinGet" "Links") $bin_dir]
  } else {
    [$bin_dir]
  })
  $env.PATH = ($env.PATH | prepend $prepends)

  log step $"($system.pretty) \(($system.id), family ($system.family), ($system.manager))"
  if $dry_run { log warn "dry run: nothing will be changed" }
  if $target != $nu.home-dir { log warn $"installing into ($target), not ($nu.home-dir)" }

  if $system.family == "unknown" {
    error make {
      msg: $"($system.pretty) is not a system this repo knows how to install on. Add an overlay in packages/ and a branch in lib/packages.nu."
    }
  }

  let requested = (steps requested --only $only --with $with)
  let run = ($requested | where {|s| steps applies $s $system.family })
  # Said only when it was asked for by name. On a full run, dropping a step
  # that could never apply here is not news.
  if ($only | is-not-empty) {
    for s in ($requested | where {|s| not (steps applies $s $system.family) }) { log skipped (steps platform-note $s) }
  }

  for step in $run {
    match $step {
      "packages" => {
        packages install $system --bin-dir $bin_dir --dry-run=$dry_run
        # MSI installs record themselves only in the registry's PATH; see
        # lib/winpath.nu for why later steps need to see them.
        if $system.family == "windows" { winpath refresh --prepend $prepends }
      }
      "plugins" => (plugins install --home $target --bin-dir $bin_dir --dry-run=$dry_run)
      "cleanup" => (cleanup install $system --dry-run=$dry_run)
      "links" => (link-everything $system --root $root --home $target --copy=$copy --dry-run=$dry_run)
      # After links, which is what puts the config under ~/.config in the
      # first place; this adds the second link for the applications that read
      # it from somewhere else.
      "appdirs" => (appdirs install $system --root $root --home $target --copy=$copy --dry-run=$dry_run)
      "zsh" => (zsh install --home $target --dry-run=$dry_run)
      "neovim" => {
        if ($nvim_repo | is-empty) {
          neovim install $system.family --home $target --dry-run=$dry_run
        } else {
          neovim install $system.family --home $target --repo $nvim_repo --dry-run=$dry_run
        }
      }
      "hooks" => (githooks install --root $root --dry-run=$dry_run)
      "macos" => (macos install --home $target --dry-run=$dry_run)
      "powershell" => (powershell install --home $target --dry-run=$dry_run)
      "claude" => (claude install $system.family --dry-run=$dry_run)
      # An unknown step name should never reach here (steps requested validates
      # against lib/steps.nu's ORDER and OPT_IN), but fail loudly if it does.
      _ => { error make { msg: $"install.nu has no dispatch arm for step '($step)' -- add one" } }
    }
  }

  log step "Done"
  # Not on Windows: nothing there is fetched from upstream releases (see
  # lib/fallback.nu), so the note would point at an empty directory.
  if "packages" in $run and $system.family != "windows" {
    log info $"tools fetched from upstream live in ($bin_dir) -- make sure it is on PATH"
  }
}
