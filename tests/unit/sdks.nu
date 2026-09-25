use ../../lib/steps.nu
use ../../steps/dotnet.nu
use ../../steps/rust.nu
use std/testing *
use std/assert

def release [channel: string, type: string, phase: string]: nothing -> record {
  { channel-version: $channel, release-type: $type, support-phase: $phase }
}

@test
export def "the SDK steps are opt-in and run before neovim" [] {
  let plain = (steps requested --only "" --with "")
  assert not ("dotnet" in $plain)
  assert not ("rust" in $plain)
  let s = (steps requested --only "" --with "rust,dotnet")
  let n = ($s | enumerate | where item == "neovim" | first | get index)
  for step in ["dotnet" "rust"] {
    let i = ($s | enumerate | where item == $step | first | get index)
    assert ($i < $n) $"($step) must run before neovim"
    assert (steps applies $step "windows")
    assert (steps applies $step "macos")
  }
}

@test
export def "one .NET SDK when the newest release is the LTS" [] {
  let index = [
    (release "11.0" "sts" "go-live")
    (release "10.0" "lts" "active")
    (release "9.0" "sts" "maintenance")
    (release "8.0" "lts" "maintenance")
  ]
  assert equal (dotnet channels $index) ["10.0"]
}

@test
export def "the newest LTS and the newest release when they differ, in any index order" [] {
  let index = [
    (release "10.0" "lts" "active")
    (release "11.0" "sts" "active")
    (release "12.0" "lts" "preview")
    (release "7.0" "sts" "eol")
  ]
  assert equal (dotnet channels $index) ["10.0" "11.0"]
}

@test
export def "an index with nothing supported is an error, not an empty install" [] {
  assert error {|| dotnet channels [(release "11.0" "sts" "preview")] }
}

@test
export def "winget has one .NET SDK package per major" [] {
  assert equal (dotnet winget-id "10.0") "Microsoft.DotNet.SDK.10"
}

@test
export def "dotnet-install runs under bash with the channel and directory as arguments" [] {
  let cmd = (dotnet installer-command "10.0" "/home/me/.dotnet")
  assert equal ($cmd | first) "bash"
  assert str contains ($cmd | get 2) "set -e"
  assert equal ($cmd | last 2) ["10.0" "/home/me/.dotnet"]
  for element in $cmd { assert not ($element | str contains "\n") }
}

@test
export def "rustup leaves the shell profiles to this repo" [] {
  let cmd = (rust installer-command "debian" | str join " ")
  assert str contains $cmd "--no-modify-path"
  assert str contains $cmd "set -e"
  assert str contains (rust installer-command "windows" | str join " ") "Rustlang.Rustup"
}

@test
export def "the toolchain brings what an editor needs, and keeps a chosen default" [] {
  let cmds = (rust toolchain-commands "rustup" true)
  let components = ($cmds | where {|c| "component" in $c } | first)
  for c in ["rust-analyzer" "rust-src" "clippy" "rustfmt"] { assert ($c in $components) }
  assert ($cmds | all {|c| "default" not-in ($c | slice 1..1) })
  assert (rust toolchain-commands "rustup" false | any {|c| ($c | slice 1..) == ["default" "stable"] })
}

@test
export def "the Build Tools install brings the C++ workload and the Windows SDK" [] {
  let cmd = (rust build-tools-command)
  let override = ($cmd | get (($cmd | enumerate | where item == "--override" | first | get index) + 1))
  assert str contains $override "Microsoft.VisualStudio.Workload.VCTools"
  assert str contains $override "--includeRecommended"
  assert str contains $override "--wait"
}
