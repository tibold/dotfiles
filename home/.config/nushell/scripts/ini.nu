# `to ini`, which nushell does not have.
#
# The formats plugin parses ini (`from ini`) but has never written it: the
# parsers were moved out of core in 0.76 and no writer came with them, and
# the one pull request that added one (nushell/nushell#18509, July 2026) was
# abandoned by its author. Until something lands upstream, this is it.
#
# Mirrors what `from ini` produces, so the two round-trip:
#
#   { "": { global: 1 }, server: { port: 8080, name: "my server" } }
#
# becomes
#
#   global=1
#
#   [server]
#   port=8080
#   name=my server
#
# Top-level scalars, and everything under the "" key, are global keys and go
# first -- ini binds every key after a header to that section, so they cannot
# come later. Each record-valued key is a [section]. ini cannot nest deeper
# than that, so a list, or a record inside a section, is an error rather than
# something mangled into a string.
#
# Values are written bare, with no quoting: ini has no standard quoting, and
# `from ini` hands back whatever text is after the `=`. A newline in a value
# has no representation and is rejected.
#
# Load it in a script with `use ini.nu *`; ~/.config/nushell/scripts is on
# nushell's library path. The REPL gets it through autoload/formats.nu.

def scalar [key: string, value: any, where: string]: nothing -> string {
  let kind = ($value | describe)
  if ($kind =~ '^(record|list|table)') {
    error make {
      msg: $"to ini: ($where)'($key)' is a ($kind), and ini cannot nest that deep"
    }
  }
  let text = (if $value == null { "" } else { $"($value)" })
  if ($text | str contains "\n") {
    error make { msg: $"to ini: ($where)'($key)' contains a newline, which ini cannot represent" }
  }
  $"($key)=($text)"
}

def section-lines [name: string, body: record]: nothing -> list<string> {
  let where = (if ($name | is-empty) { "" } else { $"[($name)] " })
  $body | items {|k, v| scalar $k $v $where }
}

# Convert a record into an ini string.
export def "to ini" []: record -> string {
  let input = $in

  # Global keys: the "" section as `from ini` reports it, plus any scalar
  # written directly at the top level, which is the natural way to type one.
  let named_globals = ($input | get --optional "" | default {})
  if ($named_globals | describe) !~ '^record' {
    error make { msg: "to ini: the \"\" key holds the global section and must be a record" }
  }
  let loose_globals = ($input
    | reject --optional ""
    | items {|k, v| if ($v | describe) !~ '^record' { { key: $k, value: $v } } }
    | compact)

  let globals = (
    (section-lines "" $named_globals)
    ++ ($loose_globals | each {|g| scalar $g.key $g.value "" })
  )

  let sections = ($input
    | reject --optional ""
    | items {|name, body| if ($body | describe) =~ '^record' { { name: $name, body: $body } } }
    | compact
    | each {|s| [$"[($s.name)]"] ++ (section-lines $s.name $s.body) })

  let blocks = (if ($globals | is-empty) { $sections } else { [$globals] ++ $sections })

  $blocks | each {|b| $b | str join "\n" } | str join "\n\n"
}
