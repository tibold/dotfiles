#!/bin/sh
#
# Get nushell onto this machine, then hand over to install.nu.
#
#   ./bootstrap.sh              bootstrap, then run the full install
#   ./bootstrap.sh --dry-run    bootstrap, then show what install.nu would do
#
# Every argument is passed through to install.nu.
#
# This is the one script here that cannot be written in nushell, so it is
# deliberately the smallest thing that will do: POSIX sh, no bashisms, no
# assumptions beyond a package manager and curl. Everything else -- package
# name mapping, linking, the per-distro logic -- lives in the nushell side
# where it can be read and tested.

set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOCAL_BIN="$HOME/.local/bin"

log() { printf '\033[36m==>\033[0m %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
die() { printf '\033[31mbootstrap:\033[0m %s\n' "$1" >&2; exit 1; }

# --- privilege ----------------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  die "not root and sudo is not installed -- cannot install packages"
fi

# --- which distribution -------------------------------------------------------

[ -r /etc/os-release ] || die "/etc/os-release is missing -- cannot identify this system"

# shellcheck disable=SC1091
. /etc/os-release
ID="${ID:-unknown}"
ID_LIKE="${ID_LIKE:-}"

# Mirrors lib/distro.nu's family-of. Kept in step by tests/unit/distro.nu,
# which asserts the same inputs land in the same family.
family=unknown
for name in $ID $ID_LIKE; do
  case "$name" in
    opensuse|opensuse-leap|opensuse-tumbleweed|suse|sles|sled) family=suse; break ;;
    fedora|rhel|centos|rocky|almalinux) family=fedora; break ;;
    debian|ubuntu) family=debian; break ;;
  esac
done

[ "$family" != unknown ] || die "$PRETTY_NAME is not a supported distribution"

log "$PRETTY_NAME (family $family)"

# --- the handful of packages needed to get any further ------------------------

# curl and tar fetch and unpack nushell; git is needed before install.nu can do
# anything useful. Everything else is install.nu's job.
install_base() {
  case "$family" in
    suse)
      $SUDO zypper --non-interactive install --auto-agree-with-licenses \
        curl tar gzip git ca-certificates
      ;;
    fedora)
      $SUDO dnf install -y curl tar gzip git ca-certificates
      ;;
    debian)
      # apt genuinely needs this: a fresh image's package lists are stale
      # enough that packages which exist will not be found.
      $SUDO apt-get update
      $SUDO apt-get install -y --no-install-recommends \
        curl tar gzip git ca-certificates
      ;;
  esac
}

log "Base packages"
install_base

# --- nushell ------------------------------------------------------------------

# Put ~/.local/bin ahead of the system path before any of the checks below, so
# that a newer nu installed here wins over an older packaged one.
PATH="$LOCAL_BIN:$PATH"
export PATH

# Can this nushell actually run these scripts?
#
# Asked directly rather than by comparing version numbers. A version floor is a
# proxy for the real question, and one that has to be revised by hand every
# time the scripts use something newer. So is a hand-written probe of "the
# newest syntax we rely on": it drifts the moment a script uses something the
# probe does not, and it did -- it let through a release the test runner could
# not parse.
#
# nu-check parses install.nu and, because nushell resolves `use` at parse time,
# every module it imports. That is the real question, asked of the real files,
# and it needs no maintenance when the scripts change.
#
# It is not hypothetical: Fedora packages nushell 0.99, which installs happily
# and then cannot parse lib/distro.nu.
nu_is_usable() {
  candidate="$1"
  [ -n "$candidate" ] || return 1

  "$candidate" --no-config-file -c \
    "if (nu-check '$REPO_DIR/install.nu') { exit 0 } else { exit 1 }" \
    >/dev/null 2>&1
}

# Try the distro first, then fall back to the upstream release.
#
# Deliberately not a table of which distro packages nushell: what matters is
# whether the result works, and asking is self-correcting. The day Fedora's
# package catches up, this starts using it with no edit here.
install_nushell_from_release() {
  case "$(uname -m)" in
    x86_64) target="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) target="aarch64-unknown-linux-gnu" ;;
    *) die "no nushell release build for $(uname -m)" ;;
  esac

  info "fetching the latest nushell release for $target"

  # The version comes from the redirect that github.com/.../releases/latest
  # performs, not from api.github.com.
  #
  # The API is the obvious way to do this and the wrong one here: it allows 60
  # unauthenticated calls an hour per IP, which a handful of container test
  # runs exhausts, and it then fails in a way that looks like "there is no such
  # release". The redirect is plain web traffic and is not rationed like that.
  tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/nushell/nushell/releases/latest" \
    | sed 's#.*/tag/##')

  [ -n "$tag" ] || die "could not work out the latest nushell version"

  url="https://github.com/nushell/nushell/releases/download/${tag}/nu-${tag}-${target}.tar.gz"
  info "nushell ${tag}"

  workdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  curl -fsSL "$url" -o "$workdir/nu.tar.gz"
  tar -xzf "$workdir/nu.tar.gz" -C "$workdir"

  found=$(find "$workdir" -type f -name nu -perm -u+x | head -n 1)
  [ -n "$found" ] || die "the nushell archive did not contain a nu binary"

  mkdir -p "$LOCAL_BIN"
  cp "$found" "$LOCAL_BIN/nu"
  chmod +x "$LOCAL_BIN/nu"
  info "installed nu to $LOCAL_BIN/nu"
}

log "Nushell"

# Everything below refers to the interpreter by its full path in $NU, never by
# looking up "nu" again.
#
# The shell caches the location of a command the first time it runs one, and
# the probe above runs nu. On Fedora that cached /usr/bin/nu, so the newer
# binary this script then installed into ~/.local/bin was ignored by every
# later lookup -- including the final check, which reported the old version it
# had just replaced. Holding the path removes the question.
NU=$(command -v nu 2>/dev/null || true)

if nu_is_usable "$NU"; then
  info "already installed: $("$NU" --version)"
else
  if [ -z "$NU" ]; then
    case "$family" in
      suse) $SUDO zypper --non-interactive install nushell || true ;;
      fedora) $SUDO dnf install -y nushell || true ;;
      debian) $SUDO apt-get install -y nushell || true ;;
    esac
    hash -r 2>/dev/null || true
    NU=$(command -v nu 2>/dev/null || true)
  fi

  if nu_is_usable "$NU"; then
    info "installed from the distribution: $("$NU" --version)"
  else
    if [ -n "$NU" ]; then
      info "the packaged nushell ($("$NU" --version)) is too old for these scripts"
    else
      info "not packaged for this distribution"
    fi
    info "using the upstream release instead"
    install_nushell_from_release
    NU="$LOCAL_BIN/nu"
  fi
fi

[ -x "$NU" ] || die "nushell is still not installed -- cannot continue"
nu_is_usable "$NU" || die "the nushell at $NU ($("$NU" --version)) cannot run these scripts"

# --- hand over ----------------------------------------------------------------

log "Handing over to install.nu"
exec "$NU" "$REPO_DIR/install.nu" "$@"
