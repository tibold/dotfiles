# `to ini`, the writer nushell's formats plugin does not have. Lives in home/
# because it is shell configuration, tested here because it is code.

use ../../home/.config/nushell/scripts/ini.nu *
use std/testing *
use std/assert

@test
export def "sections become headers with one key per line" [] {
  let out = ({ server: { port: 8080, name: "my server" } } | to ini)
  assert equal $out "[server]\nport=8080\nname=my server"
}

@test
export def "globals come before the first section" [] {
  # ini binds every key after a header to that section, so a global that
  # came later would silently join the last section.
  let out = ({ server: { port: 1 }, debug: true } | to ini)
  assert equal $out "debug=true\n\n[server]\nport=1"
}

@test
export def "the empty-named section is the global one, as from ini reports it" [] {
  let out = ({ "": { global: 1 }, s: { k: v } } | to ini)
  assert equal $out "global=1\n\n[s]\nk=v"
}

@test
export def "sections are separated by a blank line" [] {
  let out = ({ a: { x: 1 }, b: { y: 2 } } | to ini)
  assert equal $out "[a]\nx=1\n\n[b]\ny=2"
}

@test
export def "an empty section is just its header" [] {
  assert equal ({ empty: {} } | to ini) "[empty]"
}

@test
export def "a null value is written empty" [] {
  assert equal ({ s: { k: null } } | to ini) "[s]\nk="
}

@test
export def "values are written bare" [] {
  # No quoting: ini has none, and from ini returns the raw text after `=`.
  assert equal ({ s: { path: "/a b/c", eq: "x=y" } } | to ini) "[s]\npath=/a b/c\neq=x=y"
}

@test
export def "a record inside a section is refused" [] {
  let failed = (try { { s: { deep: { k: 1 } } } | to ini; false } catch { true })
  assert $failed "ini cannot nest two levels deep; that should be an error, not a mangled string"
}

@test
export def "a list is refused" [] {
  let failed = (try { { s: { items: [1 2] } } | to ini; false } catch { true })
  assert $failed
}

@test
export def "a newline in a value is refused" [] {
  let failed = (try { { s: { k: "a\nb" } } | to ini; false } catch { true })
  assert $failed
}

@test
export def "an empty record is an empty string" [] {
  assert equal ({} | to ini) ""
}
