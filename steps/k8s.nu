# Kubernetes clients: kubectl, helm and k9s, then krew and a few kubectl
# plugins through it. Opt-in: see OPT_IN in lib/steps.nu.
#
# The clients are K8S_TOOLS in packages/common.nu, installed by the packages
# step's machinery like any other group -- the overlays name them, and Linux
# takes an upstream release where the archive has nothing.
#
# The plugins come from krew, kubectl's plugin manager, rather than from each
# platform's packages: only Tumbleweed packages any of them, and krew installs
# the same builds the same way everywhere -- but for two with no Windows build,
# see WINGET_PLUGINS. No platform packages krew itself in
# a way that helps -- none of the Linux distributions has it at all -- so it
# is fetched from its release and installs itself into ~/.krew, which is also
# how it later upgrades itself. ~/.profile, ~/.zshrc and the pwsh profile put
# ~/.krew/bin on PATH; that is where kubectl looks for kubectl-<name>.

use ../lib/log.nu
use ../lib/distro.nu
use packages.nu

# cnpg   CloudNativePG: cluster status, promote, psql into an instance, backups
# ctx    kubectx: switch context, `kubectl ctx` alone picks one through fzf
# ns     kubens: the same for the current namespace
# stern  tail logs from every pod matching a pattern at once, one colour each
export const PLUGINS = ["cnpg" "ctx" "ns" "stern"]

# krew's ctx and ns have no Windows build. winget has the same programs, but
# only under their own names: the package's alias wins over `--rename`, so on
# Windows they are `kubectx` and `kubens`, not `kubectl ctx` and `kubectl ns`.
export const WINGET_PLUGINS = { ctx: "ahmetb.kubectx", ns: "ahmetb.kubens" }

# The plugins krew installs on this platform.
export def krew-plugins [family: string]: nothing -> list<string> {
  if $family == "windows" { $PLUGINS | where {|p| $p not-in ($WINGET_PLUGINS | columns) } } else { $PLUGINS }
}

const RELEASES = "https://github.com/kubernetes-sigs/krew/releases/latest/download"

# What to download for this machine, and what the executable in it is called.
# Windows has a bare krew.exe, so nothing to unpack; there is no arm64 Windows
# build, and the amd64 one runs there under emulation.
export def krew-asset [os: string, arch: string]: nothing -> record {
  if $os == "windows" { return { download: "krew.exe", binary: "krew.exe" } }
  let platform = (match $os {
    "linux" => "linux"
    "macos" => "darwin"
    _ => { error make { msg: $"krew has no build for ($os)" } }
  })
  let cpu = (match $arch {
    "x86_64" => "amd64"
    "aarch64" => "arm64"
    _ => { error make { msg: $"krew has no ($os) build for ($arch)" } }
  })
  let name = $"krew-($platform)_($cpu)"
  { download: $"($name).tar.gz", binary: $name }
}

export def krew-path [family: string]: nothing -> path {
  let root = ($env.KREW_ROOT? | default ($nu.home-dir | path join ".krew"))
  $root | path join "bin" (if $family == "windows" { "kubectl-krew.exe" } else { "kubectl-krew" })
}

# The plugin names in `krew list` output: one per line, or a table under a
# PLUGIN heading, depending on the version and on whether it is a terminal.
export def installed-plugins [output: string]: nothing -> list<string> {
  $output | lines | each {|l| $l | str trim | split row " " | first } | where {|n| $n | is-not-empty } | where {|n| $n != "PLUGIN" }
}

# Refresh the index, add what is missing, and bring what is already there up
# to date -- only the ones named here, and krew itself: plugins someone
# installed by hand are theirs to upgrade.
export def krew-commands [krew: string, plugins: list<string>, installed: list<string>]: nothing -> list<list<string>> {
  let missing = ($plugins | where {|p| $p not-in $installed })
  let present = (["krew"] ++ $plugins | where {|p| $p in $installed })
  let install = (if ($missing | is-empty) { [] } else { [([$krew "install"] ++ $missing)] })
  # One at a time: see up-to-date below.
  let upgrade = ($present | each {|p| [$krew "upgrade" $p] })
  [[$krew "update"]] ++ $install ++ $upgrade
}

