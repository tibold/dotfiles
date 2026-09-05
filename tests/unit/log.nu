use ../../lib/log.nu
use std/testing *
use std/assert

# Regression tests for lib/log.nu's `shell`.
#
# This is the command every package install, removal and clone goes through,
# and until the container tests ran it was silently dropping every argument:
# `log skip` shadowed the builtin `skip`, so `$argv | skip 1` called the logger
# instead of dropping the command name, and `sudo zypper install ...` reached
# the system as a bare `sudo`. --dry-run returns before that line, which is why
# nothing here noticed.

@test
export def "arguments survive the trip to the command" [] {
  assert equal (log shell ["echo" "one" "two"] | complete | get stdout | str trim) "one two"
}

@test
export def "a single-argument command still runs" [] {
  assert equal (log shell ["true"] | complete | get exit_code) 0
}

@test
export def "a dry run runs nothing at all" [] {
  # `false` would make this fail if --dry-run ever started executing.
  log shell ["false"] --dry-run
  assert true
}

@test
export def "a failing command reports its failure" [] {
  assert equal (log shell ["false"] | complete | get exit_code) 1
}
