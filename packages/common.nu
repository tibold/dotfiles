# The tools this environment is made of, under one logical name each.
#
# These are NOT package names. They are the names this repo uses to talk about
# a tool; each distro overlay in this directory maps them to whatever that
# distro actually calls the thing, splits one into several, or marks it
# unavailable. Adding a tool is a one-line change here, plus an override only
# where the obvious name is wrong.
export const PACKAGES = [
  # -- Core shell environment --
  zsh
  tmux
  neovim
  htop

  # -- Fetching and building; also what bootstrap and the omz installer need --
  git
  curl
  tar
  gcc
  make
  diffutils

  # -- Git tooling --
  gh          # GitHub CLI; doubles as git's credential helper
  lazygit
  git-delta   # lazygit and .gitconfig both page diffs through it
  gitleaks    # backs the pre-commit secret scan, see githooks/

  # -- Search and navigation --
  ripgrep
  fzf
  jq

  # The fuller terminfo database. tmux names an entry (tmux-256color) that the
  # minimal database does not carry, and a missing entry stops every login
  # shell inside tmux to ask what terminal you are on.
  terminfo-extra

  # -- Fonts --
  #
  # No prompt package: Oh My Zsh draws the prompt, and zsh is the only shell
  # anyone types into here. powerline used to be in this list and is gone --
  # a python daemon with a per-shell integration script, replaced by the omz
  # theme for the prompt and by tmux's own formats for the status line.
  #
  # Nerd Fonts supersede powerline-fonts outright: they carry the powerline
  # glyph range plus everything else.
  nerd-fonts

  # -- Languages and runtimes --
  nodejs
  npm
  pipx

  # neovim's python provider. Taken from the distro rather than pip, because
  # every one of these ships a PEP 668 "externally managed" python where a
  # plain `pip install` into the system interpreter now refuses to run.
  neovim-python

  # -- Containers --
  podman
  podman-docker   # `docker` as an alias for podman

  # -- Shell of choice for this repo's own scripts --
  nushell

  # nushell keeps its less common commands out of the binary: `from ini`,
  # `query json` and `inc` are plugins, shipped as separate
  # executables and unknown to the shell until registered. See NUSHELL_PLUGINS
  # below for which ones, and steps/plugins.nu for the registration.
  nushell-plugins

  # -- Odds and ends --
  mkisofs
]

# Installed through pipx rather than the distro, because the distro versions
# lag and these are pure-python leaf tools with no system integration.
export const PIPX = [
  tmuxp
]

# neovim's node provider, which has no distro package worth relying on.
export const NPM = [
  neovim
]

# The nushell plugins to register, by their short name: the binary is
# nu_plugin_NAME, and openSUSE's package is nushell-plugin_NAME.
#
# The list is spelled out again in packages/suse.nu and lib/fallback.nu, because
# a const cannot be derived from another with `each`; tests/unit/plugins.nu
# holds all three to this one.
#
#   formats   from ini, from eml, from ics, from vcf, from plist
#   query     query json / xml / web, against files and pages
#   inc       bump a semver string or a number
#
# polars, the dataframe plugin, is deliberately not here: a 120 MB binary for
# a library nothing in this environment uses. Add it to this list if that
# changes -- the packaging on both sides follows the same naming.
export const NUSHELL_PLUGINS = [
  formats
  query
  inc
]
