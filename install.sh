#!/bin/bash

log() { echo "==> $1"; }
err() {
  ▏ echo "ERROR: $1" >&2
  ▏ exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install packages
log 'Install system packages'
sudo zypper install -y $(cat packages.txt)

log 'Install Python packages (pipx)'
sudo pipx install $(cat pip_packages.txt)

log 'Ensure PATH has ~/.local/bin'
pipx ensurepath
export PATH="$PATH:$HOME/.local/bin"

# install.sh
log 'Link dot files and config in place'
ln -sf "$SCRIPT_DIR/.tmux.conf" ~/.tmux.conf
ln -sf "$SCRIPT_DIR/.zshrc" ~/.zshrc
ln -sf "$SCRIPT_DIR/config/powerline-tmux.conf" ~/.config/powerline-tmux.conf
ln -sf "$SCRIPT_DIR/tmuxp" ~/.tmuxp
ln -sf "$SCRIPT_DIR/bin/claude" ~/.local/bin/claude

# Clone nvim config
clone_repo() {
  local url="$1"
  local dest="$2"

  if [ -d "$dest" ]; then
    if [ -d "$dest/.git" ]; then
      existing_url=$(git -C "$dest" remote get-url origin 2>/dev/null)
      if [ "$existing_url" = "$url" ]; then
        echo "OK: $dest already contains $url, pulling latest"
        git -C "$dest" pull
        return 0
      else
        echo "ERROR: $dest exists but points to $existing_url (expected $url)"
        return 1
      fi
    else
      echo "ERROR: $dest exists but is not a git repository"
      return 1
    fi
  fi

  git clone "$url" "$dest"
}

log 'Clone neovim configuration'
clone_repo "https://github.com/tibold/astrovim-init.git" "$HOME/.config/nvim"
log 'Neovim will install its plugins on first start'

"$SCRIPT_DIR/scripts/setup-claude-assistant.sh"
