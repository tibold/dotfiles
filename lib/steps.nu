# The installer's steps, which of them run where, and which run only when asked.
#
# Kept out of install.nu so the rules can be tested; install.nu only dispatches.

# Order matters. Packages first because later steps need what they install;
# databases right after them, being more of the same; claude before neovim so
# the plugin in the neovim config can be registered in the same run; macos
# last. Every name is here on every platform so `--only X` answers "that step
# does not apply here" rather than "unknown step".
export const ORDER = ["packages" "databases" "plugins" "cleanup" "links" "appdirs" "zsh" "powershell" "claude" "neovim" "hooks" "macos"]

# Run only when named, with --with or --only. Claude Code is a personal tool
# that authenticates interactively, and not every machine this repo lands on
# should have it. The database clients (DATABASES in packages/common.nu) are
# for the neovim database plugin, which most machines never use.
export const OPT_IN = ["claude" "databases"]

def names [csv: string]: nothing -> list<string> {
  let wanted = ($csv | split row "," | each {|s| $s | str trim } | where {|s| $s | is-not-empty })
  let unknown = ($wanted | where {|s| $s not-in $ORDER })
  if ($unknown | is-not-empty) {
    error make { msg: $"unknown step\(s): ($unknown | str join ', ') -- pick from ($ORDER | str join ', ')" }
  }
  $wanted
}

export def requested [--only: string = "", --with: string = ""]: nothing -> list<string> {
  let only = (names $only)
  let with = (names $with)
  let wanted = (if ($only | is-not-empty) { $only } else {
    ($ORDER | where {|s| $s not-in $OPT_IN }) ++ $with
  })
  # Canonical order regardless of the order they were typed in.
  $ORDER | where {|s| $s in $wanted }
}

export def applies [step: string, family: string]: nothing -> bool {
  match $step {
    "zsh" => ($family != "windows")
    "powershell" => ($family == "windows")
    "macos" => ($family == "macos")
    _ => true
  }
}

export def platform-note [step: string]: nothing -> string {
  match $step {
    "zsh" => "zsh: that step does not apply on Windows -- see powershell"
    "powershell" => "powershell: that step only applies to Windows"
    "macos" => "macos: that step only applies to macOS"
    _ => $"($step): does not apply here"
  }
}
