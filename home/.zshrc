# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# Drawn by Oh My Zsh, which is already a dependency of this file.
#
# starship was tried here and removed. It is the better answer only if you use
# more than one shell interactively, because it gives all of them the same
# prompt -- and zsh is the only interactive shell on these machines. Against
# that, it is packaged on Tumbleweed alone, so on Leap, Fedora and Ubuntu it
# meant fetching and re-fetching an upstream binary to draw a prompt that
# Oh My Zsh already draws for free.
ZSH_THEME="jonathan"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  # -- Shell enhancements --
  zsh-autosuggestions # Ghost text suggestions from history
  zsh-completions     # Additional completion definitions
  fzf-tab             # Fuzzy completion menu
  colored-man-pages   # Colorized man pages
  command-not-found   # Suggests packages for unknown commands
  history             # History search shortcuts
  sudo                # Press Esc twice to prepend sudo

  # -- Navigation --
  z          # Jump to frequent directories (z myproject)
  dirhistory # Alt+arrows to navigate directory history

  # -- Development --
  git  # Git aliases (gst, ga, gc, gp, gd, glog...)
  node # Node.js aliases
  npm  # npm completions and aliases

  # -- DevOps --
  kubectl        # Kubernetes aliases (k, kgp, kgs, kdp, kl...)
  helm           # Helm aliases (h, hi, hu, hls...)
  terraform      # Terraform aliases (tf, tfi, tfp, tfa...)
  podman         # Podman completions
  docker-compose # Docker compose aliases (dco, dcup, dcdown...)
  systemd        # systemctl aliases (sc-start, sc-stop, sc-status...)

  # -- Sysadmin --
  suse        # because I mostly use OpenSUSE
  rsync       # rsync aliases
  systemadmin # System administration helpers
  firewalld   # firewalld completions

  vi-mode                 # Visual indicator for vim bindings
  zsh-syntax-highlighting # Colors commands as you type (MUST be last)
)

VI_MODE_SET_CURSOR=true

# Locale. This has to be settled BEFORE Oh My Zsh is sourced.
#
# The prompt theme decides at load time whether this terminal can draw box
# characters, by reading the locale's codeset. The stock .zshrc sets LANG
# further down, under "User configuration", which leaves the theme initialised
# for ASCII while running in a UTF-8 locale -- an inconsistent pair whose
# prompt fill expands to a malformed ${(l:...)} that zsh reports as
# "closing brace expected" before every prompt.
#
# Invisible on a desktop, where the session exports LANG long before zsh starts.
# It shows up on a minimal server or in a container, which is exactly where
# this repo also has to work.
if [[ ${LANG:-} != *[Uu][Tt][Ff]* ]]; then
  if locale -a 2>/dev/null | grep -qix 'en_US\.utf-\?8'; then
    export LANG=en_US.UTF-8
  else
    # Built into glibc since 2.35 and present even on stripped-down images.
    export LANG=C.UTF-8
  fi
fi

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# The language environment is set above, before Oh My Zsh loads -- see the note
# there for why the order matters.

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Where tmux keeps its socket.
#
# tmux is compiled with a default socket directory -- /run/tmux/$UID on
# openSUSE -- which systemd-tmpfiles creates at boot from
# /usr/lib/tmpfiles.d/tmux.conf. Nothing creates it where systemd is not
# running, so on a container or a minimal image tmux fails to start with
# "couldn't create directory /run/tmux/1000 (No such file or directory)".
#
# XDG_RUNTIME_DIR is the standard per-user runtime location and is already
# 0700, which is what tmux requires; /tmp is the fallback when there is no
# session bus at all (cron, ssh without pam_systemd), and tmux makes its own
# 0700 directory inside it.
# if [ -z "${TMUX_TMPDIR:-}" ]; then
#   export TMUX_TMPDIR="${XDG_RUNTIME_DIR:-/tmp}"
# fi

alias vim=nvim
alias vi=nvim
export VISUAL=nvim
export EDITOR=nvim
export SYSTEMD_EDITOR=nvim

# The following lines were added by compinstall

zstyle ':completion:*' completer _expand _complete _ignored _correct
zstyle ':completion:*' matcher-list '' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|[._-]=** r:|=**'
zstyle ':completion:*' max-errors 2
zstyle ':completion:*' menu select=2
zstyle ':completion:*' original true
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle :compinstall filename "$HOME/.zshrc"

autoload -Uz compinit
compinit
# End of lines added by compinstall
# Lines configured by zsh-newuser-install
HISTFILE=~/.zsh.history
HISTSIZE=10000
SAVEHIST=1000000
setopt autocd extendedglob nomatch
unsetopt beep notify

# End of lines configured by zsh-newuser-install

# See the note in ~/.profile; zsh does not read it for interactive shells.
export PATH="$HOME/.local/bin:$PATH"

autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'v' edit-command-line

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
