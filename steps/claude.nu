# Claude Code, for the current user. Opt-in: see OPT_IN in lib/steps.nu.
#
# Runs before the neovim step, which registers the Claude plugin that lives in
# the neovim config -- on a fresh machine that is only possible if Claude Code
# arrived first. The official installers put a self-updating binary in
# ~/.local/bin, which install.nu has already put on this run's PATH.
#
# It also points Claude Code's status line at the script in
# home/.claude/statusline-command.sh, which the links step (appdirs, on
# Windows) puts in ~/.claude. That one key is merged into settings.json rather
# than the file being linked: Claude Code rewrites settings.json whenever a
# setting changes in /config, and the rest of it -- plugins, marketplaces with
# paths on this machine, the model -- is this machine's own business.

use ../lib/log.nu

# The command runs under bash on every platform, Windows included, where
# Claude Code needs Git Bash anyway. The script itself needs jq, which the
# packages step installs.
export const STATUSLINE = {
  type: "command"
  command: "bash ~/.claude/statusline-command.sh"
}

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

export def install [family: string, --home: path, --dry-run]: nothing -> nothing {
  log step "Claude Code"
  if (which claude | is-not-empty) {
    let version = (do { ^claude --version } | complete | get stdout | str trim)
    log skipped $"already installed \(($version)) -- it updates itself"
  } else {
    install-binary $family --dry-run=$dry_run
  }
  configure-statusline --home $home --dry-run=$dry_run
}

# settings.json with this repo's status line in it, or null when it already
# has exactly that. Every other key is left as it was.
export def with-statusline [settings: record]: nothing -> any {
  if ($settings | get --optional statusLine) == $STATUSLINE { return null }
  $settings | upsert statusLine $STATUSLINE
}

export def configure-statusline [--home: path, --dry-run]: nothing -> nothing {
  let file = ($home | path join ".claude" "settings.json")
  let current = (if ($file | path exists) { open --raw $file | from json } else { {} })
  let wanted = (with-statusline $current)
  if $wanted == null {
    log skipped "status line already set"
    return
  }
  if $dry_run {
    log info $"would set statusLine in ($file)"
    return
  }
  mkdir ($file | path dirname)
  $wanted | to json --indent 2 | save --force $file
  log ok $"status line set in ($file)"
}

def install-binary [family: string, --dry-run]: nothing -> nothing {
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
