#!/usr/bin/env nu
#
# Install Claude Code for the current user.
#
#   nu tools/install-claude.nu
#
# Kept out of install.nu on purpose: this is a personal tool rather than part
# of the machine's shell environment, it authenticates interactively, and not
# every box this repo lands on should have it.

use ../lib/log.nu

const INSTALLER = "https://claude.ai/install.sh"

def main [--dry-run] {
  log step "Claude Code"

  if (which claude | is-not-empty) {
    let version = (do { ^claude --version } | complete | get stdout | str trim)
    log skipped $"already installed \(($version)) -- it updates itself"
    return
  }

  if $dry_run {
    log info $"would run ($INSTALLER)"
    return
  }

  # The official installer drops a self-updating binary into ~/.local/bin,
  # which is already on PATH via home/.profile.
  http get $INSTALLER | ^sh
  log ok "installed; run `claude` and sign in to finish"
}
