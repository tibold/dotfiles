# Tools that a distro does not package, fetched from their upstream releases.
#
# This is the escape hatch that makes Leap and Ubuntu viable targets. Both are
# conservative archives: Leap tracks SLE and Ubuntu freezes, so the newer Rust
# and Go tools here are either absent or too old. Rather than bolting a
# third-party repository onto the system for each one -- which is a much bigger
# commitment than it looks, since it stays and affects every future upgrade --
# we drop a single static binary into ~/.local/bin.
#
# The trade is explicit: these binaries do not get security updates from the
# distro, and nothing here re-fetches one that is already on PATH. To update
# one, delete it from ~/.local/bin and run `install.nu --only packages`, which
# fetches whatever upstream calls latest. That is the whole maintenance story.
#
# Every asset below is a Linux build, and this is a Linux-only mechanism on
# purpose. macOS has no use for it -- Homebrew carries every tool in
# common.nu, so packages/macos.nu nulls nothing that is not either in the base
# system or deliberately dropped -- and the upstream projects do not line up
# for it anyway: delta publishes no x86_64 macOS build, and gh ships macOS as a
# .zip, which `install` below does not unpack. Rather than grow a second set of
# asset tables for a path that should never be taken, `install` refuses to run
# anywhere but Linux, so a future override that nulls a formula fails loudly
# instead of putting an ELF binary in ~/.local/bin.

use log.nu

# Release assets, by tool and CPU architecture. Linux only -- see above.
#
# `{version}` is the release tag with any leading "v" removed, which is what
# every one of these projects puts in its filenames even when the tag itself is
# prefixed. The architecture tokens are spelled out per repo rather than
# derived, because projects disagree about them -- Go projects say amd64/arm64,
# Rust projects say x86_64/aarch64 -- and a template clever enough to hide that
# would be harder to check than the five lines it saved.
export const SOURCES = {
  nushell: {
    repo: "nushell/nushell"
    assets: {
      x86_64: "nu-{version}-x86_64-unknown-linux-gnu.tar.gz"
      aarch64: "nu-{version}-aarch64-unknown-linux-gnu.tar.gz"
    }
    binaries: ["nu"]
  }
  # The same archive as nushell -- upstream ships every plugin alongside the
  # shell -- picked over for the plugin executables instead. A second entry
  # rather than more binaries on the first, so that a machine bootstrap.sh
  # already gave a `nu` does not refetch it to get the plugins. Kept in step
  # with NUSHELL_PLUGINS in packages/common.nu by tests/unit/plugins.nu.
  nushell-plugins: {
    repo: "nushell/nushell"
    assets: {
      x86_64: "nu-{version}-x86_64-unknown-linux-gnu.tar.gz"
      aarch64: "nu-{version}-aarch64-unknown-linux-gnu.tar.gz"
    }
    binaries: ["nu_plugin_formats" "nu_plugin_query" "nu_plugin_inc"]
  }
  lazygit: {
    repo: "jesseduffield/lazygit"
    assets: {
      x86_64: "lazygit_{version}_linux_x86_64.tar.gz"
      aarch64: "lazygit_{version}_linux_arm64.tar.gz"
    }
    binaries: ["lazygit"]
  }
  gitleaks: {
    repo: "gitleaks/gitleaks"
    assets: {
      x86_64: "gitleaks_{version}_linux_x64.tar.gz"
      aarch64: "gitleaks_{version}_linux_arm64.tar.gz"
    }
    binaries: ["gitleaks"]
  }
  git-delta: {
    repo: "dandavison/delta"
    assets: {
      x86_64: "delta-{version}-x86_64-unknown-linux-gnu.tar.gz"
      aarch64: "delta-{version}-aarch64-unknown-linux-gnu.tar.gz"
    }
    # The binary is called delta; only the package is called git-delta.
    binaries: ["delta"]
  }
  gh: {
    repo: "cli/cli"
    assets: {
      x86_64: "gh_{version}_linux_amd64.tar.gz"
      aarch64: "gh_{version}_linux_arm64.tar.gz"
    }
    binaries: ["gh"]
  }
  # No distribution packages this, so every Linux machine takes it from here.
  #
  # The usual instruction is `dotnet tool install -g git-credential-manager`,
  # which is not used: it makes a credential helper depend on an SDK, and the
  # machines most likely to want it are servers with no other use for one.
  # These archives are self-contained builds -- their runtimeconfig.json
  # declares `includedFrameworks` rather than a framework reference, meaning
  # the .NET runtime is inside the download. Confirmed by running one with an
  # empty environment and nothing but /usr/bin on PATH.
  #
  # "directory" because the archive is the binary plus libSkiaSharp.so and
  # libHarfBuzzSharp.so, which it loads from beside itself.
  git-credential-manager: {
    repo: "git-ecosystem/git-credential-manager"
    assets: {
      x86_64: "gcm-linux-x64-{version}.tar.gz"
      aarch64: "gcm-linux-arm64-{version}.tar.gz"
    }
    binaries: ["git-credential-manager"]
    layout: "directory"
  }
}

