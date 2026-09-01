# Leap, layered on top of packages/suse.nu.
#
# Leap tracks SLE, so its repos are years behind Tumbleweed's and simply do not
# carry the newer Rust and Go tools. Everything nulled here is picked up from
# the upstream release instead -- see lib/fallback.nu. This overlay exists so
# that Leap's shortfalls stay visible in one place rather than being smeared
# across the shared suse file as conditionals.
export const OVERRIDES = {
  lazygit: null
  git-delta: null
  gitleaks: null
  nushell: null

  # Leap's repos have no Nerd Font package under any name.
  nerd-fonts: null

  # Leap splits fzf less finely than Tumbleweed: there is no
  # fzf-zsh-integration package. The completion it would provide is small
  # enough to do without, and fzf-tab covers the same ground.
  fzf: ["fzf" "fzf-tmux" "vim-fzf"]

  # No pythonNNN-neovim on Leap under any version prefix.
  neovim-python: null

  # Leap 15.x's default python is 3.11.
  pipx: "python311-pipx"
}

export const EXTRA = []

# Nothing beyond what packages/suse.nu already removes.
export const REMOVED = []

export const OMITTED = {
  nerd-fonts: "not packaged on Leap, and a Leap box here is a server reached over ssh -- the glyphs come from the terminal you are sitting at, not this one"
  neovim-python: "no pythonNNN-neovim in Leap's repos; neovim runs fine without the python provider, it just cannot host python plugins"
}
