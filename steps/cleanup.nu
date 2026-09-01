# Removing what this repo used to install and no longer wants.

use ../lib/log.nu
use ../lib/packages.nu
use ../lib/cleanup.nu

export def install [
  distro: record
  --dry-run
]: nothing -> nothing {
  let resolved = (packages resolve $distro)
  if ($resolved.removed | is-empty) { return }

  log step "Removing superseded packages"

  # The install list is passed as protected so that a name appearing on both
  # lists can never be uninstalled. tests/unit/cleanup.nu already fails if that
  # overlap exists, but the belt stays on: a bad edit should be inert here, not
  # merely caught later.
  let facts = (cleanup gather $distro.family $resolved.removed)
  let plan = (cleanup plan $resolved.removed
    --installed $facts.installed
    --requires $facts.requires
    --protected $resolved.install)

  for name in $plan.absent {
    log skipped $"($name) is not installed"
  }

  for kept in $plan.kept {
    log warn $"keeping ($kept.package): ($kept.reason)"
  }

  if ($plan.remove | is-empty) {
    log info "nothing to remove"
    return
  }

  log shell (cleanup remove-command $distro.family $plan.remove) --dry-run=$dry_run
}
