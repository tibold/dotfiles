# Claude Code, for the current user. Opt-in: see OPT_IN in lib/steps.nu.
#
# Runs before the neovim step, which registers the Claude plugin that lives in
# the neovim config -- on a fresh machine that is only possible if Claude Code
# arrived first. The official installers put a self-updating binary in
# ~/.local/bin, which install.nu has already put on this run's PATH.

use ../lib/log.nu

export def installer-command [family: string]: nothing -> list<string> {
  if $family == "windows" {
    # Windows PowerShell 5.1 rather than pwsh. It ships with every Windows, so
    # it is on this process's PATH from the start; pwsh arrives in this very
    # run as an MSI under Program Files, which a running process does not see
    # until its PATH is rebuilt. The installer script runs fine on either.
    ["powershell" "-NoProfile" "-Command" "$ErrorActionPreference = 'Stop'; irm https://claude.ai/install.ps1 | iex"]
  } else {
    ["sh" "-c" "set -e; script=$(curl -fsSL https://claude.ai/install.sh); printf '%s' \"$script\" | sh"]
  }
}

export def install [family: string, --dry-run]: nothing -> nothing {
  log step "Claude Code"
  if (which claude | is-not-empty) {
    let version = (do { ^claude --version } | complete | get stdout | str trim)
    log skipped $"already installed \(($version)) -- it updates itself"
    return
  }
  # A failure here warns rather than aborts. Claude Code is an opt-in extra
  # fetched from the network, and the steps after it -- neovim, hooks -- do not
  # need it: neovim only skips registering the plugin when claude is missing.
  # Losing the rest of the run to a flaky download would be the worse outcome.
  try {
    log shell (installer-command $family) --dry-run=$dry_run
    if not $dry_run { log ok "installed; run `claude` and sign in to finish" }
  } catch {|e|
    log warn $"could not install Claude Code \(($e.msg)) -- rerun with `--only claude` later"
  }
}
