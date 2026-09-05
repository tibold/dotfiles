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
if [ -z "${TMUX_TMPDIR:-}" ]; then
  export TMUX_TMPDIR="${XDG_RUNTIME_DIR:-/tmp}"
fi

alias vim=nvim
alias vi=nvim

export VISUAL=nvim
export EDITOR=nvim
export SYSTEMD_EDITOR=nvim

