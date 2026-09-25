# Rust, through rustup, for the current user. Opt-in: see OPT_IN in lib/steps.nu.
#
# rustup rather than any distribution's rustc: every distribution here lags
# the six-weekly releases, and rustup is what cargo, rust-analyzer and the
# ecosystem's docs all assume. Windows takes it from winget; everywhere else
# from the official installer script, told to leave the shell profiles alone
# -- they are this repo's files, and ~/.profile and ~/.zshrc already put
# ~/.cargo/bin on PATH.
#
# Past rustup itself, the toolchain step is the same everywhere: stable, plus
# the components an editor needs. rust-analyzer is the language server, and it
# reads the standard library's source from rust-src.
#
# The linker comes from elsewhere. Linux has gcc from the packages step and
# macOS the Command Line Tools; Windows needs MSVC's link.exe and the Windows
# SDK, which only Visual Studio supplies -- see ensure-msvc below.

use ../lib/log.nu
use ../lib/distro.nu

export const COMPONENTS = ["rust-analyzer" "rust-src" "clippy" "rustfmt"]

export const BUILD_TOOLS = "Microsoft.VisualStudio.BuildTools"
# What rustc's msvc target links with: the x64 compiler and linker.
export const VC_COMPONENT = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"

# --override replaces winget's whole installer command line, so it repeats the
# unattended switches. --includeRecommended is what brings the Windows SDK
# along with the C++ workload; without it there is a linker and no libraries.
export def build-tools-command []: nothing -> list<string> {
  (distro winget-install-command $BUILD_TOOLS) ++ [
    "--override" "--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  ]
}

export def installer-command [family: string]: nothing -> list<string> {
  if $family == "windows" {
    distro winget-install-command "Rustlang.Rustup"
  } else {
    # --default-toolchain none: the toolchain is installed by the common step
    # below, the same way whether rustup was just installed or was already here.
    ["sh" "-c" "set -e; script=$(curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs); printf '%s' \"$script\" | sh -s -- -y --no-modify-path --default-toolchain none"]
  }
}

# Installing stable when it is already there updates it, so a re-run is also
# how the toolchain gets upgraded. The default is set only when there is none:
# a machine that defaults to nightly did that on purpose.
export def toolchain-commands [rustup: string, has_default: bool]: nothing -> list<list<string>> {
  [
    [$rustup "toolchain" "install" "stable" "--profile" "default"]
    ([$rustup "component" "add" "--toolchain" "stable"] ++ $COMPONENTS)
  ] ++ (if $has_default { [] } else { [[$rustup "default" "stable"]] })
}

# Where rustup puts itself, which a process started before the install cannot
# find on its PATH.
export def cargo-bin []: nothing -> path {
  let home = ($env.CARGO_HOME? | default ($nu.home-dir | path join ".cargo"))
  $home | path join "bin"
}

def find-rustup [family: string]: nothing -> any {
  let found = (which rustup)
  if ($found | is-not-empty) { return ($found | first | get path) }
  let exe = (if $family == "windows" { "rustup.exe" } else { "rustup" })
  let candidate = (cargo-bin | path join $exe)
  if ($candidate | path exists) { $candidate } else { null }
}

# Any Visual Studio -- Community, Professional, Build Tools, any year -- that
# already has the C++ tools will do, so this asks vswhere rather than winget,
# which only knows about the one product id.
def has-msvc []: nothing -> bool {
  let x86 = ($env | get --optional "ProgramFiles(x86)" | default 'C:\Program Files (x86)')
  let vswhere = ($x86 | path join "Microsoft Visual Studio" "Installer" "vswhere.exe")
  if not ($vswhere | path exists) { return false }
  let found = (do { ^$vswhere -latest -products "*" -requires $VC_COMPONENT -property installationPath } | complete)
  $found.exit_code == 0 and ($found.stdout | str trim | is-not-empty)
}

def ensure-msvc [--dry-run]: nothing -> nothing {
  if (has-msvc) {
    log skipped "the MSVC C++ tools are already installed"
    return
  }
  # Several GB, and the installer asks for elevation. A failure leaves rustup
  # installed and cargo unable to link, which is worth a warning, not the run.
  try {
    log shell (build-tools-command) --dry-run=$dry_run
  } catch {
    log warn $"the Visual Studio Build Tools did not install -- cargo cannot link without them; rerun with `--only rust`"
  }
}

export def install [family: string, --dry-run]: nothing -> nothing {
  log step "Rust"
  if $family == "windows" { ensure-msvc --dry-run=$dry_run }

  let found = (find-rustup $family)
  if ($found | is-empty) {
    # Warns rather than aborts, as the Claude Code step does and for its reason.
    let installed = (try {
      log shell (installer-command $family) --dry-run=$dry_run
      true
    } catch {|e|
      log warn $"could not install rustup \(($e.msg)) -- rerun with `--only rust` later"
      false
    })
    if not $installed { return }
  } else {
    log skipped $"rustup already installed at ($found)"
  }
  let exe = (if $family == "windows" { "rustup.exe" } else { "rustup" })
  let rustup = ($found | default (cargo-bin | path join $exe))

  let has_default = (not $dry_run) and ((do { ^$rustup default } | complete).exit_code == 0)
  try {
    for cmd in (toolchain-commands $rustup $has_default) { log shell $cmd --dry-run=$dry_run }
    if not $dry_run { log ok "stable toolchain ready; open a new shell for ~/.cargo/bin on PATH" }
  } catch {
    log warn "the stable toolchain did not install -- rerun with `--only rust` later"
  }
}