export def arch []: nothing -> string {
  $nu.os-info.arch
}

# The tag of a repository's newest release, read from the redirect that
# github.com/OWNER/REPO/releases/latest performs.
#
# Deliberately not api.github.com. The API is the obvious way to ask and the
# wrong one here: it allows 60 unauthenticated calls an hour per IP address,
# which a few container-test runs exhaust, and it then answers 403 in a way
# that reads like "this release does not exist". The redirect is ordinary web
# traffic and is not rationed like that.
export def latest-tag [repo: string]: nothing -> string {
  let response = (http get --full --redirect-mode manual $"https://github.com/($repo)/releases/latest")

  let location = ($response.headers.response
    | where {|h| ($h.name | str lowercase) == "location" }
    | get value
    | first)

  if ($location | is-empty) {
    error make { msg: $"($repo) did not redirect to a release -- has it ever published one?" }
  }

  $location | split row "/tag/" | last
}

# Where to get one tool, without asking GitHub's API for anything.
export def resolve-asset [tool: string, --arch: string]: nothing -> record {
  let source = ($SOURCES | get --optional $tool)
  if $source == null {
    error make { msg: $"no upstream release is configured for '($tool)'" }
  }

  let template = ($source.assets | get --optional $arch)
  if $template == null {
    error make { msg: $"($tool) has no ($arch) release asset configured" }
  }

  let tag = (latest-tag $source.repo)
  # Tags are inconsistently prefixed; filenames never are.
  let version = ($tag | str replace --regex '^v' '')
  let name = ($template | str replace --all "{version}" $version)

  {
    tool: $tool
    version: $tag
    name: $name
    url: $"https://github.com/($source.repo)/releases/download/($tag)/($name)"
    binaries: $source.binaries
  }
}

# How a tool's archive turns into an installed tool.
#
#   binaries   the named executables are lifted out and the rest discarded.
#              True of every Go and Rust tool here: the archive is the binary,
#              a licence and a README.
#   directory  the whole archive is kept together and the binaries are linked
#              to from bin-dir, because the executable does not work alone.
#
# The distinction is not cosmetic. git-credential-manager's Linux archive is
# the binary plus libSkiaSharp.so and libHarfBuzzSharp.so, which it loads from
# its own directory; lifting out the binary alone produces a command that runs
# until the moment it needs to draw something and then dies.
export def layout-of [tool: string]: nothing -> string {
  $SOURCES | get --optional $tool | default {} | get --optional layout | default "binaries"
}

# Where a directory-layout tool lives: beside bin-dir rather than in it.
#
# ~/.local/bin is a directory of commands, and unpacking two hundred files of
# .NET runtime into it would make it something else. ~/.local/share is where
# that belongs, with a link back.
export def share-dir [tool: string, --bin-dir: path]: nothing -> path {
  $bin_dir | path dirname | path join "share" $tool
}

