# Installing everything that comes from a package manager.

use ../lib/log.nu
use ../lib/distro.nu
use ../lib/packages.nu
use ../lib/fallback.nu

# Which winget ids still need installing, given what `winget list` already
# found. Pure and separate from install-windows below so the skip/install
# split can be tested without running winget.
export def winget-plan [ids: list<string>, installed: list<string>]: nothing -> table {
  $ids | each {|id| { id: $id, action: (if $id in $installed { "skip" } else { "install" }) } }
}

# Whether a Nerd Font variant of `name` is already among these font file
# names. Matches loosely -- "NerdFont" and "Nerd Font" both appear across the
# family, and the check only needs to rule out reinstalling one that is
# already there, not identify the exact build.
export def font-present [name: string, files: list<string>]: nothing -> bool {
  $files | any {|f| ($f | path basename) =~ $"\(?i\)^($name).*nerd.?font" }
}

# fnm needs a default Node version before `fnm exec` has anything to run.
# Installing one is idempotent in principle, but not worth doing every run --
# `fnm default` already says whether one exists.
export def fnm-setup [default_output: string]: nothing -> list<list<string>> {
  if ($default_output | str trim | is-not-empty) { [] } else {
    [["fnm" "install" "--lts"] ["fnm" "default" "lts-latest"]]
  }
}

# The winget install command for one id, with any extra arguments its
# overlay names (WINGET_ARGS). Pure, so the arguments can be tested.
export def winget-command [id: string, extra: record]: nothing -> list<string> {
  (distro winget-install-command $id) ++ ($extra | get --optional $id | default [])
}

export def install [
  distro: record
  --bin-dir: path
  --group: string = "base"   # or "databases", the opt-in step's list
  --dry-run
]: nothing -> nothing {
  let plan = (packages resolve $distro --group $group)
  let title = (if $group == "base" { "System packages" } else { "Database clients" })

  log step $"($title) for ($distro.pretty) \(($plan.install | length) packages)"

  # winget has no batch install and no all-or-nothing transaction, so it gets
  # its own path entirely rather than sharing the apt/dnf/zypper/brew one
  # below, which assumes exactly one of those things.
  if $distro.family == "windows" {
    install-windows $plan --dry-run=$dry_run
    return
  }

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

# winget, one id at a time.
#
# Unlike the Linux transaction, a failure is per package: winget has no
# all-or-nothing install, and one id failing -- a network blip, a publisher's
# installer refusing -- is no reason to leave the other twenty uninstalled.
def install-windows [plan: record, --dry-run]: nothing -> nothing {
  let installed = ($plan.install | where {|id|
    let argv = (distro winget-list-command $id)
    (do { ^($argv | first) ...($argv | slice 1..) } | complete).exit_code == 0
  })
  for row in (winget-plan $plan.install $installed) {
    if $row.action == "skip" { log skipped $"($row.id) already installed"; continue }
    try {
      log shell (winget-command $row.id $plan.winget_args) --dry-run=$dry_run
    } catch {
      log warn $"($row.id) did not install -- carrying on; re-run to retry"
    }
  }

  for font in $plan.fonts {
    let dirs = [
      ($env.LOCALAPPDATA | path join "Microsoft" "Windows" "Fonts")
      ($env.WINDIR | path join "Fonts")
    ]
    let files = ($dirs | where {|d| $d | path exists } | each {|d| ls $d | get name } | flatten)
    if (font-present $font $files) { log skipped $"($font) nerd font already installed"; continue }
    try {
      log shell ["oh-my-posh" "font" "install" $font "--headless"] --dry-run=$dry_run
    } catch {
      log warn $"could not install the ($font) nerd font -- the prompt and status line separators need it; `oh-my-posh font install ($font)` by hand"
    }
  }

  for present in $plan.provided { log skipped $"($present.tool): in the base system -- ($present.reason)" }
  for skipped in $plan.omitted { log skipped $"($skipped.tool): ($skipped.reason)" }

  # Only the base list carries npm packages; the database group has no use
  # for Node at all.
  if ($plan.npm | is-empty) { return }

  if (which fnm | is-not-empty) or $dry_run {
    let current = (if (which fnm | is-empty) { "" } else { do { ^fnm default } | complete | get stdout })
    # Per step, like the winget ids above: a failed Node download is no reason
    # to abort the steps after this one. The npm packages need that Node, so
    # they are skipped rather than attempted against nothing.
    let node_ready = (try {
      for cmd in (fnm-setup $current) { log shell $cmd --dry-run=$dry_run }
      true
    } catch {
      log warn "fnm could not set up a default Node -- skipping the npm packages; re-run to retry"
      false
    })
    if $node_ready and ($plan.npm | is-not-empty) {
      log step "Node packages (npm, global, through fnm)"
      try {
        log shell (distro npm-global-command "windows" $plan.npm) --dry-run=$dry_run
      } catch {
        log warn "the global npm packages did not install -- carrying on; re-run to retry"
      }
    }
  } else {
    log warn "fnm is not on PATH yet -- open a new shell and re-run `nu install.nu --only packages` for node and its packages"
  }
}
