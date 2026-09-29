# ~/.gitconfig, owned by the machine rather than by this repo.
#
# It used to be a link to this repo's copy, which meant every
# `git config --global` a tool ran -- Git Credential Manager adding a host,
# say -- was written through the link into the repo, where it either got
# committed to every machine or sat as a local change forever. Now the shared
# settings live in home/.config/git/shared.conf, linked like any other config,
# and ~/.gitconfig is a real file that starts with an include for it and for
# the per-system platform.conf. Tools append below that, and what they write
# wins over both, because git applies an include where it appears.
#
# Runs after links and appdirs, which are what put shared.conf and
# platform.conf in place.

use ../lib/log.nu
use ../lib/links.nu

# Shared first, then the per-system file, so a platform setting overrides a
# shared one. An include naming a file that does not exist is ignored, which is
# what makes platform.conf's presence the condition -- see "Per-system
# settings" in the README.
export const INCLUDES = ["~/.config/git/shared.conf" "~/.config/git/platform.conf"]

export def header []: nothing -> string {
  [
    "# Added by dotfiles (nu install.nu --only gitconfig): the settings every machine"
    "# shares, then the ones for this kind of machine. Anything below here is this"
    "# machine's own and overrides both."
    "[include]"
    ...($INCLUDES | each {|p| $"\tpath = ($p)" })
  ] | str join "\n"
}

# Whether a gitconfig already includes every file in INCLUDES.
export def has-includes [text: string]: nothing -> bool {
  let paths = ($text
    | lines
    | each {|l| $l | str trim }
    | where {|l| $l =~ '^path\s*=' }
    | each {|l| $l | str replace --regex '^path\s*=\s*' '' | str trim })
  $INCLUDES | all {|p| $p in $paths }
}

# What to do about ~/.gitconfig: ok, create, prepend, migrate (it is still the
# old link into this repo), or foreign-link (a link to somewhere else, which is
# not ours to write through).
export def classify [file: path, --root: path]: nothing -> string {
  let target = (links link-target $file)
  if $target != null {
    # A relative target is relative to the link's own directory.
    let resolved = ($file | path dirname | path join $target)
    return (if (links is-inside $resolved $root) { "migrate" } else { "foreign-link" })
  }
  if not ($file | path exists) { return "create" }
  if (has-includes (open --raw $file)) { "ok" } else { "prepend" }
}

export def install [--root: path, --home: path, --dry-run]: nothing -> nothing {
  log step "Git config"
  let file = ($home | path join ".gitconfig")
  let action = (classify $file --root $root)

  match $action {
    "ok" => { log skipped "~/.gitconfig already includes the shared and platform files" }
    "foreign-link" => {
      log warn $"($file) is a link to (links link-target $file), not into this repo -- add the includes there by hand:\n(header)"
    }
    _ => {
      if $dry_run {
        let what = (match $action {
          "migrate" => "replace the link into this repo with a real file"
          "create" => "create it"
          _ => "put the includes at the top"
        })
        log info $"would ($what): ($file)"
        return
      }
      # The link's target is this repo's file, so removing the link loses
      # nothing: the shared settings now come from shared.conf.
      if $action == "migrate" { rm --force $file }
      let rest = (if $action == "prepend" { "\n\n" + (open --raw $file) } else { "\n" })
      (header) + $rest | save --force $file
      log ok (match $action {
        "migrate" => $"($file) is now this machine's own file, including the shared config"
        "create" => $"created ($file), including the shared config"
        _ => $"($file) now includes the shared config"
      })
    }
  }
}
