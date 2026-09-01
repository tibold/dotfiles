# Fedora (and RHEL derivatives), via dnf.
export const OVERRIDES = {
  # cdrtools' mkisofs is not shipped; xorriso provides the same job and an
  # mkisofs-compatible front end.
  terminfo-extra: "ncurses-term"

  mkisofs: "xorriso"

  pipx: "pipx"
  neovim-python: "python3-neovim"

  # Not in Fedora's repos under any name the container test could find.
  nerd-fonts: null

  # Not packaged either, despite being in EPEL for RHEL.
  lazygit: null

  # Fedora does package nushell, but well behind: 0.99 at the time of writing,
  # which cannot parse the scripts in this repo. bootstrap.sh probes whatever
  # it finds and falls back to the upstream release, so nothing is asked of dnf
  # here.
  nushell: null
}

export const EXTRA = []

export const OMITTED = {
  nerd-fonts: "not packaged, and a Fedora box here is a server reached over ssh -- the glyphs come from the terminal you are sitting at, not this one"
}

export const REMOVED = [
  powerline
  powerline-fonts
  tmux-powerline
]
