# Rebuild PATH on Windows from what the registry says it is now.
#
# winget installs MSI packages -- PowerShell, Git, Neovim -- under Program
# Files and records their directories in the registry's PATH, not in winget's
# Links directory. A process that is already running never sees that change:
# its PATH was copied from the registry when it started. So without this, the
# first run on a fresh machine installs pwsh and then skips the powershell step
# because pwsh "is not installed", and a checkout downloaded as a zip has no git
# for the neovim clone. Rebuilding PATH after the packages step is what a new
# terminal would do anyway.

# Where Windows keeps the machine-wide and the per-user PATH.
const MACHINE_KEY = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
const USER_KEY = 'Environment'

# Two spellings of the same directory: Windows compares paths without regard
# to case, and a trailing separator changes nothing.
def key [dir: string]: nothing -> string {
  $dir | str lowercase | str replace --regex '[\\/]+$' ''
}

# The PATH to use from here on, as a list.
#
# Pure, so it can be tested with fixture strings on any platform. `machine` and
# `user` are the registry's ';'-separated values with %VARS% already expanded
# (`registry query` expands REG_EXPAND_SZ by default). Order is `prepend`
# first -- the directories install.nu puts in front on purpose -- then machine,
# then user, which is the order Windows itself builds a new process's PATH in.
# Whatever else the current PATH holds (what bootstrap.ps1 or Git Bash added
# for this session) is kept at the end rather than dropped. Each directory
# appears once, at its first position.
export def merge [
  current: list<string>
  machine: string
  user: string
  --prepend: list<string> = []
]: nothing -> list<string> {
  let split = {|s: string| $s | split row ";" | each {|d| $d | str trim } | where {|d| $d | is-not-empty } }
  let all = ($prepend ++ (do $split $machine) ++ (do $split $user) ++ $current)
  $all
  | reduce --fold { seen: [], dirs: [] } {|dir, acc|
      let k = (key $dir)
      if $k in $acc.seen { $acc } else { { seen: ($acc.seen | append $k), dirs: ($acc.dirs | append $dir) } }
    }
  | get dirs
}

# Read one PATH value from the registry, or "" when there is none -- a user
# account with no PATH of its own is normal.
def read [hive: string, key: string]: nothing -> string {
  try {
    if $hive == "hklm" {
      registry query --hklm $key Path | get value
    } else {
      registry query --hkcu $key Path | get value
    }
  } catch { "" }
}

# Replace this process's PATH with the registry's, keeping `prepend` in front.
export def --env refresh [--prepend: list<string> = []] {
  let current = (if ($env.PATH | describe) =~ '^list' { $env.PATH } else { $env.PATH | split row (char esep) })
  $env.PATH = (merge $current (read "hklm" $MACHINE_KEY) (read "hkcu" $USER_KEY) --prepend $prepend)
}