# Install a tool that has to stay in one piece.
#
# Exported so a test can drive it against a fabricated payload: it is the only
# part of this file that deletes a directory, and the path it deletes is derived
# rather than given.
export def install-directory [
  tool: string
  asset: record
  --payload: path      # where the archive was unpacked
  --bin-dir: path
]: nothing -> nothing {
  # Archives disagree about whether they have a top-level directory. Both
  # shapes are accepted rather than asserted about, because which one a project
  # ships is not a decision this repo gets to make, and it can change between
  # releases without anything saying so.
  let entries = (ls --all $payload)
  let root = (if (($entries | length) == 1) and (($entries | first | get type) == "dir") {
    $entries | first | get name
  } else {
    $payload
  })

  let dest = (share-dir $tool --bin-dir $bin_dir)

  # Replaced wholesale rather than merged. A half-old, half-new set of runtime
  # files is a worse state than either version on its own, and the directory
  # holds nothing but what a previous run of this put there.
  rm --recursive --force $dest
  mkdir $dest
  ^cp -R $"($root)/." $dest
  log ok $"($tool) -> ($dest)"

  mkdir $bin_dir
  for binary in $asset.binaries {
    let target = ($dest | path join $binary)
    if not ($target | path exists) {
      error make { msg: $"($asset.name) does not contain a '($binary)' binary" }
    }
    ^chmod +x $target
    let link = ($bin_dir | path join $binary)
    # -n so an existing link to a directory is replaced rather than followed
    # into, the same flags the dotfile links use.
    ^ln -sfn $target $link
    log ok $"($binary) -> ($link)"
  }
}

# Fetch one tool into bin-dir. Every source above is a .tar.gz; what happens to
# its contents afterwards depends on the tool's layout, above.
export def install [
  tool: string
  --bin-dir: path
  --dry-run
  --force        # refetch even when the binary is already on PATH
]: nothing -> nothing {
  let source = ($SOURCES | get --optional $tool)
  if $source == null {
    log warn $"($tool) is unavailable here and has no upstream release configured -- skipping"
    return
  }

  # On PATH, or already in bin-dir: bin-dir is where this puts things, and the
  # session running the install often does not have it on PATH yet.
  let present = ($source.binaries | all {|b|
    (which $b | is-not-empty) or ($bin_dir | path join $b | path exists)
  })
  if $present and (not $force) {
    log skipped $"($tool) already on PATH"
    return
  }

  # Checked here rather than at the top of the file, so that a tool which is
  # already present is still simply skipped: this is about what would be
  # downloaded, not about where the function was called from.
  if $nu.os-info.name != "linux" {
    error make {
      msg: $"($tool) resolved to an upstream release, but every asset in lib/fallback.nu is a Linux build -- on ($nu.os-info.name) it has to come from the package manager, or be listed in that overlay's PROVIDED or OMITTED"
    }
  }

  if $dry_run {
    log info $"would fetch ($tool) from ($source.repo) into ($bin_dir)"
    return
  }

  let asset = (resolve-asset $tool --arch (arch))
  log info $"($tool) ($asset.version) <- ($asset.name)"

  let workdir = (mktemp --directory --tmpdir $"dotfiles-($tool)-XXXXXX")
  let archive = ($workdir | path join $asset.name)

  # Unpacked into its own subdirectory rather than alongside the archive, so
  # that "everything the archive contained" is a directory listing rather than
  # a listing minus one file we happen to have put there.
  let payload = ($workdir | path join "payload")
  mkdir $payload

  http get $asset.url | save --raw --force $archive
  ^tar --extract --gzip --file $archive --directory $payload

  if (layout-of $tool) == "directory" {
    install-directory $tool $asset --payload $payload --bin-dir $bin_dir
    rm --recursive --force $workdir
    return
  }

  mkdir $bin_dir
  for binary in $source.binaries {
    let found = (glob ($payload | path join "**" $binary) --no-dir)
    if ($found | is-empty) {
      rm --recursive --force $workdir
      error make { msg: $"($asset.name) does not contain a '($binary)' binary" }
    }
    let dest = ($bin_dir | path join $binary)
    cp --force ($found | first) $dest
    ^chmod +x $dest
    log ok $"($binary) -> ($dest)"
  }

  rm --recursive --force $workdir
}

export def install-all [
  tools: list<string>
  --bin-dir: path
  --dry-run
  --force
]: nothing -> nothing {
  for tool in $tools {
    install $tool --bin-dir $bin_dir --dry-run=$dry_run --force=$force
  }
}
