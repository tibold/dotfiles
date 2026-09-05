# Installing everything that comes from a package manager.

use ../lib/log.nu
use ../lib/distro.nu
use ../lib/packages.nu
use ../lib/fallback.nu

export def install [
  distro: record
  --bin-dir: path
  --dry-run
]: nothing -> nothing {
  let plan = (packages resolve $distro)

  log step $"System packages for ($distro.pretty) \(($plan.install | length) packages)"

  let refresh = (distro refresh-command $distro.family)
  if ($refresh | is-not-empty) {
    log shell $refresh --dry-run=$dry_run
  }

  log shell (distro install-command $distro.family $plan.install) --dry-run=$dry_run

  if ($plan.fallback | is-not-empty) {
    log step $"Upstream releases for ($plan.fallback | str join ', ')"
    fallback install-all $plan.fallback --bin-dir $bin_dir --dry-run=$dry_run
  }

  # Said out loud rather than passed over in silence: an environment that is
  # missing a tool everywhere else should say so once, with the reason.
  for skipped in $plan.omitted {
    log skipped $"($skipped.tool): ($skipped.reason)"
  }

  if ($plan.pipx | is-not-empty) {
    # Deliberately not under sudo. pipx installs into ~/.local, so running it
    # as root puts the venvs in root's home where this user cannot reach them
    # -- which is what the previous `sudo pipx install` actually did.
    log step "Python applications (pipx)"
    log shell (["pipx" "install"] ++ $plan.pipx) --dry-run=$dry_run
    log shell ["pipx" "ensurepath"] --dry-run=$dry_run
  }

  if ($plan.npm | is-not-empty) {
    # -g matters: without it npm treats the current directory as a project and
    # writes a node_modules tree into whatever we happen to be standing in.
    log step "Node packages (npm, global)"
    log shell (["sudo" "npm" "install" "--global"] ++ $plan.npm) --dry-run=$dry_run
  }
}
