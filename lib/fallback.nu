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

use log.nu

# Release assets, by tool and CPU architecture.
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

# Fetch one tool into bin-dir. Assumes the archive is a .tar.gz somewhere
# inside which the binaries live; every source above is packaged that way.
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

  if $dry_run {
    log info $"would fetch ($tool) from ($source.repo) into ($bin_dir)"
    return
  }

  let asset = (resolve-asset $tool --arch (arch))
  log info $"($tool) ($asset.version) <- ($asset.name)"

  let workdir = (mktemp --directory --tmpdir $"dotfiles-($tool)-XXXXXX")
  let archive = ($workdir | path join $asset.name)

  http get $asset.url | save --raw --force $archive
  ^tar --extract --gzip --file $archive --directory $workdir

  mkdir $bin_dir
  for binary in $source.binaries {
    let found = (glob ($workdir | path join "**" $binary) --no-dir)
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
