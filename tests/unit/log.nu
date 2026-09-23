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

# The commands these run are nushell itself rather than `true` and `false`,
# which Windows only has when Git's usr/bin is on PATH -- and the suite has to
# pass from a plain pwsh too.
const SUCCEED = ["--no-config-file" "-c" "exit 0"]
const FAIL = ["--no-config-file" "-c" "exit 1"]

@test
export def "a single-argument command still runs" [] {
  # A command with nothing after its name, so `slice 1..` sees a one-element
  # list. hostname.exe lives in System32 on every Windows; `true` everywhere
  # else.
  let alone = (if $nu.os-info.name == "windows" { "hostname" } else { "true" })
  assert equal (log shell [$alone] | complete | get exit_code) 0
}

@test
export def "a command that succeeds reports success" [] {
  assert equal (log shell [$nu.current-exe ...$SUCCEED] | complete | get exit_code) 0
}

@test
export def "a dry run runs nothing at all" [] {
  # A failing command would make this fail if --dry-run ever started executing.
  log shell [$nu.current-exe ...$FAIL] --dry-run
  assert true
}

@test
export def "a failing command reports its failure" [] {
  assert equal (log shell [$nu.current-exe ...$FAIL] | complete | get exit_code) 1
}

@test
export def "render displays arguments with proper quoting for spaces" [] {
  assert equal (log render ["sh" "-c" "a b"]) "sh -c 'a b'"
}

@test
export def "render displays arguments with proper quoting for pipes" [] {
  assert equal (log render ["sh" "-c" "a | b"]) "sh -c 'a | b'"
}

@test
export def "render leaves plain arguments unquoted" [] {
  assert equal (log render ["echo" "hello"]) "echo hello"
}

@test
export def "render escapes embedded single quotes" [] {
  assert equal (log render ["printf" "it's"]) "printf 'it'\\''s'"
}

@test
export def "render produces one-line output for complex commands" [] {
  use ../../steps/claude.nu
  let debian_cmd = (claude installer-command "debian")
  let rendered = (log render $debian_cmd)
  # Must be a single line (no newlines)
  assert equal ($rendered | str contains "\n") false
  # Must contain the key components
  assert str contains $rendered "sh"
  assert str contains $rendered "set -e"
  assert str contains $rendered "install.sh"
}

@test
export def "render wraps arguments containing tabs or newlines" [] {
  assert str contains (log render ["echo" "a\tb"]) "'"
  assert str contains (log render ["echo" "a\nb"]) "'"
}
