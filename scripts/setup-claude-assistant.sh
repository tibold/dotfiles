#!/bin/bash
# Setup script for a restricted claude-assistant user
# - No sudo access, no password (login only via su)
# - Claude CLI installed and authenticated
# - GitHub authenticated
# - Simple launch script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="claude-assistant"
WORK_DIR="/home/${USERNAME}/work"

mkdir -p ~/.local/bin
mkdir -p ~/.tmuxp/

ln -sf "$SCRIPT_DIR/bin/claude" ~/.local/bin/claude
ln -sf "$SCRIPT_DIR/tmuxp/claude.yaml" ~/.tmuxp/claude.yaml

# --- Helpers ---

log() { echo "==> $1"; }
err() {
  echo "ERROR: $1" >&2
  exit 1
}

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root"
  fi
}

# --- User setup ---

create_user() {
  if id "$USERNAME" &>/dev/null; then
    log "User $USERNAME already exists"
  else
    log "Creating user $USERNAME (no password, no sudo)"
    useradd -m -s /bin/bash "$USERNAME"
    passwd -l "$USERNAME" # Lock password — no direct login
  fi

  mkdir -p "$WORK_DIR"
  chown "$USERNAME:$USERNAME" "$WORK_DIR"
}

# --- Claude CLI ---

install_claude() {
  if [ -f "/home/${USERNAME}/.local/bin/claude" ]; then
    log "Claude CLI already installed"
    su - "$USERNAME" -c "claude --version"
  else
    log "Installing Claude CLI"
    su - "$USERNAME" -c 'curl -fsSL https://claude.ai/install.sh | sh'
  fi
}

configure_claude_plugins() {
  local settings_dir="/home/${USERNAME}/.claude"
  local settings_file="${settings_dir}/settings.json"

  mkdir -p "$settings_dir"

  if [ -f "$settings_file" ]; then
    log "Claude settings.json already exists, skipping"
  else
    log "Writing Claude settings.json"
    cat >"$settings_file" <<'SETTINGS'
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "remember@claude-plugins-official": true
  }
}
SETTINGS
  fi

  chown -R "$USERNAME:$USERNAME" "$settings_dir"
}

# --- Authentication ---

authenticate_claude() {
  if su - "$USERNAME" -c "claude auth status --text"; then
    log "Claude already authenticated"
  else
    log "Authenticating Claude CLI (interactive)"
    log "You will be switched to the $USERNAME user"
    su - "$USERNAME" -c "claude login"
  fi
}

authenticate_github() {
  # Check if gh is installed
  if ! command -v gh &>/dev/null; then
    log "Installing GitHub CLI"
    sudo zypper install -y gh
  fi

  # Check if gh is already authenticated
  if su - "$USERNAME" -c "gh auth status" &>/dev/null; then
    log "GitHub already authenticated"
  else
    log "Authenticating GitHub CLI (interactive)"
    log "You will be switched to the $USERNAME user"
    su - "$USERNAME" -c "gh auth login"
  fi
}

# --- CLAUDE.md ---

create_claude_md() {
  local claude_md="${WORK_DIR}/CLAUDE.md"

  if [ -f "$claude_md" ]; then
    log "CLAUDE.md already exists"
  else
    local distro
    distro=$(. /etc/os-release && echo "$NAME $VERSION_ID" 2>/dev/null || echo "Linux")
    log "Creating CLAUDE.md (detected: $distro)"
    cat >"$claude_md" <<'CLAUDEMD'
You are a sysadmin assistant for an ${distro} server.
Focus on system administration, not coding.
You are in a sandbox, so you can only use local md files as notes and read some system settings.               
CLAUDEMD
    chown "$USERNAME:$USERNAME" "$claude_md"
  fi
}

# --- Launch script ---

create_launch_script() {
  local script="/home/${USERNAME}/start-claude.sh"

  if [ -f "$script" ]; then
    log "Launch script already exists"
  else
    log "Creating launch script"
    cat >"$script" <<'LAUNCH'
#!/bin/bash
cd ~/work
claude --append-system-prompt "You are a sysadmin assisstant for an openSUSE Tumbleweed server. Focus on system administration, not coding. You are in a sandbox, so you can only use local md files as notes."
LAUNCH
    chmod +x "$script"
    chown "$USERNAME:$USERNAME" "$script"
  fi
}

# --- Hardening wrapper ---
#
# Create a hardened wrapper
create_su_wrapper() {
  local wrapper="/usr/local/bin/su-claude"

  cat >"$wrapper" <<EOF
#!/bin/bash
# Launch a restricted shell for claude-assistant
# - Only /home/${USERNAME} is visible and writable
# - /etc, other homes, system dirs are hidden or read-only
# - Private /tmp
# - No device access

CMD="\${*:-/home/${USERNAME}/start-claude.sh}"

exec systemd-run --uid=claude-assistant --gid=claude-assistant \\
  --property="ProtectHome=tmpfs" \\
  --property="ReadOnlyPaths=/etc" \\
  --property="InaccessiblePaths=/etc/shadow /etc/sudoers /etc/sudoers.d /etc/ssh" \\
  --property="BindPaths=/home/claude-assistant" \\
  --property="ProtectSystem=strict" \\
  --property="PrivateTmp=yes" \\
  --property="PrivateDevices=yes" \\
  --property="ProtectKernelTunables=yes" \\
  --property="ProtectKernelModules=yes" \\
  --property="ProtectControlGroups=yes" \\
  --property="RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX" \\
  --pty -- /bin/bash -l -c "\$CMD"
EOF

  chmod +x "$wrapper"
  log "Created $wrapper"
  log "Usage: sudo su-claude"
  log "Or: sudo su-claude bash"
}

# --- Main ---

main() {
  check_root

  log "Setting up restricted claude-assistant user"
  echo ""

  create_user
  install_claude
  configure_claude_plugins
  create_claude_md
  create_launch_script
  create_su_wrapper

  echo ""
  log "Non-interactive setup complete."
  echo ""
  log "Remaining manual steps:"
  echo "  1. Authenticate Claude:  $0 --auth-claude"
  echo "  2. Authenticate GitHub:  $0 --auth-github"
  echo ""
  log "To switch to the user:  su - $USERNAME"
  log "To launch claude:       su - $USERNAME -c ~/start-claude.sh"
}

# --- CLI ---

case "${1:-}" in
--auth-claude)
  check_root
  authenticate_claude
  ;;
--auth-github)
  check_root
  authenticate_github
  ;;
--all)
  main
  authenticate_claude
  authenticate_github
  ;;
*)
  main
  authenticate_claude
  ;;
esac
