# Checks that the tracked config files and the code that installs them agree.
#
# These are the failures that no amount of testing the installer would catch:
# the install succeeds, and the shell is subtly wrong.

use ../../steps/zsh.nu
use std/testing *
use std/assert

# `path self` resolves at parse time to this file, so the repo root is found
# the same way whether the tests run from the repo, from $HOME, or from inside
# a container. $env.FILE_PWD would not do: it is unset when a module is loaded
# by `nu --commands`, which is exactly how the runner invokes this.
const REPO = (path self | path dirname | path dirname | path dirname)

def zshrc []: nothing -> string {
  open --raw ($REPO | path join "home" ".zshrc")
}

# A file's active content: comments dropped, so a note explaining why something
# was removed does not read as the thing still being there.
def active [file: path]: nothing -> string {
  open --raw $file
  | lines
  | where {|l| not (($l | str trim) | str starts-with "#") }
  | str join "\n"
}

# Every file that gets linked into $HOME.
def home-files []: nothing -> list<path> {
  let files = (glob ($REPO | path join "home" "**" "*") --no-dir)
  # Guards against the whole suite passing vacuously if this path is ever
  # wrong: an empty glob would make every loop below a no-op.
  assert ($files | is-not-empty) $"no files found under ($REPO)/home"
  $files
}

@test
export def "every external plugin we install is enabled in zshrc" [] {
  # Cloning a plugin that .zshrc never lists is dead weight; listing one we do
  # not clone makes zsh complain on every start.
  for plugin in ($zsh.PLUGINS | columns) {
    assert str contains (zshrc) $plugin $"($plugin) is installed by steps/zsh.nu but not enabled in home/.zshrc"
  }
}

@test
export def "syntax highlighting is loaded last" [] {
  # zsh-syntax-highlighting wraps the line editor and must be the final plugin;
  # anything after it silently loses highlighting.
  let plugins = (zshrc
    | lines
    | skip until {|l| $l | str starts-with "plugins=(" }
    | take until {|l| ($l | str trim) == ")" })

  let listed = ($plugins
    | each {|l| $l | str replace --regex '#.*$' '' | str trim }
    | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "plugins=(")) })

  assert equal ($listed | last) "zsh-syntax-highlighting"
}

@test
export def "zsh has a prompt theme" [] {
  # An empty ZSH_THEME with nothing else drawing a prompt leaves zsh's bare
  # "%m%#", which looks like a broken shell rather than a configured one. That
  # is exactly what happened when starship was removed from this repo without
  # restoring the theme it had displaced.
  let theme = (zshrc
    | lines
    | where {|l| $l =~ '^ZSH_THEME=' }
    | last)

  assert ($theme =~ 'ZSH_THEME="[a-z]') $"expected a named theme, found: ($theme)"
}

@test
export def "no config still reaches for starship" [] {
  # starship was removed; a leftover `starship init` in a shell rc is a error
  # message on every shell start once the binary is gone.
  for file in (home-files) {
    assert not (((active $file) | str lowercase) =~ 'starship') $"($file | path basename) still references starship"
  }
}

@test
export def "nothing still reaches for powerline" [] {
  # powerline was replaced by starship; a leftover reference means a shell that
  # errors on start, or a status bar that silently never renders.
  for file in (home-files) {
    assert not (((active $file) | str lowercase) =~ 'powerline') $"($file | path basename) still references powerline"
  }
}

@test
export def "no config hardcodes a specific home directory" [] {
  # These files started life on a root install and carried /root paths around
  # in them, which quietly broke PATH for every non-root user.
  for file in (home-files) {
    assert not ((active $file) =~ '/root/') $"($file | path basename) hardcodes /root"
    assert not ((active $file) =~ '/home/[a-z]') $"($file | path basename) hardcodes a specific home directory"
  }
}

@test
export def "tmux does not source a file the repo no longer ships" [] {
  let conf = (open --raw ($REPO | path join "home" ".tmux.conf"))
  let sourced = ($conf | lines | where {|l| $l | str trim | str starts-with "source" })

  for line in $sourced {
    # source-file takes flags (-q suppresses the error for a missing file), so
    # strip the command AND any flags before what is left is a path.
    let target = ($line
      | str trim
      | str replace --regex '^source(-file)?\s+' ''
      | str replace --regex '^(-[a-zA-Z]+\s+)*' ''
      | str trim
      | str trim --char '"'
      | str trim --char "'")

    let relative = ($target | str replace '$HOME/' '' | str replace '~/' '')
    assert (($REPO | path join "home" $relative) | path exists) $"tmux sources ($target), which is not in home/"
  }
}

