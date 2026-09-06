use ../../steps/plugins.nu
use ../../lib/fallback.nu
use ../../packages/common.nu
use ../../packages/suse.nu
use std/testing *
use std/assert

# The one list, and the two places that have to restate it because a const
# cannot be computed from another. Either drifting would mean a plugin that is
# installed on one distro and silently absent on the next.
@test
export def "openSUSE packages one plugin per entry in the list" [] {
  let expected = ($common.NUSHELL_PLUGINS | each {|p| $"nushell-plugin_($p)" })
  assert equal $suse.OVERRIDES.nushell-plugins $expected
}

@test
export def "the upstream fallback fetches one binary per entry in the list" [] {
  let expected = ($common.NUSHELL_PLUGINS | each {|p| $"nu_plugin_($p)" })
  assert equal $fallback.SOURCES.nushell-plugins.binaries $expected
}

@test
export def "the plugins come from the same archive as the shell" [] {
  # Upstream ships them together; taking them from anywhere else would risk a
  # protocol mismatch with the nu that bootstrap.sh fetched.
  assert equal $fallback.SOURCES.nushell-plugins.assets $fallback.SOURCES.nushell.assets
  assert equal $fallback.SOURCES.nushell-plugins.repo $fallback.SOURCES.nushell.repo
}

@test
export def "polars is not on the list" [] {
  # 120 MB of dataframe library that nothing here uses. If it is ever wanted,
  # add it deliberately and delete this test.
  assert ("polars" not-in $common.NUSHELL_PLUGINS)
}

@test
export def "a plugin in bin-dir is found" [] {
  let dir = (mktemp --directory --tmpdir "dotfiles-plugins-XXXXXX")
  touch ($dir | path join "nu_plugin_zzz")

  assert equal (plugins locate "zzz" --bin-dir $dir) ($dir | path join "nu_plugin_zzz")

  rm --recursive --force $dir
}

@test
export def "a plugin that is nowhere yields an empty path" [] {
  let dir = (mktemp --directory --tmpdir "dotfiles-plugins-XXXXXX")
  assert equal (plugins locate "does-not-exist" --bin-dir $dir) ""
  rm --recursive --force $dir
}

@test
export def "the registry for another home lives under that home" [] {
  assert equal (plugins registry --home "/elsewhere") "/elsewhere/.config/nushell/plugin.msgpackz"
}

@test
export def "the registry for this home is the one nushell reports" [] {
  assert equal (plugins registry --home $nu.home-dir) $nu.plugin-path
}
