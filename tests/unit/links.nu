use ../../lib/links.nu
use std/testing *
use std/assert

# A throwaway repo root with a home/ tree, plus an empty destination.
def fixture []: nothing -> record {
  let base = (mktemp --directory --tmpdir "dotfiles-links-XXXXXX")
  let root = ($base | path join "repo")
  let home = ($base | path join "home")

  mkdir ($root | path join "home" ".config" "lazygit")
  "zshrc contents" | save ($root | path join "home" ".zshrc")
  "lazygit contents" | save ($root | path join "home" ".config" "lazygit" "config.yml")
  mkdir $home

  { base: $base, root: $root, home: $home }
}

def cleanup [f: record]: nothing -> nothing {
  rm --recursive --force $f.base
}

@test
export def "the plan mirrors home/ into the destination" [] {
  let f = (fixture)
  let plan = (links plan --root $f.root --home $f.home)

  assert equal ($plan | get relative) [".config/lazygit/config.yml" ".zshrc"]
  assert equal ($plan | where relative == ".zshrc" | first | get target) ($f.home | path join ".zshrc")

  cleanup $f
}

@test
export def "nested paths keep their shape" [] {
  # The whole reason for the mirror layout: no manifest says where this goes,
  # the directory structure does.
  let f = (fixture)
  let row = (links plan --root $f.root --home $f.home | where relative =~ "lazygit" | first)

  assert equal $row.target ($f.home | path join ".config" "lazygit" "config.yml")

  cleanup $f
}

@test
export def "an empty destination is all creations" [] {
  let f = (fixture)
  let plan = (links plan --root $f.root --home $f.home)

  assert equal ($plan | get action | uniq) ["create"]

  cleanup $f
}

@test
export def "applying twice is a no-op the second time" [] {
  let f = (fixture)

  links apply (links plan --root $f.root --home $f.home) --backup-root ($f.base | path join "backup")
  let replan = (links plan --root $f.root --home $f.home)

  assert equal ($replan | get action | uniq) ["ok"] "a second run should find everything already linked"

  cleanup $f
}

@test
export def "links are created, and they resolve to the repo" [] {
  let f = (fixture)

  links apply (links plan --root $f.root --home $f.home) --backup-root ($f.base | path join "backup")

  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"
  assert equal (^readlink ($f.home | path join ".zshrc") | str trim) ($f.root | path join "home" ".zshrc")

  cleanup $f
}

@test
export def "a link pointing somewhere else is repointed" [] {
  let f = (fixture)
  "somewhere else" | save ($f.base | path join "stray")
  ^ln -sfn ($f.base | path join "stray") ($f.home | path join ".zshrc")

  let plan = (links plan --root $f.root --home $f.home)
  assert equal ($plan | where relative == ".zshrc" | first | get action) "relink"

  links apply $plan --backup-root ($f.base | path join "backup")
  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"

  cleanup $f
}

@test
export def "a real file in the way is backed up, never destroyed" [] {
  # A fresh Ubuntu ships its own ~/.bashrc and ~/.profile. Losing local edits
  # to them on a first install would be a nasty surprise.
  let f = (fixture)
  "the distro's own version" | save ($f.home | path join ".zshrc")
  let backups = ($f.base | path join "backup")

  let plan = (links plan --root $f.root --home $f.home)
  assert equal ($plan | where relative == ".zshrc" | first | get action) "backup"

  links apply $plan --backup-root $backups

  let saved = (glob ($backups | path join "**" ".zshrc") --no-dir)
  assert equal ($saved | length) 1 "the displaced file should be kept exactly once"
  assert equal (open --raw ($saved | first)) "the distro's own version"
  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"

  cleanup $f
}

@test
export def "copy mode leaves a real file, not a link" [] {
  let f = (fixture)

  links apply (links plan --root $f.root --home $f.home --copy) --copy --backup-root ($f.base | path join "backup")

  assert equal (^readlink ($f.home | path join ".zshrc") | complete | get exit_code) 1 "copy mode must not leave a symlink"
  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"

  cleanup $f
}

