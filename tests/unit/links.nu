use ../../lib/links.nu
use ../../lib/paths.nu
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
  assert equal (links link-target ($f.home | path join ".zshrc")) ($f.root | path join "home" ".zshrc")

  cleanup $f
}

@test
export def "a link pointing somewhere else is repointed" [] {
  let f = (fixture)
  "somewhere else" | save ($f.base | path join "stray")
  links make-link ($f.base | path join "stray") ($f.home | path join ".zshrc")

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

  let saved = (glob ($backups | path join "**" ".zshrc" | paths for-glob) --no-dir)
  assert equal ($saved | length) 1 "the displaced file should be kept exactly once"
  assert equal (open --raw ($saved | first)) "the distro's own version"
  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"

  cleanup $f
}

@test
export def "copy mode leaves a real file, not a link" [] {
  let f = (fixture)

  links apply (links plan --root $f.root --home $f.home --copy) --copy --backup-root ($f.base | path join "backup")

  assert equal (links link-target ($f.home | path join ".zshrc")) null "copy mode must not leave a symlink"
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

  assert equal (links link-target ($f.home | path join ".zshrc")) null
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
  links make-link ("/nonexistent" | path join "elsewhere") ($f.home | path join ".unrelated")

  assert equal (links stale --root $f.root --home $f.home) []

  cleanup $f
}

@test
export def "a link into a sibling checkout with a longer name is left alone" [] {
  # Guards the `stale` call site against a revert to a plain `str
  # starts-with`: repo-old is not inside repo, even though the string "repo"
  # is a prefix of "repo-old" -- and this link, dangling or not, is not ours
  # to delete.
  let f = (fixture)
  let sibling_root = ($f.base | path join $"($f.root | path basename)-old")
  links make-link ($sibling_root | path join "home" ".x") ($f.home | path join ".sibling")

  assert equal (links stale --root $f.root --home $f.home) []

  cleanup $f
}

# A relative symlink, made from inside `dir` the way a user would type it.
# Windows' mklink stores a relative target as given, so both platforms get a
# genuinely relative link rather than one expanded on the way in.
def relative-link [dir: path, name: string, target: string]: nothing -> nothing {
  cd $dir
  if $nu.os-info.name == "windows" {
    let r = (do { ^cmd /c mklink $name $target } | complete)
    if $r.exit_code != 0 { error make { msg: $"mklink failed: ($r.stderr | str trim)" } }
  } else {
    ^ln -s $target $name
  }
}

@test
export def "a working relative link made by the user is left alone" [] {
  # Resolved against the current directory -- the repo, when install.nu runs
  # -- `mylink -> target-file` looked like a dead link into this repo and was
  # pruned. It resolves against its own directory, where it works.
  let f = (fixture)
  let config = ($f.home | path join ".config")
  mkdir $config
  "mine" | save ($config | path join "target-file")
  relative-link $config "mylink" "target-file"

  # From inside the repo, as install.nu runs; the closure keeps the `cd` from
  # outliving the call, so cleanup can delete the directory afterwards.
  assert equal (do { cd $f.root; links stale --root $f.root --home $f.home }) []
  assert equal (open --raw ($config | path join "mylink")) "mine"

  cleanup $f
}

@test
export def "a dead relative link into the repo is still pruned" [] {
  # The other half of resolving relative targets properly: one that climbs
  # back into this repo from the link's own directory is ours, and gone.
  let f = (fixture)
  let config = ($f.home | path join ".config")
  mkdir $config
  let target = (["..", "..", ($f.root | path basename), "home", ".config", "gone"] | path join)
  relative-link $config "oldlink" $target

  assert equal (links stale --root $f.root --home $f.home | get target) [($config | path join "oldlink")]

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
  links make-link ($f.root | path join "home" "old-location" ".zshrc") ($f.home | path join ".zshrc")

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

  let saved = (glob ($backups | path join "**" ".zshrc" | paths for-glob) --no-dir)
  assert equal (open --raw ($saved | first)) "hand-edited"
  assert equal (open --raw ($f.home | path join ".zshrc")) "zshrc contents"

  cleanup $f
}

@test
export def "a platform directory is mirrored the same way home is" [] {
  # The generic half of the per-system mechanism: platform/<name>/ has no
  # rules of its own, it is the same mirror as home/ pointed at a different
  # directory. Nothing about git, or about any particular setting, lives in
  # the linking code.
  let base = (mktemp --directory --tmpdir "dotfiles-links-XXXXXX")
  let root = ($base | path join "repo")
  let home = ($base | path join "home")

  mkdir ($root | path join "home")
  mkdir ($root | path join "platform" "macos" ".config" "git")
  "shared" | save ($root | path join "home" ".gitconfig")
  "mac only" | save ($root | path join "platform" "macos" ".config" "git" "platform.conf")
  mkdir $home

  let shared = (links plan --root $root --home $home)
  assert equal ($shared | get relative) [".gitconfig"] "the home plan should not see the platform tree"

  let mac = (links plan --root $root --home $home --from ("platform/macos"))
  assert equal ($mac | get relative) [".config/git/platform.conf"]
  assert equal ($mac | first | get target) ($home | path join ".config" "git" "platform.conf")

  rm --recursive --force $base
}

@test
export def "a platform directory that does not exist is an error worth seeing" [] {
  # Not silently empty. A misspelled directory would otherwise link nothing
  # and report nothing, which is the failure this mechanism is most prone to.
  let base = (mktemp --directory --tmpdir "dotfiles-links-XXXXXX")
  mkdir ($base | path join "repo" "home")

  assert error {|| links plan --root ($base | path join "repo") --home $base --from "platform/nope" }

  rm --recursive --force $base
}

@test
export def "a sibling directory with a longer name is not inside the repo" [] {
  assert (links is-inside "/home/u/dotfiles/home/.zshrc" "/home/u/dotfiles")
  assert not (links is-inside "/home/u/dotfiles-old/home/.zshrc" "/home/u/dotfiles") "a prefix match is not containment"
  assert (links is-inside "/home/u/dotfiles" "/home/u/dotfiles") "the root itself counts"
}

@test
export def "on Windows the inside check ignores case and separators" [] {
  if $nu.os-info.name != "windows" { return }
  assert (links is-inside 'C:\Users\X\dotfiles\home\a' 'c:/users/x/dotfiles')
  assert not (links is-inside 'C:\Users\X\dotfiles2\a' 'C:\Users\X\dotfiles')
}

@test
export def "a dangling link still reports its target" [] {
  let f = (fixture)
  let target = ($f.home | path join ".gone")
  links make-link ($f.root | path join "home" "nothing-here") $target
  assert equal (links link-target $target) ($f.root | path join "home" "nothing-here")
  cleanup $f
}

@test
export def "a real file has no link target" [] {
  let f = (fixture)
  assert equal (links link-target ($f.root | path join "home" ".zshrc")) null
  assert equal (links link-target ($f.home | path join "does-not-exist")) null
  cleanup $f
}
