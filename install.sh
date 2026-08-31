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

log 'Install Python packages'
sudo pip install $(cat pip_packages.txt)

log 'Install Python packages (pipx)'
sudo pipx install $(cat pipx_packages.txt)

log 'Install npm.js packages'
sudo npm install $(cat npm_packages.txt)

log 'Ensure PATH has ~/.local/bin'
pipx ensurepath
export PATH="$PATH:$HOME/.local/bin"

# install.sh
log 'Link dot files and config in place'
ln -sf "$SCRIPT_DIR/.tmux.conf" ~/.tmux.conf
ln -sf "$SCRIPT_DIR/.bashrc" ~/.bashrc
ln -sf "$SCRIPT_DIR/.zshrc" ~/.zshrc
ln -sf "$SCRIPT_DIR/.gitconfig" ~/.gitconfig
ln -sf "$SCRIPT_DIR/config/powerline-tmux.conf" ~/.config/powerline-tmux.conf
# lazygit reads a directory rather than a flat file in ~/.config, so the
# directory has to exist before the link goes into it.
mkdir -p ~/.config/lazygit
ln -sf "$SCRIPT_DIR/config/lazygit/config.yml" ~/.config/lazygit/config.yml

log 'Install zsh plugins'
"$SCRIPT_DIR/scripts/setup-zsh-plugins.sh"

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
# Pick the transport by what can actually authenticate, in that order.
#
# This used to test [ -n "$SSH_AUTH_SOCK" ], which asks the wrong question:
# GNOME's gcr-ssh-agent exports that socket in every desktop session whether or
# not a key is loaded, so on a workstation it was always set and the ssh branch
# was always taken -- with an empty agent, so the clone failed while gh and
# https sat there working.
#
# ssh-add -l is the right test for the ssh case: it exits non-zero both when the
# agent holds no identities and when there is no agent to reach.
if gh auth status >/dev/null 2>&1; then
  # gh installs itself as git's credential helper, so https needs nothing else
  clone_repo "https://github.com/tibold/astrovim-init.git" "$HOME/.config/nvim"
elif ssh-add -l >/dev/null 2>&1; then
  # on servers where access is only granted through a forwarded ssh agent
  clone_repo "git@github.com:tibold/astrovim-init.git" "$HOME/.config/nvim"
else
  # nothing is set up either way; https at least lets git prompt
  clone_repo "https://github.com/tibold/astrovim-init.git" "$HOME/.config/nvim"
fi
log 'Neovim will install its plugins on first start'
