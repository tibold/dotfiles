#!/usr/bin/env nu
#
# Run the unit tests.
#
#   nu tests/run.nu                 everything
#   nu tests/run.nu --filter links  only modules whose path matches
#
# Tests are plain commands marked with nushell's @test attribute (std/testing)
# and assert with std/assert. There is no test framework here because nushell
# supplies the two halves that matter: the attribute to mark a test, and
# `scope commands` to find what carries it.
#
# Each module runs in its own `nu` subprocess. That costs a process per file
# and buys two things worth more: a test cannot leak state into the next one,
# and a module that fails to even parse is reported as a failure rather than
# taking the runner down with it.

const DISCOVER = "
scope commands
| where ($it.attributes | any {|a| $a.name == 'test'})
| get name
| to nuon
"

def discover [file: path]: nothing -> list<string> {
  let result = (do { ^nu --no-config-file --commands $"use ($file) *($DISCOVER)" } | complete)

  if $result.exit_code != 0 {
    error make { msg: $"could not load ($file):\n($result.stderr)" }
  }

  $result.stdout | from nuon
}

# Characters that cannot appear in a test name.
#
# The generated driver calls each test by writing its name in command position,
# and nushell has no way to call a command by a quoted or computed name. So a
# name containing a quote or a shell metacharacter would produce source that
# does not parse. Multi-word names are fine -- nushell resolves those natively,
# which is why the tests read as sentences.
const UNSAFE = "[\"'();|$]"

# Build a script that calls every test in the module and reports what happened.
def run-module [file: path]: nothing -> table {
  let names = (try {
    discover $file
  } catch {|e|
    return [{ module: ($file | path basename), name: "<module>", error: $e.msg, output: "" }]
  })
  if ($names | is-empty) { return [] }

  let unsafe = ($names | where {|n| $n =~ $UNSAFE })
  if ($unsafe | is-not-empty) {
    return ($unsafe | each {|n|
      {
        module: ($file | path basename)
        name: $n
        error: "this test name contains a quote or a shell metacharacter, which the runner cannot call -- rename it using plain words"
        output: ""
      }
    })
  }

  let calls = ($names
    | each {|n| $"{ name: \"($n)\", error: \(try { ($n); null } catch {|e| $e.msg }\) }" }
    | str join ", ")

  # The results go to a file rather than stdout because the code under test is
  # allowed to print. Mixing its output into the payload would make a passing
  # test that happens to log look like a corrupt result.
  let outfile = (mktemp --tmpdir "dotfiles-test-XXXXXX.nuon")
  let source = $"use ($file) *\n[ ($calls) ] | to nuon | save --force --raw \"($outfile)\""

  let result = (do { ^nu --no-config-file --commands $source } | complete)

  if $result.exit_code != 0 {
    rm --force $outfile
    return [{ module: ($file | path basename), name: "<module>", error: $"the module aborted:\n($result.stderr)", output: "" }]
  }

  let rows = (open --raw $outfile | from nuon)
  rm --force $outfile

  # Captured output is carried along so a failing test can show what it printed
  # on the way down.
  $rows | each {|row| $row | insert module ($file | path basename) | insert output $result.stdout }
}

def main [--filter: string = ""] {
  let files = (glob ($env.FILE_PWD | path join "unit" "*.nu")
    | where {|f| ($filter | is-empty) or ($f =~ $filter) }
    | sort)

  if ($files | is-empty) {
    print $"no test modules matched '($filter)'"
    return
  }

  let results = ($files | each {|f| run-module $f } | flatten)

  for row in $results {
    if $row.error == null {
      print $"(ansi green)pass(ansi reset)  ($row.module)  ($row.name)"
    } else {
      print $"(ansi red)FAIL(ansi reset)  ($row.module)  ($row.name)"
      print $"      ($row.error | str replace --all "\n" "\n      ")"
      if ($row.output | is-not-empty) {
        print $"      (ansi dark_gray)--- module output ---(ansi reset)"
        print $"      ($row.output | str trim | str replace --all "\n" "\n      ")"
      }
    }
  }

  let failed = ($results | where {|r| $r.error != null })
  print ""
  print $"($results | length) tests, ($failed | length) failed"

  if ($failed | is-not-empty) { exit 1 }
}
