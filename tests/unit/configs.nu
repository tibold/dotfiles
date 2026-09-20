# Checks that the tracked config files and the code that installs them agree.
#
# These are the failures that no amount of testing the installer would catch:
# the install succeeds, and the shell is subtly wrong.

use ../../steps/zsh.nu
use ../../lib/distro.nu
use ../../packages/macos.nu
use ../../packages/common.nu
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

# The entries of the plugins=( ... ) list, in order, comments stripped.
#
# One entry is `$os_plugins`, the array .zshrc fills in above the list with the
# plugins that only make sense on this system. It is left in rather than
# resolved: where it sits in the order is the thing worth checking.
def plugin-list []: nothing -> list<string> {
  zshrc
  | lines
  | skip until {|l| $l | str starts-with "plugins=(" }
  | take until {|l| ($l | str trim) == ")" }
  | each {|l| $l | str replace --regex '#.*$' '' | str trim }
  | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "plugins=(")) }
}

@test
export def "syntax highlighting is loaded last" [] {
  # zsh-syntax-highlighting wraps the line editor and must be the final plugin;
  # anything after it silently loses highlighting.
  assert equal (plugin-list | last) "zsh-syntax-highlighting"
}

@test
export def "the plugins for one system are not loaded on all of them" [] {
  # suse, systemd and firewalld define aliases for tools that do not exist on a
  # Mac, and brew and macos are equally pointless on Linux. They belong in the
  # os_plugins branch above the list; finding one in the list itself means it
  # loads everywhere.
  let listed = (plugin-list)

  assert ("$os_plugins" in $listed) "the per-system plugins are no longer spliced into the list"

  for name in ["suse" "systemd" "firewalld" "brew" "macos"] {
    assert ($name not-in $listed) $"($name) only applies to one of these systems, so it belongs in the os_plugins branch rather than the shared list"
  }
}

