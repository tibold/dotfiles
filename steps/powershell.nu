# pwsh's profile, on Windows.
#
# pwsh reads $PROFILE from a fixed place under Documents, and on a machine
# where OneDrive has taken Documents over that place is inside a synced folder
# whose path contains the organisation's name. A symlink there is both
# machine-specific and something OneDrive handles badly, so this step writes a
# one-line stub instead, and the stub loads the linked profile.

use ../lib/log.nu

# Built from explicit lines rather than written as one multi-line literal, so
# its line endings are LF whatever this file was checked out with. A literal
# picks up CRLF from a CRLF checkout, and then no longer matches itself once
# the comparison below normalises the file it reads back.
export const STUB = ([
  "# Managed by dotfiles (nu install.nu --only powershell). Edit ~/.config/powershell/profile.ps1 instead."
  ". (Join-Path $HOME '.config/powershell/profile.ps1')"
  ""
] | str join "\n")

def normalise [text: string]: nothing -> string {
  $text | str replace --all "\r\n" "\n" | str trim --right
}

export def stub-action [existing: any]: nothing -> string {
  if $existing == null { return "create" }
  if (normalise $existing) == (normalise $STUB) { "ok" } else { "backup" }
}

export def install [--home: path, --dry-run]: nothing -> nothing {
  log step "PowerShell profile"

  # $PROFILE is wherever pwsh says it is for the real user, not somewhere
  # under --home. An install into another directory is a rehearsal, and
  # writing this user's actual profile from it would not be.
  if $home != $nu.home-dir {
    log skipped $"installing into ($home), and pwsh's profile belongs to ($nu.home-dir) -- left alone"
    return
  }

  if (which pwsh | is-empty) {
    log warn "pwsh is not on PATH yet -- open a new shell and re-run `nu install.nu --only powershell`"
    return
  }

  # Asked of pwsh itself rather than assembled from $HOME: Documents may be
  # redirected, and pwsh is the one that knows where.
  let profile = (^pwsh -NoProfile -NoLogo -Command '$PROFILE.CurrentUserCurrentHost' | str trim)
  let existing = (if ($profile | path exists) { open --raw $profile } else { null })

  match (stub-action $existing) {
    "ok" => { log skipped $"($profile) already loads the linked profile" }
    "create" => {
      if $dry_run { log info $"would write the stub to ($profile)"; return }
      mkdir ($profile | path dirname)
      $STUB | save --force $profile
      log ok $profile
    }
    "backup" => {
      let stamp = (date now | format date "%Y%m%d-%H%M%S")
      let saved = ($home | path join ".dotfiles-backup" $stamp "powershell" ($profile | path basename))
      if $dry_run { log info $"would move ($profile) to ($saved), then write the stub"; return }
      mkdir ($saved | path dirname)
      mv --force $profile $saved
      $STUB | save --force $profile
      log warn $"($profile) existed; saved to ($saved)"
    }
  }
}
