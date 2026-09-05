#!/usr/bin/env nu
#
# Checked INSIDE a container, after bootstrap.sh and install.nu have run.
#
# This is the half that unit tests cannot reach: that the package names in
# packages/ are real names on this distribution, that the links actually
# landed, and that a shell started with these configs does not error.

const REPO = (path self | path dirname | path dirname | path dirname)

use ../../lib/links.nu
use ../../lib/distro.nu
use ../../lib/packages.nu

# Binaries that must be on PATH afterwards, whatever route they arrived by --
# a distro package on one system, an upstream release on another. Written as
# binary names rather than package names on purpose: the package is an
# implementation detail, having the command is the requirement.
const REQUIRED = [
  "nu" "git" "zsh" "tmux" "nvim"
  "rg" "fzf" "jq" "htop" "make" "gcc"
  "lazygit" "delta" "gitleaks" "gh"
]

def check [name: string, ok: bool, detail: string = ""]: nothing -> record {
  { check: $name, ok: $ok, detail: $detail }
}

def main [] {
  let system = (distro detect)
  let home = $nu.home-dir
  mut results = []

  # --- the links ---------------------------------------------------------------
  #
  # Re-planning after the install must report everything as already in place.
  # Anything else means a link did not land, or landed pointing elsewhere.
  let plan = (links plan --root $REPO --home $home)
  let unlinked = ($plan | where action != "ok")

  $results = ($results | append (check "all dotfiles are linked"
    ($unlinked | is-empty)
    $"still pending: ($unlinked | get relative | str join ', ')"))

  # A link that resolves nowhere is worse than no link: the shell reads it as
  # an empty file and starts subtly wrong instead of failing.
  let dangling = ($plan | where {|row| not ($row.target | path exists) })
  $results = ($results | append (check "every link resolves to a real file"
    ($dangling | is-empty)
    $"dangling: ($dangling | get relative | str join ', ')"))

  # --- the tools ---------------------------------------------------------------
  let omitted = ((packages resolve $system).omitted | get tool)
  let expected = ($REQUIRED | where {|b| $b not-in $omitted })
  let missing = ($expected | where {|b| (which $b | is-empty) })

  $results = ($results | append (check "every expected tool is on PATH"
    ($missing | is-empty)
    $"missing: ($missing | str join ', ')"))

  # --- the shells --------------------------------------------------------------
  #
  # An interactive zsh, because that is the one that reads .zshrc and loads Oh
  # My Zsh and every plugin. A non-interactive shell would skip all of it and
  # pass regardless.
  let zsh_run = (do { ^zsh -i -c "exit 0" } | complete)
  $results = ($results | append (check "an interactive zsh starts cleanly"
    ($zsh_run.exit_code == 0)
    ($zsh_run.stderr | str trim)))

  let bash_run = (do { ^bash -i -c "exit 0" } | complete)
  $results = ($results | append (check "an interactive bash starts cleanly"
    ($bash_run.exit_code == 0)
    ($bash_run.stderr | str trim)))

  # --- the prompt --------------------------------------------------------------
  #
  # Asked of zsh rather than of a prompt binary: the prompt comes from an Oh My
  # Zsh theme, so the only meaningful question is whether zsh ends up with one.
  let prompt = (do { ^zsh -i -c 'print -r -- $PROMPT' } | complete)
  let bare = (($prompt.stdout | str trim) in ["%m%# " "%m%#" ""])
  $results = ($results | append (check "zsh ends up with a real prompt"
    (($prompt.exit_code == 0) and (not $bare))
    $"PROMPT is '($prompt.stdout | str trim)'"))

  # Rendering the prompt is a different question from having one, and only the
  # first needs a terminal. `zsh -i -c` reports a clean prompt even while an
  # interactive session prints "closing brace expected" before every line,
  # because the theme only expands its fill when it has a real width to fill.
  # `script` supplies the pty that makes the difference.
  let rendered = (do {
    ^script --quiet --return --command "zsh -il" /dev/null
  } | complete)
  let complaints = ($"($rendered.stdout)($rendered.stderr)"
    | lines
    | where {|l| $l =~ '(?i)zsh:.*(expected|bad|error|not found)' })

  $results = ($results | append (check "an interactive prompt renders without errors"
    ($complaints | is-empty)
    ($complaints | uniq | str join "; ")))

  # The cause of that class of failure, checked directly.
  let locale = (do { ^zsh -i -c 'print -r -- $LANG' } | complete | get stdout | str trim)
  $results = ($results | append (check "zsh runs in a UTF-8 locale"
    ($locale =~ '(?i)utf-?8')
    $"LANG is '($locale)'"))

  # --- the apps actually starting ----------------------------------------------
  #
  # Config files that parse are not the same as programs that run, and this is
  # where that gap showed. An earlier version of this check passed tmux an
  # explicit -S socket path, which quietly sidestepped the only interesting
  # question: tmux is built to put its socket in /run/tmux/$UID, nothing
  # creates that without systemd-tmpfiles, and so tmux would not start at all
  # on a container or a minimal image. Handing it a socket path made the test
  # pass and left the bug in place.
  #
  # So: start tmux the way a person does, with no arguments steering it.
  let tmux_run = (do { ^tmux new-session -d -s verify } | complete)
  $results = ($results | append (check "tmux starts the way you would start it"
    ($tmux_run.exit_code == 0)
    ($"($tmux_run.stdout)($tmux_run.stderr)" | str trim)))

  if $tmux_run.exit_code == 0 {
    # It started, so the config it loaded is this repo's. Prove the status line
    # renders rather than trusting that the file parsed.
    let status = (do { ^tmux display-message -p "#{status-left}" } | complete)
    $results = ($results | append (check "the tmux status line is configured"
      (($status.exit_code == 0) and (($status.stdout | str trim) | is-not-empty))
      ($status.stderr | str trim)))

    # default-terminal has to name an entry this machine's terminfo actually
    # carries. When it does not, tmux starts fine and every login shell inside
    # it then stops at "tset: unknown terminal type ... Terminal type?" -- a
    # failure that never reaches tmux's own exit code, so nothing above catches
    # it.
    # tmux takes its shell from the passwd entry, so this is really a check
    # that the install made zsh the login shell. Getting it wrong is quiet:
    # everything works, you just land in bash with none of this configuration.
    let shell = (do { ^tmux list-panes -F "#{pane_current_command}" } | complete | get stdout | str trim)
    $results = ($results | append (check "tmux opens zsh, not the distro default"
      ($shell == "zsh")
      $"tmux opened '($shell)'"))

    let term = (do { ^tmux display-message -p "#{default-terminal}" } | complete | get stdout | str trim)
    let known = (do { ^infocmp $term } | complete)
    $results = ($results | append (check "tmux names a terminal that terminfo knows"
      ($known.exit_code == 0)
      $"default-terminal is '($term)', which infocmp cannot find"))

    do { ^tmux kill-server } | complete | ignore
  }

  let login_shell = (do { ^getent passwd (^id --user --name | str trim) } | complete
    | get stdout | str trim | split row ":" | last)
  $results = ($results | append (check "the login shell is zsh"
    ($login_shell =~ 'zsh$')
    $"login shell is '($login_shell)'"))

  # The status line calls this every few seconds. tmux runs #() commands
  # asynchronously and shows an empty segment when one fails, so a broken
  # script here is invisible in tmux itself -- the bar just quietly has a hole
  # in it.
  let metrics = (["cpu" "mem" "swap"] | each {|what|
    let run = (do { ^($home | path join ".local" "bin" "tmux-status") $what } | complete)
    { what: $what, ok: (($run.exit_code == 0) and (($run.stdout | str trim) | is-not-empty)), value: ($run.stdout | str trim) }
  })

  $results = ($results | append (check "the status line metrics work"
    ($metrics | all {|m| $m.ok })
    ($metrics | each {|m| $"($m.what)=($m.value)" } | str join " ")))

  let nvim_run = (do { ^nvim --headless -u NONE +qa } | complete)
  $results = ($results | append (check "neovim starts"
    ($nvim_run.exit_code == 0)
    ($nvim_run.stderr | str trim)))

  let lazygit_run = (do { ^lazygit --version } | complete)
  $results = ($results | append (check "lazygit runs"
    ($lazygit_run.exit_code == 0)
    ($lazygit_run.stderr | str trim)))

  # --- the secret scanning hook -------------------------------------------------
  # Only meaningful if the copy under test is a real checkout; the step
  # correctly declines to configure hooks otherwise.
  if ($REPO | path join ".git" | path exists) {
    let hooks_path = (do { ^git -C $REPO config core.hooksPath } | complete)
    $results = ($results | append (check "the pre-commit hook is wired up"
      (($hooks_path.stdout | str trim) == "githooks")
      $"core.hooksPath is '($hooks_path.stdout | str trim)'"))

    let scan = (do { ^git -C $REPO -c core.hooksPath=githooks hook run pre-commit } | complete)
    $results = ($results | append (check "the secret scan runs and finds nothing"
      ($scan.exit_code == 0)
      ($scan.stderr | str trim)))
  }

  # --- report ------------------------------------------------------------------
  print $"(ansi cyan_bold)($system.pretty)(ansi reset)"
  for r in $results {
    if $r.ok {
      print $"  (ansi green)pass(ansi reset)  ($r.check)"
    } else {
      print $"  (ansi red)FAIL(ansi reset)  ($r.check)"
      if ($r.detail | is-not-empty) { print $"        ($r.detail)" }
    }
  }

  let failed = ($results | where {|r| not $r.ok })
  print $"  ($results | length) checks, ($failed | length) failed"

  if ($failed | is-not-empty) { exit 1 }
}
