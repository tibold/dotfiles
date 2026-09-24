# Windows, via winget.
#
# Windows is the third platform here and the most different one. zsh, tmux and
# the terminfo database do not exist natively, so their roles are taken by
# pwsh, oh-my-posh and psmux -- configured in platform/windows/, not here.
# Where a Windows tool does the job of a logical name, however differently, it
# is mapped under that name: psmux ships a tmux.exe and pstop an htop.exe, so
# the commands keep their names.
#
# Values are winget ids (Publisher.Package), installed one at a time with
# --exact. Every id below was checked with `winget show --id <id> --exact`.

# logical name -> winget id.
#   string  the id
#   null    not from winget; must be accounted for in FONTS, PROVIDED or OMITTED
export const OVERRIDES = {
  # -- database clients (packages/common.nu DATABASES) --
  # There is no client-only PostgreSQL on winget: this is the full EDB
  # installer, told by WINGET_ARGS below to leave out everything but the
  # command-line tools. The pwsh profile puts its bin directory on PATH.
  postgresql-client: "PostgreSQL.PostgreSQL.18"
  sqlite: "SQLite.SQLite"

  tmux: "marlocarlo.psmux"
  htop: "marlocarlo.pstop"
  # The C compiler nvim-treesitter's parser builds find. Not gcc, but gcc is
  # what the logical name stands for: "something that compiles C".
  gcc: "LLVM.LLVM"
  neovim: "Neovim.Neovim"
  git: "Git.Git"
  gh: "GitHub.cli"
  lazygit: "JesseDuffield.lazygit"
  git-delta: "dandavison.delta"
  gitleaks: "Gitleaks.Gitleaks"
  ripgrep: "BurntSushi.ripgrep.MSVC"
  fzf: "junegunn.fzf"
  jq: "jqlang.jq"
  # Node through fnm, which is how this machine already works: the profile runs
  # `fnm env --use-on-cd`. steps/packages.nu installs an LTS default if fnm has
  # none.
  nodejs: "Schniz.fnm"
  podman: "RedHat.Podman"
  nushell: "Nushell.Nushell"
  # nerd-fonts is answered by FONTS below, and so needs no entry here -- the
  # same rule packages/macos.nu uses for CASKS.

  # -- see PROVIDED --
  curl: null
  tar: null
  git-credential-manager: null
  npm: null
  nushell-plugins: null

  # -- see OMITTED --
  zsh: null
  terminfo-extra: null
  diffutils: null
  make: null
  mkisofs: null
  podman-docker: null
  neovim-python: null
  pipx: null
}

# Not winget packages. Installed by `oh-my-posh font install <install> --headless`
# -- Windows' counterpart to Homebrew's casks for the one font this repo needs.
# The terminal is on this machine, so the font belongs here, as on macOS.
#
# Two names, because Nerd Fonts renames some of what it patches: oh-my-posh
# installs "SourceCodePro", and the files it puts down are SauceCodePro*. The
# second is what steps/packages.nu looks for to skip an installed font, and the
# family Rio's config names.
export const FONTS = {
  nerd-fonts: { install: "SourceCodePro", files: "SauceCodePro" }
}

# Windows-only tools with no logical name elsewhere.
#
# Rio, the terminal, is not among them: winget only has its per-machine MSI,
# which needs an administrator and lacks the ConPTY that images need.
# lib/rio.nu installs it for this user instead, from the packages step.
export const EXTRA = [
  "Microsoft.PowerShell"      # pwsh 7, the interactive shell here
  "JanDeDobbeleer.OhMyPosh"   # the prompt, and the font installer above
  "marlocarlo.psnet"          # the rest of the psmux family
  "marlocarlo.tmuxpanel"      # tmuxpanel, tmuxplugins, tmuxthemes
]

# Extra `winget install` arguments for the ids that need them.
#
# --override replaces the installer's whole command line, so it has to repeat
# the unattended switches winget would otherwise have passed. Without
# --disable-components the EDB installer sets up a PostgreSQL server as a
# Windows service, plus pgAdmin and StackBuilder, on a machine that only wants
# psql.
export const WINGET_ARGS = {
  "PostgreSQL.PostgreSQL.18": ["--override" "--mode unattended --unattendedmodeui none --disable-components server,pgAdmin,stackbuilder"]
}

export const PROVIDED = {
  curl: "curl.exe ships with Windows 10 1803 and later"
  tar: "bsdtar ships with Windows as tar.exe"
  git-credential-manager: "bundled with Git for Windows"
  npm: "comes with the node that fnm installs"
  nushell-plugins: "ships with Nushell.Nushell; the plugin executables sit beside nu.exe"
}

export const OMITTED = {
  zsh: "no native zsh on Windows; pwsh with oh-my-posh takes the role"
  terminfo-extra: "Windows consoles have no terminfo database"
  diffutils: "git bundles diff, and diffs are rendered by delta"
  make: "nothing in this environment builds with make on Windows"
  mkisofs: "not needed on the work machine"
  podman-docker: "no docker shim for podman on Windows; the pwsh profile aliases docker to podman when there is no real docker"
  neovim-python: "no packaged pynvim; neovim runs without the python provider"
  pipx: "the only pipx application, tmuxp, drives tmux and has nothing to drive here"
}

export const REMOVED = []
