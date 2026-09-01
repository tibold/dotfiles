# Putting the contents of home/ into $HOME.
#
# The mapping is mechanical and has no manifest: every file under home/ is
# placed at the same relative path under $HOME. `home/.config/lazygit/
# config.yml` becomes `~/.config/lazygit/config.yml`. Adding a config means
# adding a file, and nothing can fall out of sync with a list because there is
# no list.
#
# Symlinks are the default rather than copies so that edits made in $HOME land
# in the repo, `git status` shows drift, and `git pull` updates the live config
# without re-running anything. --copy exists for the two cases where that is
# wrong: a tool that rewrites its config in place (clobbering the link), and a
# machine where the checkout should not be load-bearing.

use log.nu

# readlink, as a question rather than an error.
#
# Returns the link's target, or null if the path is not a symlink. This is used
# instead of `path type` because `path exists` and friends follow symlinks, so
# they cannot tell "no file here" apart from "a link here pointing at nothing"
# -- and a dangling link left by an earlier run is exactly what we need to
# replace.
def link-target [p: path]: nothing -> any {
  let result = (do { ^readlink $p } | complete)
  if $result.exit_code == 0 { $result.stdout | str trim } else { null }
}

def classify [source: path, target: path]: nothing -> string {
  let existing = (link-target $target)

  if $existing != null {
    if ($existing | path expand) == ($source | path expand) { "ok" } else { "relink" }
  } else if ($target | path exists) {
    # A real file or directory is in the way. Never silently destroyed: a fresh
    # Ubuntu ships its own ~/.bashrc and ~/.profile, and losing local edits to
    # them to a first install would be a nasty surprise.
    "backup"
  } else {
    "create"
  }
}

# What linking would do, as data. install.nu prints this for --dry-run and the
# container tests assert against it, so the plan and the action cannot diverge.
export def plan [
  --root: path        # repo root
  --home: path        # destination root, normally $nu.home-path
  --copy              # plan copies rather than symlinks
]: nothing -> table {
  let source_root = ($root | path join "home")

  if not ($source_root | path exists) {
    error make { msg: $"($source_root) does not exist -- is --root the repo root?" }
  }

  glob ($source_root | path join "**" "*") --no-dir
  | each {|source|
      let relative = ($source | path relative-to $source_root)
      let target = ($home | path join $relative)
      {
        relative: $relative
        source: $source
        target: $target
        # In copy mode an identical symlink is still wrong, so "ok" only
        # applies to linking.
        action: (if $copy { copy-classify $source $target } else { classify $source $target })
      }
    }
  | sort-by relative
}

def copy-classify [source: path, target: path]: nothing -> string {
  # A symlink in the target position must be removed before copying, otherwise
  # cp writes *through* it and edits the repo instead of the home directory.
  if (link-target $target) != null {
    "unlink-then-copy"
  } else if not ($target | path exists) {
    "create"
  } else if (open --raw $target) == (open --raw $source) {
    # Already our copy, byte for byte. Without this check copy mode would have
    # no idempotency: every run would treat its own output as a stranger's file
    # and back it up again.
    "ok"
  } else {
    # Someone else's file, or our copy with local edits. Copy mode treats the
    # repo as the source of truth, but the displaced content is kept -- the
    # same promise link mode makes, which it would otherwise quietly break.
    "backup"
  }
}

export def apply [
  rows: table
  --copy
  --dry-run
  --backup-root: path
]: nothing -> nothing {
  let stamp = (date now | format date "%Y%m%d-%H%M%S")
  let backup_dir = ($backup_root | path join $stamp)

  for row in $rows {
    match $row.action {
      "ok" => { log skipped $"($row.relative) already linked" }

      "backup" => {
        let saved = ($backup_dir | path join $row.relative)
        if $dry_run {
          log info $"would move ($row.target) to ($saved), then link"
        } else {
          mkdir ($saved | path dirname)
          mv --force $row.target $saved
          log warn $"($row.relative) existed; saved to ($saved)"
          place $row --copy=$copy
        }
      }

      "unlink-then-copy" => {
        if $dry_run {
          log info $"would remove the symlink at ($row.target), then copy"
        } else {
          rm --force $row.target
          place $row --copy=$copy
        }
      }

      _ => {
        if $dry_run {
          log info $"would ($row.action) ($row.relative)"
        } else {
          place $row --copy=$copy
        }
      }
    }
  }
}

def place [row: record, --copy]: nothing -> nothing {
  mkdir ($row.target | path dirname)
  if $copy {
    cp --force $row.source $row.target
  } else {
    # -n so that a target which is a symlink to a directory is replaced rather
    # than followed into; -f so an existing link is overwritten.
    ^ln -sfn $row.source $row.target
  }
  log ok $row.relative
}

# Links this repo left behind that no longer point at anything.
#
# When a config is dropped from home/, the symlink in $HOME outlives it and
# becomes a link to nothing. That is worse than no link at all: most tools read
# a dangling symlink as an absent file and start subtly differently, with
# nothing on screen to say why.
#
# The rule is deliberately narrow, because deleting things in someone's home
# directory deserves to be. A link is stale only if BOTH hold:
#
#   * it points somewhere inside this repository, so we are the ones who made
#     it -- a link to /etc or to another checkout is not ours to remove; and
#   * its target no longer exists, so nothing can be reading it usefully.
#
# A real file is never touched, and neither is a link that still resolves.
#
# `managed` holds the paths the current plan is about to write. They are
# excluded even when they currently dangle: a link waiting to be repointed at
# its new location is out of date, not abandoned, and under --dry-run it has
# not been repointed yet.
#
# Only the directories that home/ mirrors are searched, rather than all of
# $HOME: those are the only places this repo has ever created a link, and
# walking a whole home directory to find a handful of them would be slow and
# far too eager.
export def stale [
  --root: path
  --home: path
  --managed: list<path> = []
]: nothing -> table {
  let source_root = ($root | path join "home")

  let search = (glob ($source_root | path join "**" "*") --no-file
    | append $source_root
    | each {|dir|
        let relative = ($dir | path relative-to $source_root)
        if ($relative | is-empty) { $home } else { $home | path join $relative }
      }
    | where {|dir| $dir | path exists }
    | uniq)

  $search
  | each {|dir|
      # --all matters more here than anywhere else in this file: everything
      # this repo installs is a dotfile, so the default listing hides all of
      # it and every directory looks empty.
      ls --all --long $dir
      | where type == symlink
      | where {|entry| ($entry.target | path expand --no-symlink | str starts-with $root) }
      | where {|entry| not ($entry.target | path exists) }
      | where {|entry| $entry.name not-in $managed }
      | each {|entry| { target: $entry.name, points_at: $entry.target } }
    }
  | flatten
}

export def prune [rows: table, --dry-run]: nothing -> nothing {
  for row in $rows {
    if $dry_run {
      log info $"would remove the dead link ($row.target) -> ($row.points_at)"
    } else {
      rm --force $row.target
      log ok $"removed dead link ($row.target)"
    }
  }
}