# `krew upgrade NAME` fails when NAME is already at its newest version, where
# a bare `krew upgrade` would skip it. That is the usual case on a re-run, not
# a failure.
export def up-to-date [output: string]: nothing -> bool {
  $output | str contains "the newest version is already installed"
}

def run-krew [argv: list<string>, --dry-run]: nothing -> nothing {
  if $dry_run or ($argv | get 1) != "upgrade" {
    log shell $argv --dry-run=$dry_run
    return
  }
  log info (log render $argv)
  let result = (do { ^($argv | first) ...($argv | slice 1..) } | complete)
  if $result.exit_code != 0 and not (up-to-date $"($result.stdout)($result.stderr)") {
    print --stderr $result.stderr
    error make { msg: $"(log render $argv) failed" }
  }
}

# krew's documented install: run the release's own binary, which copies itself
# into ~/.krew as the krew plugin.
def bootstrap [--dry-run]: nothing -> nothing {
  let asset = (krew-asset $nu.os-info.name $nu.os-info.arch)
  let url = $"($RELEASES)/($asset.download)"
  if $dry_run {
    log info $"would fetch ($url) and run `($asset.binary) install krew`"
    return
  }
  let dir = (mktemp --directory --tmpdir "dotfiles-krew-XXXXXX")
  let file = ($dir | path join $asset.download)
  http get $url | save --raw --force $file
  if $asset.download != $asset.binary {
    ^tar --extract --gzip --file $file --directory $dir
  }
  try {
    log shell [($dir | path join $asset.binary) "install" "krew"]
  } catch {|e|
    rm --recursive --force $dir
    error make { msg: $e.msg }
  }
  rm --recursive --force $dir
}

export def install [system: record, --bin-dir: path, --dry-run]: nothing -> nothing {
  packages install $system --bin-dir $bin_dir --group k8s-tools --dry-run=$dry_run

  log step $"kubectl plugins through krew \(($PLUGINS | str join ', '))"
  let krew = (krew-path $system.family)
  # Downloads from here on warn rather than abort, for the reason the Claude
  # Code step gives: an opt-in extra is not worth the rest of the run.
  if ($krew | path exists) {
    log skipped $"krew already installed at ($krew)"
  } else {
    let ok = (try { bootstrap --dry-run=$dry_run; true } catch {|e|
      log warn $"could not install krew \(($e.msg)) -- rerun with `--only k8s-tools` later"
      false
    })
    if not $ok { return }
  }

  let installed = (if ($krew | path exists) { installed-plugins (do { ^$krew list } | complete).stdout } else { [] })
  let plugins = (krew-plugins $system.family)
  let done = (try {
    for cmd in (krew-commands $krew $plugins $installed) {
      # Once more before giving up. On Windows krew's move of a fresh
      # download into ~/.krew/store has failed with "Access is denied" and
      # then worked a moment later -- most likely a virus scan holding the
      # new executable open.
      try { run-krew $cmd --dry-run=$dry_run } catch { run-krew $cmd --dry-run=$dry_run }
    }
    true
  } catch {
    log warn "the kubectl plugins did not all install -- rerun with `--only k8s-tools` later"
    false
  })

  if $system.family == "windows" {
    for row in ($WINGET_PLUGINS | transpose plugin id) {
      let argv = (distro winget-list-command $row.id)
      if (do { ^($argv | first) ...($argv | slice 1..) } | complete).exit_code == 0 {
        log skipped $"($row.id) already installed"
        continue
      }
      try {
        log shell (distro winget-install-command $row.id) --dry-run=$dry_run
      } catch {
        log warn $"($row.id) did not install -- rerun with `--only k8s-tools` later"
      }
    }
  }

  if $done and not $dry_run { log ok "plugins ready; open a new shell for ~/.krew/bin on PATH" }
}
