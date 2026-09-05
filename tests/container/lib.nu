# Shared plumbing for the container scripts.
#
# run.nu checks an install; try.nu hands you a shell in one. They differ only
# at the end, so everything up to "the environment is installed" lives here.

use ../../lib/log.nu

export const DISTROS = ["tumbleweed" "leap" "fedora" "ubuntu"]

export def containerfile [distro: string, here: path]: nothing -> path {
  let path = ($here | path join $"Containerfile.($distro)")
  if not ($path | path exists) {
    error make { msg: $"no Containerfile for '($distro)' -- pick from ($DISTROS | str join ', ')" }
  }
  $path
}

# A copy of the working tree with the heavy, irrelevant directories pruned.
#
# The working tree rather than a git archive, because the point is to test the
# changes in front of you, including the uncommitted ones. .git is kept: a real
# install is a clone, and the git hooks step has nothing to configure without
# it.
#
# Each call gets its own directory, and returns it. A fixed path meant run.nu
# and try.nu shared one: starting a try-drive while the test suite was running
# ended with the suite deleting the directory that the container was still
# mounting, and podman failing with a bare "statfs: no such file or directory".
export def stage [repo: path]: nothing -> path {
  let dest = (mktemp --directory --tmpdir "dotfiles-staging-XXXXXX")

  let excludes = ["./node_modules"]
    | each {|e| ["--exclude" $e] }
    | flatten

  let args = (["--create" "--file" "-" "--directory" $repo] ++ $excludes ++ ["."])
  ^tar ...$args | ^tar --extract --file - --directory $dest

  $dest
}

export def build [distro: string, here: path]: nothing -> record {
  let tag = $"dotfiles-test:($distro)"

  log step $"Building ($tag)"
  # Context is this directory, which holds only Containerfiles -- the repo
  # itself arrives as a mount at run time, so editing the code does not
  # invalidate the image cache.
  #
  # `tee` before `complete`, here and for the install in try.nu. `complete`
  # alone hands the output over only once the command has finished, which is
  # fine for the suite in run.nu -- its report is the summary -- but left
  # try.nu, which someone sits and watches, blank for the minutes an install
  # takes. `tee` prints a copy as it arrives; `complete` still gets the exit
  # code and the text.
  let result = (^podman build --tag $tag --file (containerfile $distro $here) $here
    o+e>| tee { print --raw } | complete)

  { tag: $tag, ok: ($result.exit_code == 0), output: $result.stdout }
}

# The neovim config lives in its own repository. If there is a checkout on this
# machine, mount it and clone from that instead of from GitHub: the test then
# exercises the config as it is here, uncommitted edits included, and does not
# need the network for it. Without one, the step clones from GitHub as it would
# on a real machine.
export def nvim-source []: nothing -> string {
  let local = ($nu.home-dir | path join ".config" "nvim")
  if ($local | path join ".git" | path exists) { $local } else { "" }
}

export def mounts [staging: path, nvim: string]: nothing -> list<string> {
  let base = ["--volume" $"($staging):/src:ro,z"]
  if ($nvim | is-empty) { $base } else { $base ++ ["--volume" $"($nvim):/nvim-src:ro,z"] }
}

# Runs inside the container: take the mounted copy, install from it, and leave
# the result in place.
#
# The repo is copied out of the read-only mount rather than used in place, so
# the container works on its own checkout -- an install that wrote back into
# the source tree is a bug worth seeing, not one to hide behind a writable
# mount.
export def install-script [nvim: string, extra: string = ""]: nothing -> string {
  # The neovim checkout is copied in rather than cloned straight from the
  # mount, for the same reason the repo is: under rootless podman the host user
  # maps to a different uid inside the container, so git sees the mounted
  # .git as belonging to a stranger and refuses to touch it ("dubious
  # ownership"). A copy belongs to the container user and just works.
  let nvim_setup = if ($nvim | is-empty) {
    ""
  } else {
    "cp -a /nvim-src \"$HOME/nvim-src\""
  }

  let nvim_flag = if ($nvim | is-empty) { "" } else { "--nvim-repo \"$HOME/nvim-src\"" }

  $"
set -eu
cp -a /src \"$HOME/dotfiles\"
($nvim_setup)
cd \"$HOME/dotfiles\"
export PATH=\"$HOME/.local/bin:$PATH\"
./bootstrap.sh ($nvim_flag)
($extra)
"
}

# A fingerprint of the working tree, used to tell a stale snapshot from a
# current one.
#
# This is a real git tree hash, not a hand-rolled digest: git already computes
# exactly this identity, does it quickly, and applies .gitignore on the way --
# so node_modules and anything else ignored is excluded without a second list
# to keep in step with .gitignore.
#
# It covers the WORKING tree, not HEAD, which is the point: the snapshot has to
# be thrown away when a file is edited, long before anything is committed.
def git-tree [repo: path]: nothing -> string {
  # A scratch index, so this never touches the real one. Without
  # GIT_INDEX_FILE, `git add --all` here would stage the caller's entire
  # working tree as a side effect of asking a question.
  let index = (mktemp --tmpdir "dotfiles-index-XXXXXX")
  rm --force $index   # git wants to create it itself

  let result = (with-env { GIT_INDEX_FILE: $index } {
    let added = (do { ^git -C $repo add --all } | complete)
    if $added.exit_code != 0 {
      ""
    } else {
      let tree = (do { ^git -C $repo write-tree } | complete)
      if $tree.exit_code == 0 { $tree.stdout | str trim } else { "" }
    }
  })

  rm --force $index
  $result
}

# Content hashes, for a copy of this repo that is not a git checkout -- a
# tarball deploy, say. Slower and it has to be told what to ignore, which is
# why it is the fallback rather than the rule.
def content-hash [repo: path]: nothing -> string {
  glob ($repo | path join "**" "*") --no-dir
  | where {|f| not ($f =~ '/\.git/|/node_modules/') }
  | sort
  | each {|f| $"($f | path relative-to $repo):(open --raw $f | hash sha256)" }
  | str join "\n"
  | hash sha256
}

export def revision [repo: path]: nothing -> string {
  if ($repo | path join ".git" | path exists) {
    let tree = (git-tree $repo)
    if ($tree | is-not-empty) { return $tree }
  }
  content-hash $repo
}
