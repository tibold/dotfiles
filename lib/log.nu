# Console output for the installer.
#
# Everything user-facing goes through here so that the container tests have a
# single place to intercept, and so --dry-run reads the same as a real run.

export def step [msg: string] {
  print $"(ansi cyan_bold)==>(ansi reset) ($msg)"
}

export def info [msg: string] {
  print $"    ($msg)"
}

export def ok [msg: string] {
  print $"    (ansi green)ok(ansi reset)   ($msg)"
}

# Named "skipped" rather than "skip" on purpose. A command defined in this
# module shadows the builtin of the same name for every other command in it,
# and `skip` is a real builtin -- so `log skip` quietly turned `$argv | skip 1`
# below into a call to itself, and every package install ran a bare `sudo` with
# no arguments. --dry-run never reached that line, so only the container tests
# caught it.
export def skipped [msg: string] {
  print $"    (ansi dark_gray)skip ($msg)(ansi reset)"
}

export def warn [msg: string] {
  print --stderr $"    (ansi yellow)warn(ansi reset) ($msg)"
}

# Run an external command, or describe it, depending on --dry-run.
#
# Package installs and git clones are the only things here that touch the
# system, and they all funnel through this, which is what makes --dry-run
# trustworthy rather than best-effort.
export def --env shell [argv: list<string>, --dry-run] {
  if $dry_run {
    info $"would run: ($argv | str join ' ')"
    return
  }
  info $"($argv | str join ' ')"
  let cmd = ($argv | first)
  # `slice` rather than `skip`, so re-adding a command named `skip` to this
  # module cannot silently break command execution again.
  let rest = ($argv | slice 1..)
  ^$cmd ...$rest
}
