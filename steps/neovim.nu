# The neovim configuration, which lives in its own repository.

use ../lib/log.nu

# Public, so a plain https clone works everywhere with no credentials. This
# used to choose between https and ssh depending on whether gh or an ssh agent
# could authenticate; making the repository public removed the reason for that
# entirely.
const REPO = "https://github.com/tibold/astrovim-init.git"

# Clone unless it is already there, and refuse to touch a directory that holds
# something else. Silently pulling over an unrelated checkout, or over someone's
# hand-written config, would be worse than stopping.
export def clone-or-update [url: string, dest: path, --dry-run]: nothing -> nothing {
  if not ($dest | path exists) {
    if $dry_run {
      log info $"would clone ($url) into ($dest)"
    } else {
      log shell ["git" "clone" $url $dest]
      log ok $dest
    }
    return
  }

  if not ($dest | path join ".git" | path exists) {
    log warn $"($dest) exists but is not a git repository -- leaving it alone"
    return
  }

  let origin = (do { ^git -C $dest remote get-url origin } | complete)
  let existing = ($origin.stdout | str trim)

  if $origin.exit_code != 0 or $existing != $url {
    log warn $"($dest) points at ($existing), not ($url) -- leaving it alone"
    return
  }

  if $dry_run {
    log info $"would pull ($dest)"
    return
  }

  # A pull that cannot fast-forward is reported and left alone -- not forced,
  # and not fatal.
  #
  # --ff-only already refuses to invent a merge commit; what this adds is that
  # its refusal no longer takes the whole install with it. There are two ways
  # to arrive here, a local commit in the config or an upstream that was
  # force-pushed, and both are somebody's work. Resolving either means looking
  # at the checkout, which is a thing to do deliberately rather than something
  # an installer should decide halfway through.
  #
  # It matters more than it looks because of where this step sits: the git
  # hooks are installed after it, so an unmergeable neovim config used to mean
  # a repository left with no secret scanning and nothing on screen saying why.
  let result = (do { ^git -C $dest pull --ff-only } | complete)

  if $result.exit_code == 0 {
    log ok $"($dest) up to date"
    return
  }

  log warn $"($dest) cannot be fast-forwarded -- leaving it exactly as it is"
  # git's hints are addressed to someone standing in that repository, and this
  # is not that. The reason is worth repeating; the suggestions are not.
  for line in ($result.stderr
    | lines
    | where {|l| ($l | str trim | is-not-empty) and (not ($l | str starts-with "hint:")) }) {
    log info $line
  }
  log info "sort it out there, then: nu install.nu --only neovim"
}

export def install [
  --home: path
  --repo: string = $REPO   # overridable so a test can point at a local clone
  --dry-run
]: nothing -> nothing {
  log step "Neovim configuration"
  clone-or-update $repo ($home | path join ".config" "nvim") --dry-run=$dry_run
  log info "neovim installs its plugins on first start"
  # Worth saying, because the first run looks broken and is not.
  #
  # AstroNvim 6's nvim-treesitter builds each parser from source with the
  # tree-sitter CLI, and Mason fetches that CLI on the same first start. The
  # parsers lose the race: they download, reach the compile step before the CLI
  # has arrived, and report
  #
  #   Error during "tree-sitter build": ENOENT: no such file or directory
  #   (cmd): 'tree-sitter'
  #
  # which reads like a missing dependency and is really a missing few seconds.
  # nvim-treesitter logs to `:messages` and no further, so it is not in any file
  # afterwards either. The second start has the CLI and builds them.
  log info "treesitter parsers may fail on that first start, before Mason has fetched the tree-sitter CLI they build with -- reopen nvim and they compile"
}
