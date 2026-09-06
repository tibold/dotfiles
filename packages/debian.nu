# Debian and Ubuntu, via apt-get.
#
# This is the "machines where I don't choose the OS" target, so it leans on
# upstream releases more than the others: Debian's archive is conservative and
# several of these tools are either absent or too old to be worth having.
export const OVERRIDES = {
  terminfo-extra: "ncurses-term"

  mkisofs: "xorriso"
  neovim-python: "python3-neovim"

  nerd-fonts: null

  # gh needs GitHub's own apt repo; the rest are not packaged at all. They all
  # come from upstream releases instead.
  gh: null
  lazygit: null
  gitleaks: null
  nushell: null
  nushell-plugins: null
}

export const EXTRA = [
  ca-certificates
  fontconfig
]

export const REMOVED = [
  powerline
  fonts-powerline
]

# Unavailable here on purpose, rather than fetched from upstream.
export const OMITTED = {
  nerd-fonts: "not in the archive, and a Debian box is usually reached over ssh -- the glyphs come from the terminal on the machine you are sitting at, not this one"
}
