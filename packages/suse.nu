# openSUSE (Tumbleweed and Leap), via zypper.
#
# openSUSE splits completions and editor integration into their own packages
# more aggressively than the others, which is why several logical tools expand
# to a list here rather than a single name.

# logical name -> what zypper calls it.
#   string  rename
#   list    expands to several packages
#   null    not available; lib/fallback.nu fetches it from upstream instead
export const OVERRIDES = {
  # -- database clients (packages/common.nu DATABASES) --
  # `postgresql` is the client; the server is postgresql-server.
  postgresql-client: "postgresql"
  sqlite: "sqlite3"


  # Not packaged by any distribution. Comes from the upstream release instead,
  # which is a self-contained build needing no dotnet -- see lib/fallback.nu.
  git-credential-manager: null
  terminfo-extra: "terminfo"

  nodejs: "nodejs-default"
  npm: "npm-default"

  # Versioned by design: openSUSE has no unversioned python3-pipx, only
  # pythonNNN-pipx. Bump this when the distro's default python moves -- the
  # container test fails loudly when it goes stale, which is the point.
  pipx: "python313-pipx"

  nerd-fonts: "nerdfonts-symbolsonly-fonts"

  # Versioned for the same reason as pipx above.
  neovim-python: "python313-neovim"

  fzf: ["fzf" "fzf-tmux" "fzf-zsh-integration" "vim-fzf"]
  ripgrep: ["ripgrep" "ripgrep-bash-completion" "ripgrep-zsh-completion"]

  # One package per plugin, built from the same source as the nushell package
  # so the versions always agree. Kept in step with NUSHELL_PLUGINS in
  # common.nu by tests/unit/plugins.nu.
  nushell-plugins: [
    nushell-plugin_formats
    nushell-plugin_query
    nushell-plugin_inc
  ]
}

export const EXTRA = [
  helm-zsh-completion

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

# Packages this repo used to install and no longer wants.
#
# Only things *we* put there, and only where something has clearly replaced
# them. powerline's prompt is now the Oh My Zsh theme and its status line is
# tmux's own formats; its font package is superseded by Nerd Fonts, which carry
# the same glyph range. starship was briefly used for the prompt and dropped --
# it only pays for itself across several interactive shells, and there is one.
#
# Not listed, deliberately: python3-* libraries, anything that came from the
# distro's own patterns, and anything a person might reasonably still want.
export const REMOVED = [
  powerline
  powerline-docs
  powerline-fonts
  tmux-powerline
  vim-plugin-powerline
  starship
]

export const OMITTED = {}
