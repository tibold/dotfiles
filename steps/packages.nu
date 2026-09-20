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

  # A separate transaction because casks are installed by a different
  # subcommand, not because they are optional. Only macOS has any.
  #
  # Tolerated rather than fatal, which is the opposite of how this step treats
  # the formulae. The reason is what a cask is here: the only one is a font,
  # nothing else in the install depends on it, and the ways it fails are things
  # like a hand-installed copy of a different version that --adopt cannot take
  # over. Stopping there would leave the machine with no dotfiles linked and no
  # shell configured because a glyph set could not be replaced.
  if ($plan.casks | is-not-empty) {
    log step $"Casks \(($plan.casks | str join ', '))"
    try {
      log shell (distro cask-install-command $distro.family $plan.casks) --dry-run=$dry_run
    } catch {
      log warn $"could not install ($plan.casks | str join ', ') -- carrying on without it; the status line separators need a Nerd Font in the terminal, so install it by hand if this keeps failing"
    }
  }

  if ($plan.fallback | is-not-empty) {
    log step $"Upstream releases for ($plan.fallback | str join ', ')"
    fallback install-all $plan.fallback --bin-dir $bin_dir --dry-run=$dry_run
  }

  # Already here without the package manager's help. Worth a line each: the
  # alternative is a list that silently has fewer things on it on one platform,
  # which reads like something went wrong.
  for present in $plan.provided {
    log skipped $"($present.tool): in the base system -- ($present.reason)"
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
    # Whether this needs sudo depends on where npm's prefix is, which depends on
    # where node came from -- see distro npm-global-command.
    log step "Node packages (npm, global)"
    log shell (distro npm-global-command $distro.family $plan.npm) --dry-run=$dry_run
  }
}
