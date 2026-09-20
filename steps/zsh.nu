# Oh My Zsh and the plugins .zshrc expects.
#
# These are git clones rather than packages because Oh My Zsh has no packaged
# form worth using and the plugins are distributed only as repositories. Each
# is skipped when already present, so this is safe to re-run.

use ../lib/log.nu

# name -> repository. The list is kept next to nothing else on purpose: it must
# stay in step with the plugins=() block in home/.zshrc, and the container test
# asserts exactly that.
export const PLUGINS = {
  zsh-autosuggestions: "https://github.com/zsh-users/zsh-autosuggestions"
  zsh-syntax-highlighting: "https://github.com/zsh-users/zsh-syntax-highlighting"
  zsh-completions: "https://github.com/zsh-users/zsh-completions"
  fzf-tab: "https://github.com/Aloxaf/fzf-tab"
}

const OMZ_INSTALLER = "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

# Make zsh the login shell.
#
# Nothing else does this, and without it the whole configuration sits there
# unused: the session still starts bash, and so does tmux, which takes the
# shell from the passwd entry rather than from $SHELL. On a machine set up by
# hand years ago this has long since been done and is invisible; on a fresh one
# it is the difference between the environment working and not.
#
# The two systems answer the same question differently. passwd is a file to be
# read on Linux, and a database behind Directory Services on macOS, where
# /etc/passwd still exists but does not describe a real user's account. The
# parsing of each is separated out so both can be tested on either.

# The shell field of a getent passwd line: seven colon-separated fields, the
# shell last.
export def parse-passwd-shell [text: string]: nothing -> string {
  $text | str trim | split row ":" | last
}

# The shell from `dscl . -read /Users/NAME UserShell`, which answers
# "UserShell: /bin/zsh" -- a key, a colon, the value.
export def parse-dscl-shell [text: string]: nothing -> string {
  $text | str trim | split row ":" | last | str trim
}

# This user's login shell as the system records it, or "" if it cannot be read.
export def login-shell [user: string]: nothing -> string {
  if $nu.os-info.name == "macos" {
    let result = (do { ^dscl . -read $"/Users/($user)" UserShell } | complete)
    if $result.exit_code != 0 { return "" }
    parse-dscl-shell $result.stdout
  } else {
    let result = (do { ^getent passwd $user } | complete)
    if $result.exit_code != 0 { return "" }
    parse-passwd-shell $result.stdout
  }
}

export def set-login-shell [--dry-run]: nothing -> nothing {
  let zsh = (which zsh | get --optional path.0)
  if $zsh == null {
    log warn "zsh is not on PATH yet -- not changing the login shell"
    return
  }

  # -un rather than --user --name: the long options are GNU coreutils' and BSD
  # id on macOS does not have them, while the short ones mean the same thing on
  # both.
  let user = (^id -un | str trim)
  let shell = (login-shell $user)

  if ($shell | is-empty) {
    log warn $"could not look up ($user)'s login shell -- not changing it"
    return
  }

  # Compared as resolved paths, not as strings. /bin is a symlink to /usr/bin
  # on any usr-merged distribution, so passwd saying /bin/zsh and `which`
  # saying /usr/bin/zsh describe the same file -- and comparing the text would
  # run chsh on every install to change nothing.
  if ($shell | path expand) == ($zsh | path expand) {
    log skipped $"login shell is already ($shell)"
    return
  }

  # chsh only accepts a shell listed in /etc/shells. The zsh package adds
  # itself there, so this holds after the packages step -- but say so plainly
  # rather than letting chsh fail with its own terse message.
  #
  # On macOS this is also the guard that stops a Homebrew zsh from being made
  # the login shell: brew does not edit /etc/shells, and the system zsh that is
  # listed there is already the default, so the normal outcome on a Mac is the
  # skip above rather than anything happening here at all.
  let shells = (if ("/etc/shells" | path exists) {
    open --raw /etc/shells
    | lines
    | each {|l| $l | str trim }
    | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "#")) }
    | each {|l| $l | path expand }
  } else { [] })

  if ($zsh | path expand) not-in $shells {
    log warn $"($zsh) is not listed in /etc/shells -- not changing the login shell"
    return
  }

  log info $"login shell is ($shell)"
  # -s rather than --shell: util-linux's chsh accepts both, BSD's accepts only
  # the short one.
  log shell ["sudo" "chsh" "-s" $zsh $user] --dry-run=$dry_run
}

export def install [--home: path, --dry-run]: nothing -> nothing {
  log step "Oh My Zsh"

  let omz = ($home | path join ".oh-my-zsh")

  if ($omz | path exists) {
    log skipped "Oh My Zsh already installed"
  } else if $dry_run {
    log info $"would install Oh My Zsh into ($omz)"
  } else {
    # --keep-zshrc is essential: without it the installer moves our symlinked
    # .zshrc aside and writes its own, quietly undoing the link step.
    let script = (http get $OMZ_INSTALLER)
    $script | ^sh -s -- --unattended --keep-zshrc
    log ok "Oh My Zsh installed"
  }

  let custom = ($home | path join ".oh-my-zsh" "custom" "plugins")

  for name in ($PLUGINS | columns) {
    let dest = ($custom | path join $name)
    if ($dest | path exists) {
      log skipped $"plugin ($name)"
    } else if $dry_run {
      log info $"would clone ($name) into ($dest)"
    } else {
      mkdir $custom
      log shell ["git" "clone" "--depth" "1" ($PLUGINS | get $name) $dest]
      log ok $"plugin ($name)"
    }
  }

  set-login-shell --dry-run=$dry_run
}
