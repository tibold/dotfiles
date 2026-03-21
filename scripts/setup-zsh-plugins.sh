#!/bin/bash
# Setup Oh My Zsh and plugins for development workflows
# Run as the target user (not root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

log() { echo "==> $1"; }

# --- Oh My Zsh ---

install_omz() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh already installed"
  else
    log "Installing Oh My Zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
  fi
}

# --- External plugins (not bundled with OMZ) ---

install_external_plugin() {
  local name="$1"
  local repo="$2"
  local dest="${ZSH_CUSTOM}/plugins/${name}"

  if [ -d "$dest" ]; then
    log "Plugin $name already installed"
  else
    log "Installing plugin: $name"
    git clone --depth 1 "$repo" "$dest"
  fi
}

install_external_plugins() {
  # Auto-suggestions: ghost text from command history
  install_external_plugin "zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions"

  # Syntax highlighting: colors commands as you type
  install_external_plugin "zsh-syntax-highlighting" \
    "https://github.com/zsh-users/zsh-syntax-highlighting"

  # Completions: additional completion definitions
  install_external_plugin "zsh-completions" \
    "https://github.com/zsh-users/zsh-completions"

  # fzf-tab: fuzzy completion menu using fzf
  install_external_plugin "fzf-tab" \
    "https://github.com/Aloxaf/fzf-tab"
}

# --- Generate plugin list for .zshrc ---

generate_plugin_config() {
  log "Generating plugin configuration"

  cat <<'EOF'

# --- Paste this into the plugins=() section of your ~/.zshrc ---

plugins=(
  # -- Shell enhancements --
  zsh-autosuggestions          # Ghost text suggestions from history
  zsh-completions              # Additional completion definitions
  fzf-tab                      # Fuzzy completion menu
  colored-man-pages            # Colorized man pages
  command-not-found            # Suggests packages for unknown commands
  history                      # History search shortcuts
  sudo                         # Press Esc twice to prepend sudo

  # -- Navigation --
  z                            # Jump to frequent directories (z myproject)
  dirhistory                   # Alt+arrows to navigate directory history

  # -- Development --
  git                          # Git aliases (gst, ga, gc, gp, gd, glog...)
  node                         # Node.js aliases
  npm                          # npm completions and aliases

  # -- DevOps --
  kubectl                      # Kubernetes aliases (k, kgp, kgs, kdp, kl...)
  helm                         # Helm aliases (h, hi, hu, hls...)
  terraform                    # Terraform aliases (tf, tfi, tfp, tfa...)
  podman                       # Podman completions
  docker-compose               # Docker compose aliases (dco, dcup, dcdown...)
  systemd                      # systemctl aliases (sc-start, sc-stop, sc-status...)
  ssh-agent                    # Auto-starts ssh-agent

  # -- Sysadmin --
  rsync                        # rsync aliases
  systemadmin                  # System administration helpers
  firewalld                    # firewalld completions

  zsh-syntax-highlighting      # Colors commands as you type (MUST be last)
)

# NOTE: zsh-syntax-highlighting MUST be the last plugin in the list
EOF
}

# --- Dependency check ---

check_dependencies() {
  log "Checking optional dependencies"

  local missing=()

  command -v fzf &>/dev/null || missing+=("fzf (needed for fzf-tab)")
  command -v git &>/dev/null || missing+=("git")
  command -v kubectl &>/dev/null || missing+=("kubectl (for kubectl plugin)")
  command -v helm &>/dev/null || missing+=("helm (for helm plugin)")
  command -v terraform &>/dev/null || missing+=("terraform (for terraform plugin)")
  command -v podman &>/dev/null || missing+=("podman (for podman plugin)")
  command -v node &>/dev/null || missing+=("node (for node/npm plugin)")
  command -v systemctl &>/dev/null || missing+=("systemctl (for systemd plugin)")

  if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    echo "Optional tools not found (plugins will be inactive without them):"
    for tool in "${missing[@]}"; do
      echo "  - $tool"
    done
    echo ""
    echo "Install on openSUSE: sudo zypper install <package>"
    echo "Remove unused plugins from .zshrc to speed up shell startup."
  else
    log "All optional dependencies found"
  fi
}

# --- Main ---

main() {
  log "Setting up Zsh plugins"
  echo ""

  install_omz
  install_external_plugins
  check_dependencies

  # Example only, .zshrc already contains the plugins
  # echo ""
  # generate_plugin_config

  echo ""
  log "Done! Update your ~/.zshrc with the plugin list above"
  log "Then run: source ~/.zshrc"
}

main