@test
export def "copy mode never writes back through an existing link" [] {
  # The trap this guards: if the destination is already a symlink into the
  # repo, copying onto it follows the link and overwrites the repo's own copy
  # with itself -- and on a second, edited run, silently reverts your edit.
  let f = (fixture)

  # First install as links, the normal case.
  links apply (links plan --root $f.root --home $f.home) --backup-root ($f.base | path join "backup")

  # Then switch to copies, which must break the link rather than write through.
  let plan = (links plan --root $f.root --home $f.home --copy)
  assert equal ($plan | where relative == ".zshrc" | first | get action) "unlink-then-copy"

  links apply $plan --copy --backup-root ($f.base | path join "backup")

  assert equal (^readlink ($f.home | path join ".zshrc") | complete | get exit_code) 1
  assert equal (open --raw ($f.root | path join "home" ".zshrc")) "zshrc contents" "the repo copy must be untouched"

  cleanup $f
}

@test
export def "a dry run changes nothing" [] {
  let f = (fixture)

  links apply (links plan --root $f.root --home $f.home) --dry-run --backup-root ($f.base | path join "backup")

  assert equal (ls $f.home | length) 0 "dry run must not create anything"

  cleanup $f
}

@test
export def "planning against a directory with no home/ is an error" [] {
  let f = (fixture)
  assert error {|| links plan --root ($f.base | path join "nope") --home $f.home }
  cleanup $f
}

@test
export def "a link left behind by a removed config is pruned" [] {
  let f = (fixture)
  links apply (links plan --root $f.root --home $f.home) --backup-root ($f.base | path join "backup")

  # A config that used to be shipped and no longer is.
  rm ($f.root | path join "home" ".zshrc")

  let dead = (links stale --root $f.root --home $f.home)
  assert equal ($dead | get target) [($f.home | path join ".zshrc")]

  links prune $dead
  assert not (($f.home | path join ".zshrc") | path exists)

  cleanup $f
}

@test
export def "a link to somewhere outside the repo is left alone" [] {
  # Not ours to remove, however broken it looks.
  let f = (fixture)
  ^ln -sfn "/nonexistent/elsewhere" ($f.home | path join ".unrelated")

  assert equal (links stale --root $f.root --home $f.home) []

  cleanup $f
}

@test
export def "a link that still resolves is left alone" [] {
  let f = (fixture)
  links apply (links plan --root $f.root --home $f.home) --backup-root ($f.base | path join "backup")

  assert equal (links stale --root $f.root --home $f.home) []

  cleanup $f
}

@test
export def "a real file is never pruned" [] {
  let f = (fixture)
  "not a link" | save ($f.home | path join ".keepme")

  assert equal (links stale --root $f.root --home $f.home) []
  assert (($f.home | path join ".keepme") | path exists)

  cleanup $f
}

@test
export def "a link the plan is about to repoint is not stale" [] {
  # Under --dry-run nothing has been repointed yet, so a link to the config's
  # old location still dangles. Reporting it as abandoned would tell the user
  # we are about to both relink and delete the same path.
  let f = (fixture)
  ^ln -sfn ($f.root | path join "home" "old-location" ".zshrc") ($f.home | path join ".zshrc")

  let plan = (links plan --root $f.root --home $f.home)
  let dead = (links stale --root $f.root --home $f.home --managed ($plan | get target))

  assert equal $dead []

  cleanup $f
}

@test
export def "copy mode is idempotent" [] {
  let f = (fixture)
  let backups = ($f.base | path join "backup")

  links apply (links plan --root $f.root --home $f.home --copy) --copy --backup-root $backups
  let replan = (links plan --root $f.root --home $f.home --copy)

  assert equal ($replan | get action | uniq) ["ok"] "a second copy run should find its own output in place"

  cleanup $f
}

@test
export def "copy mode backs up a file it is about to overwrite" [] {
  # Link mode never destroys a file it finds in the way, and copy mode must
  # make the same promise -- including for local edits to a previous copy.
  let f = (fixture)
  let backups = ($f.base | path join "backup")
  "hand-edited" | save --force ($f.home | path join ".zshrc")

  let plan = (links plan --root $f.root --home $f.home --copy)
  assert equal ($plan | where relative == ".zshrc" | first | get action) "backup"

  links apply $plan --copy --backup-root $backups

  let saved = (glob ($backups | path join "**" ".zshrc") --no-dir)
  assert equal (open --raw ($saved | first)) "hand-edited"
  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"

  cleanup $f
}
