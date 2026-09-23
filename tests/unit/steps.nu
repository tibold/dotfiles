use ../../lib/steps.nu
use ../../steps/claude.nu
use std/testing *
use std/assert

@test
export def "a plain run leaves out the opt-in steps" [] {
  let s = (steps requested --only "" --with "")
  assert not ("claude" in $s)
  assert ("neovim" in $s)
}

@test
export def "with adds an opt-in step in its place in the order" [] {
  let s = (steps requested --only "" --with "claude")
  assert ("claude" in $s)
  let i = ($s | enumerate | where item == "claude" | first | get index)
  let n = ($s | enumerate | where item == "neovim" | first | get index)
  assert ($i < $n) "claude must run before neovim, which registers its plugin"
}

@test
export def "only runs exactly what was named, opt-in or not" [] {
  assert equal (steps requested --only "claude" --with "") ["claude"]
  assert equal (steps requested --only "links,packages" --with "") ["packages" "links"]
}

@test
export def "an unknown step name is an error in either flag" [] {
  assert error {|| steps requested --only "lnks" --with "" }
  assert error {|| steps requested --only "" --with "claud" }
}

@test
export def "each platform gets only its own shell step" [] {
  assert (steps applies "zsh" "suse")
  assert (steps applies "zsh" "macos")
  assert not (steps applies "zsh" "windows")
  assert (steps applies "powershell" "windows")
  assert not (steps applies "powershell" "debian")
  assert (steps applies "macos" "macos")
  assert not (steps applies "macos" "windows")
  assert (steps applies "neovim" "windows")
  assert (steps applies "claude" "fedora")
}

@test
export def "Claude Code is installed with the official installer for the platform" [] {
  assert str contains (claude installer-command "windows" | str join " ") "install.ps1"
  assert str contains (claude installer-command "debian" | str join " ") "install.sh"
  assert str contains (claude installer-command "macos" | str join " ") "install.sh"
}

@test
export def "the Windows Claude installer runs under Windows PowerShell, which every machine has" [] {
  # pwsh is installed by this same run, under Program Files, where the running
  # process's PATH cannot see it yet.
  assert equal (claude installer-command "windows" | first) "powershell"
}

@test
export def "Unix Claude installer uses set -e to fail safely on download error" [] {
  assert str contains (claude installer-command "debian" | str join " ") "set -e"
  assert str contains (claude installer-command "macos" | str join " ") "set -e"
}

@test
export def "Claude installer commands contain no embedded newlines" [] {
  for family in ["windows" "debian" "macos"] {
    let cmd = (claude installer-command $family)
    for element in $cmd {
      assert not ($element | str contains "\n") $"element contains newline: ($element)"
    }
  }
}
