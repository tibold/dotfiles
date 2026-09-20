# Fedora (and RHEL derivatives), via dnf.
export const OVERRIDES = {

  # Not packaged by any distribution. Comes from the upstream release instead,
  # which is a self-contained build needing no dotnet -- see lib/fallback.nu.
  git-credential-manager: null
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
  nushell-plugins: null
}

export const EXTRA = [
  # git-credential-manager's runtime dependency, and the one thing its upstream
  # archive does not carry.
  #
  # That build bundles its own .NET runtime but still calls out to the system
  # ICU for globalization, and .NET does not degrade when it is missing -- it
  # aborts:
  #
  #   Couldn't find a valid ICU package installed on the system.
  #   ... core dumped with SIGABRT (6)
  #
  # So the helper installs, lands on PATH, and dies the first time git asks it
  # for a credential. Microsoft's own .deb declares no dependencies at all, so
  # there is nothing upstream to inherit this from.
  #
  # "libicu" unversioned on purpose: it is a real package name on Fedora, and
  # on openSUSE zypper resolves it as a capability to whichever libicuNN is
  # current. Neither needs revisiting when ICU's soname moves.
  libicu
]

export const OMITTED = {
  nerd-fonts: "not packaged, and a Fedora box here is a server reached over ssh -- the glyphs come from the terminal you are sitting at, not this one"
}

export const REMOVED = [
  powerline
  powerline-fonts
  tmux-powerline
]
