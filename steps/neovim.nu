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
  } else {
    log shell ["git" "-C" $dest "pull" "--ff-only"]
    log ok $"($dest) up to date"
  }
}

export def install [
  --home: path
  --repo: string = $REPO   # overridable so a test can point at a local clone
  --dry-run
]: nothing -> nothing {
  log step "Neovim configuration"
  clone-or-update $repo ($home | path join ".config" "nvim") --dry-run=$dry_run
  log info "neovim installs its plugins on first start"
}
