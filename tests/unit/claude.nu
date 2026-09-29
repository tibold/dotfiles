# The status line the Claude Code step merges into ~/.claude/settings.json.

use ../../steps/claude.nu
use std/testing *
use std/assert

const REPO = (path self | path dirname | path dirname | path dirname)

def fixture []: nothing -> path {
  mktemp --directory --tmpdir "dotfiles-claude-XXXXXX"
}

def settings [home: path]: nothing -> record {
  open --raw ($home | path join ".claude" "settings.json") | from json
}

@test
export def "the status line runs the script this repo ships" [] {
  assert ($REPO | path join "home" ".claude" "statusline-command.sh" | path exists)
  assert str contains $claude.STATUSLINE.command "~/.claude/statusline-command.sh"
}

@test
export def "a missing settings.json is created with just the status line" [] {
  let home = (fixture)
  claude configure-statusline --home $home
  assert equal (settings $home) { statusLine: $claude.STATUSLINE }
  rm --recursive --force $home
}

@test
export def "the rest of settings.json is left alone" [] {
  # Claude Code owns everything else in there, and some of it -- marketplace
  # paths -- only makes sense on the machine that wrote it.
  let home = (fixture)
  mkdir ($home | path join ".claude")
  { model: "opus", statusLine: { type: "command", command: "old" }, effortLevel: "high" }
  | to json | save ($home | path join ".claude" "settings.json")

  claude configure-statusline --home $home
  let s = (settings $home)
  assert equal $s.statusLine $claude.STATUSLINE
  assert equal $s.model "opus"
  assert equal $s.effortLevel "high"
  rm --recursive --force $home
}

@test
export def "a status line already in place is not rewritten" [] {
  assert equal (claude with-statusline { statusLine: $claude.STATUSLINE, model: "opus" }) null
}

@test
export def "a dry run writes nothing" [] {
  let home = (fixture)
  claude configure-statusline --home $home --dry-run
  assert not ($home | path join ".claude" "settings.json" | path exists)
  rm --recursive --force $home
}
