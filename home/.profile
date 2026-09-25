# Read by login shells. Kept small on purpose -- interactive zsh config lives
# in ~/.zshrc, which does not read this file.

# openSUSE's stock ~/.profile does this, and replacing that file would
# otherwise drop it. It is a fallback rather than the normal path: a login
# shell reads /etc/profile itself before getting here, and PROFILEREAD is how
# SUSE records that, so this only fires when something sourced this file
# without it -- a display manager or a systemd unit, say.
#
# It has to come before PATH is touched below. Debian's /etc/profile *assigns*
# PATH rather than appending to it, so sourcing it afterwards would silently
# throw away the entry added here.
if [ -z "${PROFILEREAD:-}" ] && [ -r /etc/profile ]; then
  . /etc/profile
fi

# Homebrew, on macOS: the same thing ~/.zshrc does, for login shells that are
# not zsh. See the longer note there.
#
# After /etc/profile, whose path_helper rebuilds PATH from scratch, and before
# the ~/.local/bin line below, so that the order ends up the same as everywhere
# else: ~/.local/bin, then Homebrew, then the system.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# The opt-in language SDKs (steps/rust.nu, steps/dotnet.nu), each only where
# it has been installed. Before ~/.local/bin below, which stays first. The .NET
# SDK lives in ~/.dotnet everywhere but Windows, and its apphosts -- dotnet
# global tools among them -- find the runtime through DOTNET_ROOT.
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi
if [ -x "$HOME/.dotnet/dotnet" ]; then
  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
fi

# ~/.local/bin holds pipx shims, the Claude CLI, and any tool this repo had to
# fetch from an upstream release because the distro does not package it
# (see lib/fallback.nu). Prepended, not appended, so those win over an older
# distro copy of the same binary.
export PATH="$HOME/.local/bin:$PATH"
