use ../../lib/steps.nu
use ../../steps/k8s.nu
use std/testing *
use std/assert

@test
export def "k8s-tools is opt-in and runs right after the other package groups" [] {
  assert not ("k8s-tools" in (steps requested --only "" --with ""))
  let s = (steps requested --only "" --with "k8s-tools,databases")
  assert equal ($s | take 3) ["packages" "databases" "k8s-tools"]
  for family in ["windows" "macos" "debian" "suse" "fedora"] {
    assert (steps applies "k8s-tools" $family)
  }
}

@test
export def "krew downloads the build for this machine" [] {
  assert equal (k8s krew-asset "linux" "x86_64") { download: "krew-linux_amd64.tar.gz", binary: "krew-linux_amd64" }
  assert equal (k8s krew-asset "linux" "aarch64") { download: "krew-linux_arm64.tar.gz", binary: "krew-linux_arm64" }
  assert equal (k8s krew-asset "macos" "aarch64") { download: "krew-darwin_arm64.tar.gz", binary: "krew-darwin_arm64" }
  # A bare executable, so nothing to unpack -- whatever the CPU.
  assert equal (k8s krew-asset "windows" "aarch64") { download: "krew.exe", binary: "krew.exe" }
}

@test
export def "krew lives in KREW_ROOT when it is set" [] {
  with-env { KREW_ROOT: "/opt/krew" } {
    assert equal (k8s krew-path "debian") ("/opt/krew" | path join "bin" "kubectl-krew")
    assert equal (k8s krew-path "windows") ("/opt/krew" | path join "bin" "kubectl-krew.exe")
  }
}

@test
export def "the plugin list is read with or without its heading" [] {
  assert equal (k8s installed-plugins "cnpg\nkrew\n") ["cnpg" "krew"]
  assert equal (k8s installed-plugins "PLUGIN  VERSION\ncnpg    v1.27.0\nkrew    v0.5.0\n") ["cnpg" "krew"]
  assert equal (k8s installed-plugins "") []
}

@test
export def "a fresh krew installs every plugin and upgrades itself" [] {
  let cmds = (k8s krew-commands "kubectl-krew" $k8s.PLUGINS ["krew"])
  assert equal $cmds [
    ["kubectl-krew" "update"]
    (["kubectl-krew" "install"] ++ $k8s.PLUGINS)
    ["kubectl-krew" "upgrade" "krew"]
  ]
}

@test
export def "an upgrade with nothing newer is not a failure" [] {
  assert (k8s up-to-date "Upgrading plugin: krew\nfailed to upgrade plugin \"krew\": can't upgrade, the newest version is already installed\n")
  assert not (k8s up-to-date "failed to upgrade plugin \"cnpg\": Access is denied.")
}

@test
export def "only the missing plugins are installed, and only ours upgraded" [] {
  let cmds = (k8s krew-commands "kubectl-krew" $k8s.PLUGINS ["krew" "cnpg" "ctx" "ns" "stern" "tree"])
  assert equal $cmds [
    ["kubectl-krew" "update"]
    ["kubectl-krew" "upgrade" "krew"]
    ["kubectl-krew" "upgrade" "cnpg"]
    ["kubectl-krew" "upgrade" "ctx"]
    ["kubectl-krew" "upgrade" "ns"]
    ["kubectl-krew" "upgrade" "stern"]
  ]
  let partial = (k8s krew-commands "kubectl-krew" $k8s.PLUGINS ["krew" "ctx"])
  assert equal ($partial | get 1) ["kubectl-krew" "install" "cnpg" "ns" "stern"]
}

@test
export def "Windows takes ctx and ns from winget, and everything else from krew" [] {
  let krew = (k8s krew-plugins "windows")
  for p in ($k8s.WINGET_PLUGINS | columns) {
    assert ($p in $k8s.PLUGINS) $"($p) comes from winget but is not one of the plugins"
    assert ($p not-in $krew) $"($p) has no Windows build in krew but is still asked of it"
  }
  assert equal ($krew | length) (($k8s.PLUGINS | length) - ($k8s.WINGET_PLUGINS | columns | length))
  assert equal (k8s krew-plugins "debian") $k8s.PLUGINS
  assert equal (k8s krew-plugins "macos") $k8s.PLUGINS
}
