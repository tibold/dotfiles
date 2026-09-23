# macOS, via Homebrew.
#
# This overlay differs from the Linux ones in a way worth stating up front:
# macOS is the only target here that is a *workstation*. The Linux boxes are
# mostly reached over ssh, which is why they omit fonts and lean on upstream
# release binaries. Here the terminal is on this machine, so the font is
# installed, and Homebrew packages every tool in common.nu -- nothing falls
# back to a downloaded binary, and tests/unit/packages.nu asserts that.
#
# The other difference is that a lot of this list is already in the base
# system. Those are in PROVIDED rather than OMITTED: "macOS already has this"
# and "we are doing without this" are not the same statement, and reading the
# first as the second would send someone hunting for a missing tool that is
# sitting on their PATH.

# logical name -> what Homebrew calls it.
#   string  rename
#   list    expands to several formulae
#   null    not available as a formula; must be accounted for in CASKS,
#           PROVIDED or OMITTED
export const OVERRIDES = {
  # -- database clients (packages/common.nu DATABASES) --
  # libpq is the client library and tools without the server. It is keg-only
  # (it would conflict with the postgresql formula), so home/.zshrc puts its
  # bin directory on PATH when it is installed.
  postgresql-client: "libpq"
  sqlite: null

  nodejs: "node"

  # Same as Fedora and Debian: cdrtools is not packaged, xorriso does the job
  # and ships an mkisofs-compatible front end.
  mkisofs: "xorriso"

  # Not a second formula: Homebrew's nushell build installs every nu_plugin_*
  # crate alongside `nu` from the same source tree, so asking for the shell
  # already puts the plugin executables in the prefix. resolve() de-duplicates
  # the repeated name. Kept honest by tests/unit/plugins.nu.
  nushell-plugins: "nushell"

  # -- in the base system; see PROVIDED for why each one --
  zsh: null
  curl: null
  tar: null
  gcc: null
  make: null
  diffutils: null
  npm: null
  terminfo-extra: null

  # -- genuinely absent here; see OMITTED --
  neovim-python: null
  podman-docker: null
}

# Homebrew's other half. Casks are applications and fonts rather than
# command-line packages, and they install with `brew install --cask`, so they
# are a separate list rather than an override -- see lib/distro.nu.
#
# Written the same way as OVERRIDES: logical name -> cask token. A tool that
# appears here is accounted for, so it does not need an entry anywhere else.
export const CASKS = {
  # 0xProto, picked by eye in Rio over Meslo (the Oh My Zsh default this list
  # started with), which read poorly at terminal sizes. The same family is in
  # FONTS in packages/windows.nu and in Rio's config; tests/unit/configs.nu
  # fails when the three disagree. Any other Nerd Font is a one-word change
  # here and there.
  #
  # Installing a font is only useful on a machine someone is sitting at, which
  # is why the Linux overlays omit this and this one does not.
  nerd-fonts: "font-0xproto-nerd-font"

  # Microsoft's own macOS package, which the cask wraps. It carries its own
  # .NET runtime, so it needs no SDK -- the same reason the Linux side takes
  # the upstream tarball rather than a dotnet global tool.
  #
  # It is a .pkg rather than a plain binary, so unlike the font this one asks
  # for a password during the install.
  git-credential-manager: "git-credential-manager"
}

export const EXTRA = []

# Already in the base system.
#
# Distinct from OMITTED: the tool is present and working, it just does not come
# from the package manager. Installing Homebrew's version would mean a second
# copy that either shadows the system one or, for the keg-only formulae, is not
# even on PATH -- more to maintain, for a tool we already have.
export const PROVIDED = {
  sqlite: "macOS ships sqlite3 at /usr/bin/sqlite3"
  zsh: "macOS ships zsh and already uses it as the login shell; Homebrew's would additionally have to be added to /etc/shells before it could be one"
  curl: "the system curl is current, and Homebrew's is keg-only -- installing it would not even put it on PATH"
  tar: "bsdtar is /usr/bin/tar; Homebrew's GNU tar installs as gtar, and nothing here passes a GNU-only flag"
  gcc: "the Command Line Tools provide clang as cc and gcc; Homebrew's gcc is the actual GNU compiler, which is a much larger thing than this list means by it"
  make: "the Command Line Tools provide make; Homebrew's installs as gmake to avoid shadowing it"
  diffutils: "BSD diff is in the base system, and diffs here are rendered by delta, which does its own"
  npm: "bundled with the node formula rather than packaged separately"
  terminfo-extra: "macOS ships a terminfo database that already carries tmux-256color, which is the entry .tmux.conf asks for"
}

# Unavailable here, and we are choosing to do without rather than fetch it.
export const OMITTED = {
  neovim-python: "no pynvim formula, and Homebrew's python is PEP 668 managed so pip cannot add one to it; neovim runs fine without the python provider, it just cannot host python plugins"
  podman-docker: "no such formula -- podman on macOS drives a Linux VM and ships no docker shim. home/.zshrc aliases docker to podman when no real docker is installed, which is the part of that package worth having; `podman-mac-helper install` is the fuller answer if a tool needs the socket"
}

# Nothing to remove.
#
# The Linux overlays list powerline and starship because this repo installed
# them there and no longer wants them. It has never installed anything on
# macOS, so there is nothing here it has any business uninstalling -- and
# "looks unused" is not a reason, on any platform.
export const REMOVED = []