@test
export def "the locale is set before oh-my-zsh loads" [] {
  # Order, not presence. The prompt theme reads the locale's codeset when it is
  # loaded, so setting LANG afterwards -- which is where the stock .zshrc puts
  # it -- leaves the theme initialised for ASCII while running in UTF-8. Its
  # prompt fill then expands to a malformed ${(l:...)} and zsh prints
  # "closing brace expected" before every prompt.
  #
  # Only reproducible where LANG is not already in the environment: a desktop
  # session sets it, a container does not.
  let lines = (zshrc | lines)
  let lang = ($lines | enumerate | where {|r| $r.item =~ '^\s*export LANG=' } | get index)
  let omz = ($lines | enumerate | where {|r| $r.item =~ 'source \$ZSH/oh-my-zsh\.sh' } | get index | first)

  assert ($lang | is-not-empty) "no LANG is exported anywhere in .zshrc"
  assert (($lang | math max) < $omz) $"LANG is exported at lines ($lang) but oh-my-zsh loads at line ($omz)"
}

@test
export def "tmux has a socket directory that will exist" [] {
  # tmux is built to keep its socket in /run/tmux/$UID on openSUSE, and that
  # directory is created at boot by systemd-tmpfiles. Nothing creates it where
  # systemd is not running, so on a container or a minimal image tmux refuses
  # to start at all:
  #
  #   couldn't create directory /run/tmux/1000 (No such file or directory)
  #
  # Pointing TMUX_TMPDIR at XDG_RUNTIME_DIR, or /tmp when there is none, makes
  # tmux work the same everywhere.
  for name in [".zshrc" ".bashrc"] {
    let rc = (open --raw ($REPO | path join "home" $name))
    assert str contains $rc "TMUX_TMPDIR" $"($name) does not set TMUX_TMPDIR, so tmux will not start without systemd-tmpfiles"
    assert str contains $rc "XDG_RUNTIME_DIR" $"($name) should prefer XDG_RUNTIME_DIR for the tmux socket"
  }
}

@test
export def "tmux does not hardcode a terminal that may be missing" [] {
  # tmux-256color is the right entry but lives in a terminfo package that is
  # not installed by default anywhere. Naming it unconditionally means every
  # login shell inside tmux stops to ask "Terminal type?" on any machine where
  # that package is absent -- including, as it turned out, this one.
  let conf = (open --raw ($REPO | path join "home" ".tmux.conf"))

  let unconditional = ($conf
    | lines
    | where {|l| $l =~ '^\s*set(-option)?\s+-g\s+default-terminal' })

  assert equal $unconditional [] "default-terminal is set unconditionally; pick it based on what infocmp finds"
  assert str contains $conf "infocmp" "the choice of default-terminal should be guarded by an infocmp check"
}

@test
export def "tmux actually configures its status line" [] {
  # Presence, because absence is silent. Deleting these leaves tmux on its
  # stock green bar and reports nothing -- no error, no warning, just the
  # default. That is exactly what happened: an edit meant to replace the
  # palette block took the whole status section with it, and a check that only
  # looked at the theme variables (which come from the sourced theme file, and
  # were still fine) said everything was well.
  let conf = (open --raw ($REPO | path join "home" ".tmux.conf"))

  for option in [
    "status-style"
    "status-left"
    "status-right"
    "window-status-format"
    "window-status-current-format"
  ] {
    assert str contains $conf $option $"($option) is not set; tmux would fall back to its default status bar"
  }
}

@test
export def "every colour the status line uses is defined by a theme" [] {
  # The status format strings refer to colours as #{@name}. A typo, or a name
  # a theme does not define, renders as an empty style rather than an error.
  let conf = (open --raw ($REPO | path join "home" ".tmux.conf"))

  let used = ($conf
    | parse --regex '#\{(@[a-z_]+)\}'
    | get capture0
    | uniq
    | sort)

  assert ($used | is-not-empty) "the status line references no theme colours at all"

  let themes = (glob ($REPO | path join "home" ".config" "tmux" "themes" "*.conf"))
  assert ($themes | is-not-empty) "no themes found"

  for theme in $themes {
    let defined = (open --raw $theme
      | parse --regex '(?m)^set -g (@[a-z_]+)'
      | get capture0
      | uniq)

    for name in $used {
      assert ($name in $defined) $"($theme | path basename) does not define ($name), which the status line uses"
    }
  }
}
