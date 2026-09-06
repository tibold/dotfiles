# Registering nushell's plugins for this user.
#
# A plugin is a separate executable that nushell knows nothing about until it
# is written into the plugin registry, a per-user file (`$nu.plugin-path`,
# ~/.config/nushell/plugin.msgpackz by default). The packages step gets the
# executables onto the machine; this writes them into that file. Every nu
# started afterwards loads them, and `from ini` stops being "extra positional
# argument".
#
# Registered every run rather than skipped when present: `plugin add` runs the
# executable and records its signatures, so it is also how a registration is
# refreshed after an upgrade, and it costs milliseconds.

use ../lib/log.nu
use ../packages/common.nu

# Where a plugin's executable is, or "" when it is not installed.
#
# The directory the running nu came from wins. Plugins speak a protocol that
# is versioned with the shell, and the one shipped alongside this nu -- the
# same package, or the same release archive -- is the one that matches. A
# Fedora box ends up with the distro's old nu in /usr/bin next to the upstream
# one in ~/.local/bin, and looking there first is what keeps them apart.
export def locate [name: string, --bin-dir: path]: nothing -> string {
  let binary = $"nu_plugin_($name)"

  let beside_nu = ($nu.current-exe | path dirname | path join $binary)
  if ($beside_nu | path exists) { return $beside_nu }

  let staged = ($bin_dir | path join $binary)
  if ($staged | path exists) { return $staged }

  let on_path = (which $binary)
  if ($on_path | is-not-empty) { return ($on_path | first | get path) }

  ""
}

# The registry file to write. nushell's own answer for this user; the
# conventional path under any other --home, where nothing has asked nushell.
export def registry [--home: path]: nothing -> path {
  if $home == $nu.home-dir {
    $nu.plugin-path
  } else {
    $home | path join ".config" "nushell" "plugin.msgpackz"
  }
}

export def install [--home: path, --bin-dir: path, --dry-run]: nothing -> nothing {
  log step $"Nushell plugins \(($common.NUSHELL_PLUGINS | str join ', '))"

  let target = (registry --home $home)

  for name in $common.NUSHELL_PLUGINS {
    let path = (locate $name --bin-dir $bin_dir)

    if ($path | is-empty) {
      log warn $"nu_plugin_($name) is not installed -- run the packages step first"
      continue
    }

    if $dry_run {
      log info $"would register ($path) in ($target)"
      continue
    }

    mkdir ($target | path dirname)
    plugin add --plugin-config $target $path
    log ok $"($name) <- ($path)"
  }
}
