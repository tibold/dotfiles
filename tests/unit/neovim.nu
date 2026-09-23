use ../../steps/neovim.nu
use std/testing *
use std/assert

@test
export def "neovim reads its config from AppData on Windows" [] {
  assert equal (neovim destination "/h" "windows") ("/h" | path join "AppData" "Local" "nvim")
  assert equal (neovim destination "/h" "fedora") ("/h" | path join ".config" "nvim")
}

@test
export def "the marketplace is added once and never repointed" [] {
  let dest = ("/h" | path join "AppData" "Local" "nvim")
  assert equal (neovim marketplace-action [] $dest) "add"
  assert equal (neovim marketplace-action [{ name: "tibold-nvim", source: "directory", path: $dest }] $dest) "ok"
  assert equal (neovim marketplace-action [{ name: "tibold-nvim", source: "directory", path: "/other/nvim" }] $dest) "elsewhere"
  assert equal (neovim marketplace-action [{ name: "tibold-nvim", source: "github", repo: "tibold/astrovim-init" }] $dest) "elsewhere"
  # An empty path (which a directory marketplace should never have, but a
  # defensive check all the same) must not accidentally compare equal to dest.
  assert equal (neovim marketplace-action [{ name: "tibold-nvim", source: "directory", path: "" }] $dest) "elsewhere"
}

@test
export def "on Windows the marketplace still matches when spelled with different case or slashes" [] {
  # claude reports the path back however the platform's tooling spelled it --
  # drive letter case, backslash vs forward slash -- and that is not a
  # different marketplace.
  if $nu.os-info.name != "windows" { return }
  let dest = (neovim destination "/h" "windows")
  let differently_spelled = ($dest | str replace --all '\' '/' | str uppercase)
  assert equal (neovim marketplace-action [{ name: "tibold-nvim", source: "directory", path: $differently_spelled }] $dest) "ok"
}

@test
export def "a sibling directory is not mistaken for the marketplace" [] {
  let dest = (neovim destination "/h" "windows")
  assert equal (neovim marketplace-action [{ name: "tibold-nvim", source: "directory", path: $"($dest)-old" }] $dest) "elsewhere"
}

@test
export def "the plugin is installed once and updated after a pull" [] {
  assert equal (neovim plugin-action [] false) "install"
  assert equal (neovim plugin-action [{ id: "nvim@tibold-nvim" }] false) "ok"
  assert equal (neovim plugin-action [{ id: "nvim@tibold-nvim" }] true) "update"
  assert equal (neovim plugin-action [{ id: "other@x" }] true) "install"
}

# A real upstream, a second clone that plays "someone pushing changes", and the
# checkout the step keeps up to date -- all in a temp directory.
# null when git is not installed: the minimal nushell image the Linux unit run
# uses has none, and every machine this repo sets up installs it first.
def git-fixture []: nothing -> any {
  if (which git | is-empty) { return null }
  let base = (mktemp --directory --tmpdir "dotfiles-nvim-XXXXXX")
  let remote = ($base | path join "remote.git")
  let seed = ($base | path join "seed")
  let dest = ($base | path join "nvim")
  let g = {|dir, args| ^git -C $dir -c user.name=test -c user.email=test@example.com -c core.hooksPath= ...$args | complete }

  ^git init --quiet --bare --initial-branch=main $remote
  ^git clone --quiet $remote $seed
  "{ \"lazy.nvim\": \"v1\" }\n" | save ($seed | path join "lazy-lock.json")
  "-- init v1\n" | save ($seed | path join "init.lua")
  do $g $seed [add .] | ignore
  do $g $seed [commit --quiet -m seed] | ignore
  do $g $seed [push --quiet origin HEAD:main] | ignore
  ^git clone --quiet $remote $dest

  { base: $base, remote: $remote, seed: $seed, dest: $dest, backup: ($base | path join "backup"), g: $g }
}

# Commit a new version of one file upstream.
def push-upstream [f: record, file: string, content: string] {
  $content | save --force ($f.seed | path join $file)
  do $f.g $f.seed [commit --quiet -am $"update ($file)"] | ignore
  do $f.g $f.seed [push --quiet origin HEAD:main] | ignore
}

def update [f: record]: nothing -> record {
  neovim clone-or-update $f.remote $f.dest --backup-root $f.backup
}

@test
export def "a local lock file yields to an incoming one and is kept in the backup" [] {
  # lazy.nvim rewrites lazy-lock.json on every plugin update, so a checkout
  # almost always has it modified -- which used to make every pull that also
  # touched it refuse to run.
  let f = (git-fixture)
  if $f == null { return }
  push-upstream $f "lazy-lock.json" "{ \"lazy.nvim\": \"v2\" }\n"
  "{ \"lazy.nvim\": \"local\" }\n" | save --force ($f.dest | path join "lazy-lock.json")

  let result = (update $f)

  assert $result.changed "the pull did not happen"
  assert str contains (open --raw ($f.dest | path join "lazy-lock.json")) "v2"
  let saved = (glob ($f.backup | path join "**" "lazy-lock.json" | str replace --all '\' '/'))
  assert equal ($saved | length) 1 "the local lock file was not kept"
  assert str contains (open --raw ($saved | first)) "local"
  rm --recursive --force $f.base
}

@test
export def "a local lock file the pull does not touch is left alone" [] {
  let f = (git-fixture)
  if $f == null { return }
  push-upstream $f "init.lua" "-- init v2\n"
  "{ \"lazy.nvim\": \"local\" }\n" | save --force ($f.dest | path join "lazy-lock.json")

  let result = (update $f)

  assert $result.changed
  assert str contains (open --raw ($f.dest | path join "lazy-lock.json")) "local"
  assert not ($f.backup | path exists) "nothing needed backing up"
  rm --recursive --force $f.base
}

@test
export def "local edits the pull does not touch survive it" [] {
  let f = (git-fixture)
  if $f == null { return }
  push-upstream $f "lazy-lock.json" "{ \"lazy.nvim\": \"v2\" }\n"
  "-- my own edit\n" | save --force ($f.dest | path join "init.lua")

  let result = (update $f)

  assert $result.changed
  assert str contains (open --raw ($f.dest | path join "init.lua")) "my own edit"
  assert str contains (open --raw ($f.dest | path join "lazy-lock.json")) "v2"
  rm --recursive --force $f.base
}

@test
export def "a pull that would overwrite a hand edit is refused" [] {
  let f = (git-fixture)
  if $f == null { return }
  push-upstream $f "init.lua" "-- init v2\n"
  "-- my own edit\n" | save --force ($f.dest | path join "init.lua")
  let before = (^git -C $f.dest rev-parse HEAD | str trim)

  let result = (update $f)

  assert not $result.changed
  assert equal (^git -C $f.dest rev-parse HEAD | str trim) $before "the checkout moved"
  assert str contains (open --raw ($f.dest | path join "init.lua")) "my own edit"
  rm --recursive --force $f.base
}
