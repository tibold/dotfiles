# The startup check for a plugin registry left behind by an upgrade. Lives in
# home/ because it is shell configuration, tested here because it is code.

use ../../home/.config/nushell/scripts/plugin-check.nu
use std/testing *
use std/assert

@test
export def "a plugin whose executable is gone is reported" [] {
  let dir = (mktemp --directory --tmpdir "dotfiles-plugin-check-XXXXXX")
  let present = ($dir | path join "nu_plugin_inc")
  touch $present

  let registry = [
    { name: "inc", filename: $present }
    { name: "formats", filename: ($dir | path join "0.115.1" "nu_plugin_formats") }
  ]
  assert equal ($registry | plugin-check missing) ["formats"]

  rm --recursive $dir
}

@test
export def "an empty registry has nothing missing" [] {
  assert equal ([] | plugin-check missing) []
}
