# The repository's own git hooks.
#
# Hooks are not cloned with a repository, so they have to be turned on once per
# checkout. core.hooksPath is how that is done without copying anything into
# .git/hooks: the hooks stay tracked in githooks/, so a fix to one arrives with
# a git pull rather than needing a reinstall.

use ../lib/log.nu

export def install [--root: path, --dry-run]: nothing -> nothing {
  log step "Git hooks (secret scanning)"

  let hooks = ($root | path join "githooks")
  if not ($hooks | path exists) {
    log warn $"($hooks) is missing -- skipping"
    return
  }

  # core.hooksPath is a repository setting, so there has to be a repository.
  # Deploying these files as a tarball or a copy is a legitimate thing to do;
  # it just cannot have hooks, and should say so rather than fail the install.
  if not ($root | path join ".git" | path exists) {
    log warn $"($root) is not a git checkout -- no hooks to enable"
    return
  }

  if $dry_run {
    log info $"would set core.hooksPath to githooks in ($root)"
    return
  }

  log shell ["git" "-C" $root "config" "core.hooksPath" "githooks"]

  if (which gitleaks | is-empty) {
    log warn "gitleaks is not on PATH yet; the pre-commit hook will block commits until it is"
  } else {
    log ok "gitleaks pre-commit hook active"
  }
}
