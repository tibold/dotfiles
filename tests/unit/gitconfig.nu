# ~/.gitconfig as this machine's own file, including the repo's shared and
# per-system git config.

use ../../steps/gitconfig.nu
use ../../lib/links.nu
use std/testing *
use std/assert

const REPO = (path self | path dirname | path dirname | path dirname)

# A throwaway repo root holding the old home/.gitconfig, and an empty home.
def fixture []: nothing -> record {
  let base = (mktemp --directory --tmpdir "dotfiles-gitconfig-XXXXXX")
  let root = ($base | path join "repo")
  let home = ($base | path join "home")
  mkdir ($root | path join "home")
  mkdir $home
  { base: $base, root: $root, home: $home, file: ($home | path join ".gitconfig") }
}

def cleanup [f: record]: nothing -> nothing {
  rm --recursive --force $f.base
}

@test
export def "the includes name files this repo puts in place" [] {
  assert equal $gitconfig.INCLUDES ["~/.config/git/shared.conf" "~/.config/git/platform.conf"] "shared first, so platform overrides it"
  assert ($REPO | path join "home" ".config" "git" "shared.conf" | path exists)
}

@test
export def "a missing gitconfig is created with the includes" [] {
  let f = (fixture)
  assert equal (gitconfig classify $f.file --root $f.root) "create"
  gitconfig install --root $f.root --home $f.home
  assert (gitconfig has-includes (open --raw $f.file))
  assert equal (gitconfig classify $f.file --root $f.root) "ok"
  cleanup $f
}

@test
export def "an existing gitconfig keeps its lines, below the includes" [] {
  # Below, so this machine's own settings override the shared ones.
  let f = (fixture)
  "[credential \"https://example.test\"]\n\tprovider = generic\n" | save $f.file
  assert equal (gitconfig classify $f.file --root $f.root) "prepend"

  gitconfig install --root $f.root --home $f.home
  let text = (open --raw $f.file)
  assert ($text | str starts-with (gitconfig header))
  assert str contains $text "provider = generic"
  cleanup $f
}

@test
export def "a second run changes nothing" [] {
  let f = (fixture)
  gitconfig install --root $f.root --home $f.home
  let first = (open --raw $f.file)
  gitconfig install --root $f.root --home $f.home
  assert equal (open --raw $f.file) $first
  cleanup $f
}

@test
export def "the old link into the repo is replaced by a real file" [] {
  # The migration: ~/.gitconfig used to be a link to home/.gitconfig here.
  # Writing through it would put this machine's settings back into the repo.
  let f = (fixture)
  let old = ($f.root | path join "home" ".gitconfig")
  "[user]\n\tname = old\n" | save $old
  links make-link $old $f.file
  assert equal (gitconfig classify $f.file --root $f.root) "migrate"

  gitconfig install --root $f.root --home $f.home
  assert equal (links link-target $f.file) null "still a link"
  assert (gitconfig has-includes (open --raw $f.file))
  assert equal (open --raw $old) "[user]\n\tname = old\n" "wrote through the link into the repo"
  cleanup $f
}

@test
export def "a dangling link into the repo is migrated too" [] {
  # What a pull leaves behind once home/.gitconfig is gone, if the links
  # step has not pruned it first.
  let f = (fixture)
  let old = ($f.root | path join "home" ".gitconfig")
  "x" | save $old
  links make-link $old $f.file
  rm $old
  assert equal (gitconfig classify $f.file --root $f.root) "migrate"
  cleanup $f
}

@test
export def "a link to somewhere else is left alone" [] {
  let f = (fixture)
  let elsewhere = ($f.base | path join "elsewhere.gitconfig")
  "mine" | save $elsewhere
  links make-link $elsewhere $f.file
  assert equal (gitconfig classify $f.file --root $f.root) "foreign-link"

  gitconfig install --root $f.root --home $f.home
  assert equal (open --raw $elsewhere) "mine"
  cleanup $f
}

@test
export def "a dry run writes nothing" [] {
  let f = (fixture)
  gitconfig install --root $f.root --home $f.home --dry-run
  assert not ($f.file | path exists)
  cleanup $f
}
