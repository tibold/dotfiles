alias vim=nvim
alias vi=nvim

# The following lines were added by compinstall

zstyle ':completion:*' completer _expand _complete _ignored _correct
zstyle ':completion:*' matcher-list '' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|[._-]=** r:|=**'
zstyle ':completion:*' max-errors 2
zstyle ':completion:*' menu select=2
zstyle ':completion:*' original true
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle :compinstall filename '/root/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall
# Lines configured by zsh-newuser-install
HISTFILE=~/.zsh.history
HISTSIZE=10000
SAVEHIST=1000000
setopt autocd extendedglob nomatch
unsetopt beep notify
bindkey -v

# End of lines configured by zsh-newuser-install
if [ -f /usr/share/powerline/zsh/powerline.zsh ]; then
  source /usr/share/powerline/zsh/powerline.zsh
fi

# Created by `pipx` on 2026-03-21 14:14:58
export PATH="$PATH:/root/.local/bin"
