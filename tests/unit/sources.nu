# Static checks over the repo's own nushell sources.
#
# Nushell resolves a command name at parse time, but a module is only parsed
# when something uses it -- so a typo in a rarely-taken branch survives every
# run until that branch executes. This is the cheap way to find those.

use std/testing *
use std/assert

const REPO = (path self | path dirname | path dirname | path dirname)
const SELF = (path self)

# tests/container/run.nu copies the whole repo here while it works. It is a
# transient build artifact, and scanning it means every finding is reported
# twice -- once for the real file and once for its copy.
const STAGING = ($REPO | path join "tests" "container" "staging")

def sources []: nothing -> list<path> {
  let files = ([ "lib" "steps" "tools" "tests" ]
    | each {|dir| glob ($REPO | path join $dir "**" "*.nu") --no-dir }
    | flatten
    | append ($REPO | path join "install.nu")
    # This file talks *about* log calls in its test names and messages, which
    # the scan below cannot tell from a real one.
    | where {|f| $f != $SELF }
    | where {|f| not ($f | str starts-with $STAGING) })

  assert (($files | length) > 5) "the source glob found almost nothing -- wrong repo root?"
  $files
}

# Comments stripped: this file and lib/log.nu both discuss `log skip` in prose,
# and prose is not a call.
def code [file: path]: nothing -> string {
  open --raw $file
  | lines
  | each {|l| $l | str replace --regex '#.*$' '' }
  | str join "\n"
}

@test
export def "every log call names a command that exists" [] {
  # The regression this exists for: `log skip` was renamed to `log skipped`,
  # one caller was missed, and it only surfaced as "Command `log` not found" on
  # Ubuntu -- because that branch only runs on a distro that omits a package.
  # Read from the source rather than from `scope commands`: a module imported
  # without a glob does not surface its subcommands there, and this way the
  # check does not depend on how the test module happens to import it.
  let defined = (open --raw ($REPO | path join "lib" "log.nu")
    | parse --regex '(?m)^export def (?:--env )?([a-z][a-z-]*)'
    | get capture0)

  assert ($defined | is-not-empty) "no exported commands found in lib/log.nu"

  for file in (sources) {
    let called = (code $file
      | parse --regex '(?m)(?:^|[|(\s])log ([a-z][a-z-]*)'
      | get capture0
      | uniq)

    for name in $called {
      assert ($name in $defined) $"($file | path basename) calls `log ($name)`, which lib/log.nu does not export \(it has: ($defined | str join ', '))"
    }
  }
}

@test
export def "no source file calls a step entry point named run" [] {
  # `run` is a parser keyword in nushell and cannot be a command name. Defining
  # one fails at parse time with a message that does not mention your code, so
  # it is worth naming outright.
  for file in (sources) {
    assert not ((code $file) =~ '(?m)^\s*export def run \[') $"($file | path basename) defines `run`, which is a reserved parser keyword"
  }
}

@test
export def "nothing depends on the GitHub API" [] {
  # api.github.com allows 60 unauthenticated calls an hour per IP address. A
  # few container-test runs exhaust that, and it then answers 403 in a way that
  # reads like "this release does not exist" -- which cost a debugging cycle.
  # Release lookups go through the redirect on github.com/.../releases/latest
  # instead, which is not rationed.
  for file in (sources) {
    assert not ((code $file) =~ 'api\.github\.com') $"($file | path basename) calls the GitHub API, which is rate limited"
  }

  let bootstrap = ($REPO | path join "bootstrap.sh")
  assert not ((open --raw $bootstrap) =~ '(?m)^[^#]*api\.github\.com') "bootstrap.sh calls the GitHub API, which is rate limited"
}