@test
export def "Homebrew reaches PATH before oh-my-zsh loads" [] {
  # Order, like the locale test below. Oh My Zsh sources the plugins chosen
  # above, and the brew plugin looks for its completions under HOMEBREW_PREFIX
  # -- which `brew shellenv` is what sets. Run it afterwards and the plugin
  # loads against an environment that does not mention Homebrew yet.
  let lines = (zshrc | lines)
  let shellenv = ($lines | enumerate | where {|r| $r.item =~ 'brew" shellenv' } | get index)
  let omz = ($lines | enumerate | where {|r| $r.item =~ 'source \$ZSH/oh-my-zsh\.sh' } | get index | first)

  assert ($shellenv | is-not-empty) "nothing in .zshrc puts Homebrew on PATH"
  assert (($shellenv | math max) < $omz) $"brew shellenv runs at ($shellenv) but oh-my-zsh loads at ($omz)"
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

@test
export def "the docker alias checks that docker actually runs" [] {
  # $+commands is true for any name zsh found on PATH, dangling symlink or not.
  # Uninstalling Docker Desktop leaves /usr/local/bin/docker pointing into an
  # /Applications entry that is gone, so a $+commands guard reads that as "a
  # real docker is installed" and skips the alias in favour of a command that
  # only ever answers "no such file or directory".
  let rc = (zshrc)
  let guard = ($rc | lines | where {|l| $l =~ 'commands\[docker\]' })

  assert ($guard | is-not-empty) "the docker alias is no longer guarded at all"
  for line in $guard {
    assert ($line =~ '-x ') $"($line | str trim) tests for the name rather than for something executable"
  }
}

@test
export def "every credential helper the gitconfig names is a tool this repo installs" [] {
  # The check that was missing. .gitconfig has named git-credential-manager as
  # the helper for dev.azure.com since long before anything installed it, so on
  # every machine this repo has ever set up, that line pointed at a command
  # that was not there -- and git says nothing about it until the first push to
  # Azure DevOps fails to authenticate.
  #
  # Helpers beginning with "!" are shell commands rather than executables to be
  # found on PATH -- `!gh auth git-credential` is gh, already on the list -- so
  # they are not name-checked here.
  let helpers = (open --raw ($REPO | path join "home" ".gitconfig")
    | lines
    | each {|l| $l | str trim }
    | where {|l| $l =~ '^helper\s*=' }
    | each {|l| $l | str replace --regex '^helper\s*=\s*' '' | str trim }
    | where {|h| ($h | is-not-empty) and (not ($h | str starts-with "!")) }
    | each {|h| $h | split row " " | first }
    | uniq)

  assert ($helpers | is-not-empty) "no credential helper is configured at all, which is a change worth noticing"

  for helper in $helpers {
    # An absolute path is its own failure, and a likely one: `git-credential-
    # manager configure`, which GCM's macOS installer runs for you, appends
    # `helper = /usr/local/share/gcm-core/git-credential-manager` to the global
    # config -- which here is this very file, by symlink. That path does not
    # exist on Linux, so committing it breaks every other machine quietly.
    assert not ($helper | str starts-with "/") $"($helper) is an absolute path, which only exists on the machine it was written on -- name the command and let PATH find it"

    assert ($helper in $common.PACKAGES) $"($helper) is configured as a credential helper but is not in packages/common.nu, so nothing installs it"
  }
}

@test
export def "the gitconfig includes the platform file" [] {
  # git has no condition for "which system is this", but it does ignore an
  # include whose file is absent -- so the file's existence is the condition,
  # and the links step decides it. Losing this line silently drops every
  # per-system git setting.
  let rc = (open --raw ($REPO | path join "home" ".gitconfig"))
  assert str contains $rc "~/.config/git/platform.conf" "nothing includes the platform file"

  # Last, so it overrides what came before. Anything after it would win over
  # the per-system settings, which is the opposite of the point.
  let lines = ($rc | lines | where {|l| ($l | str trim | is-not-empty) and (not ($l | str trim | str starts-with "#")) })
  assert str contains ($lines | last) "platform.conf" $"the include is not the last thing in .gitconfig; found: ($lines | last)"
}

@test
export def "every platform directory is a name that can match a machine" [] {
  # A typo here fails silently and completely: platform/darwin/ or
  # platform/osx/ would simply never be linked, and the settings in it would
  # never apply, with nothing on screen to say so.
  let dirs = (glob ($REPO | path join "platform" "*") --no-file
    | each {|d| $d | path basename })

  let matchable = ([
    { id: "opensuse-tumbleweed", family: "suse" }
    { id: "opensuse-leap", family: "suse" }
    { id: "fedora", family: "fedora" }
    { id: "ubuntu", family: "debian" }
    { id: "debian", family: "debian" }
    { id: "macos", family: "macos" }
  ] | each {|s| distro config-names $s } | flatten | uniq)

  for dir in $dirs {
    assert ($dir in $matchable) $"platform/($dir) matches no system this repo supports, so it would never be linked -- expected one of: ($matchable | str join ', ')"
  }
}

@test
export def "the font Rio asks for is the font this repo installs" [] {
  # The same trap as a credential helper naming a command nothing installs:
  # a font that happens to be on this machine would leave a fresh one falling
  # back to whatever the system picks, silently losing the glyph range the
  # tmux status separators are drawn from.
  #
  # Compared by family prefix, because a cask token and a font family are not
  # spelled alike -- font-meslo-lg-nerd-font installs "MesloLGS Nerd Font
  # Mono" and its siblings. Changing the cask without changing the config, or
  # the other way round, is what this catches.
  let rio = ($REPO | path join "home" ".config" "rio" "config.toml")
  if not ($rio | path exists) { return }

  let family = (open --raw $rio
    | lines
    | where {|l| $l =~ '^\s*family\s*=' }
    | each {|l| $l | str replace --regex '^\s*family\s*=\s*' '' | str trim | str trim --char '"' }
    | first)

  let cask = ($macos.CASKS | get nerd-fonts)
  let stem = ($cask
    | str replace --regex '^font-' ''
    | str replace --regex '-nerd-font$' ''
    | str replace --all '-' '')

  assert (($family | str downcase | str replace --all ' ' '') | str starts-with $stem) $"Rio asks for '($family)' but packages/macos.nu installs ($cask) -- one of the two moved without the other"
}
