# dotfiles

Shell environment for openSUSE (Tumbleweed and Leap), Fedora, Ubuntu and macOS.

```sh
git clone https://github.com/tibold/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` installs nushell and hands over to `install.nu`, which does
everything else. It is safe to re-run: every step checks before it acts.

On macOS it installs Homebrew first, since that is the one platform where there
is no package manager to assume -- see [macOS](#macos) below.

## Layout

```
bootstrap.sh      POSIX sh. Installs nushell, then runs install.nu.
install.nu        The installer. Runs the steps in order.

home/             Mirrors $HOME. Every file here is linked to the same
                  relative path under ~, so home/.config/lazygit/config.yml
                  becomes ~/.config/lazygit/config.yml. There is no manifest;
                  adding a config means adding a file.

platform/         The same mirror, per system. platform/macos/.config/... is
                  linked only on macOS. See "Per-system settings".

packages/         What to install. common.nu is one logical name per tool;
                  the others map those names onto each system.
lib/              system detection, package resolution, linking, and the
                  upstream-release fallback. No side effects except in apply.
steps/            The parts of an install: packages, nushell plugins,
                  cleanup, links, app config dirs, zsh, neovim, git hooks,
                  macOS defaults.
tools/            Standalone utilities, not run by the installer. These are
                  Linux-only; they configure GDM, KVM, WireGuard and RKE2.
githooks/         Enabled via core.hooksPath; currently a gitleaks scan.
tests/            unit tests (fast) and container tests (slow, real).
```

## Usage

```sh
nu install.nu                       # everything
nu install.nu --dry-run             # show what would happen, change nothing
nu install.nu --only links          # one step
nu install.nu --only cleanup        # just the package removals
nu install.nu --only packages,links
nu install.nu --copy                # copy files instead of linking them
nu install.nu --only macos          # just the macOS system defaults
```

Symlinks are the default so that edits made in `~` land in the repo and
`git status` shows the drift. `--copy` is for the cases where that is wrong: a
tool that rewrites its own config in place, or a machine where the checkout
should not be load-bearing.

Anything displaced by a first install is kept in `~/.dotfiles-backup/`, not
overwritten.

Dropping a file from `home/` leaves a dead symlink in `$HOME`, so the link step
also prunes those. It removes a link only if it points inside this repository
*and* its target is gone -- a real file, a link that still resolves, and a link
to anywhere else are all left alone.

## Removing a tool

`install.nu` also uninstalls packages this repo used to install and no longer
wants -- the `REMOVED` list in each overlay. That step is built to be dull:

- only names written in a `REMOVED` list are ever passed to the package
  manager, and nothing is inferred from "looks unused";
- a package that another installed package still requires is kept, and the
  step says which package is holding it;
- a name cannot be on both the install and the removed list -- the unit tests
  fail if that ever becomes true, and the step protects the install list again
  at run time;
- no `--clean-deps`, `--autoremove` or `--purge` anywhere, so the transaction
  never widens past what was listed.

Use `--dry-run` to see the exact command before it runs.

## Adding a tool

Add its logical name to `packages/common.nu`. If every distribution calls it
that, you are done. Otherwise add an entry to the overlay that disagrees:

```nu
# packages/debian.nu
export const OVERRIDES = {
  mkisofs: "xorriso"                        # different name here
  powerline: ["powerline" "fonts-powerline"] # several packages here
  lazygit: null                              # not packaged here
}
```

`null` means the system cannot supply it under that name, and then it must be
accounted for one of these ways:

- add it to `lib/fallback.nu` to fetch the binary from its upstream release, or
- add it to that overlay's `PROVIDED` with a reason, if the base system already
  has it, or
- add it to that overlay's `OMITTED` with a reason, if we are choosing to do
  without it there.

`tests/unit/packages.nu` fails if a tool is nulled and none of those applies, so
a tool cannot quietly disappear from one system's environment.

`PROVIDED` and `OMITTED` are not the same claim and the tests hold them apart.
"Homebrew does not package zsh for you because macOS already did" and "there is
no Nerd Font in Debian's archive and we have decided to live without one" would
both be a missing package if the only bucket were `OMITTED`, and only one of
them is something to go and fix.

macOS has a fourth mapping, because Homebrew has two halves:

```nu
# packages/macos.nu
export const CASKS = {
  nerd-fonts: "font-meslo-lg-nerd-font"   # installed with brew install --cask
}
```

A logical name in `CASKS` is answered by that and never looked up as a formula,
so it needs no override and no null.

## Nushell plugins

`from ini`, `query json` and `inc` are not built into nushell; each is
a separate `nu_plugin_*` executable that the shell ignores until it is written
into the per-user plugin registry. The list lives in `NUSHELL_PLUGINS` in
`packages/common.nu`. Tumbleweed installs them as `nushell-plugin_*` packages;
everywhere else they come out of the same upstream archive as `nu`. The
`plugins` step then registers whichever ones are installed, and every nu
started after that has them.

`polars` is left out on purpose -- a 120 MB binary for a dataframe library
nothing here uses. Adding a plugin is one line in that list; the openSUSE
override and the fallback entry restate it, and `tests/unit/plugins.nu` fails
until all three agree.

The plugin only reads ini; nushell has no `to ini` at all. One lives in
`home/.config/nushell/scripts/ini.nu`, and `autoload/formats.nu` next to it
loads it into every interactive nu. A script gets it with `use ini.nu *`.

## Tests

```sh
nu tests/run.nu                     # unit tests, seconds
nu tests/container/run.nu           # full install per distro, minutes
nu tests/container/run.nu --distro fedora
```

To try the environment by hand rather than assert about it:

```sh
nu tests/container/try.nu                  # install into a container, land in zsh
nu tests/container/try.nu --distro ubuntu
nu tests/container/try.nu --shell nu
nu tests/container/try.nu --rebuild        # after changing the repo
```

The first run installs and takes a few minutes, then snapshots the result, so
later runs start in about a second. Nothing you do inside survives leaving the
shell -- the container is discarded on exit and the snapshot is rebuilt from
the repo, never from your session.

The unit tests check the logic: os-release parsing, package resolution, the
link plan, and that the configs and the code that installs them agree. They
cannot tell you whether a package name is real.

The container tests can. Each builds an image with nothing but `sudo` and a
user, runs `bootstrap.sh` inside it, and then checks that the links landed,
the expected commands are on `PATH`, and an interactive zsh and bash both
start cleanly. That is what catches a package that was renamed, or that never
existed on Leap in the first place.

There is no macOS equivalent and there cannot be: macOS does not run in a
container, and a disposable one is the whole point of that layer. So the mapping
in `packages/macos.nu` is checked by the unit tests for internal consistency and
by running the installer on a real Mac for everything else. `--dry-run` prints
the exact `brew install` line without touching anything, which is the closest
thing to a rehearsal available here.

## Applications that keep their config elsewhere

Everything here lives under `home/.config/<app>/`, so there is one place to
look. Some applications then read it from somewhere else, and they disagree
with each other about where:

```
lazygit   ~/.config on Linux, ~/Library/Application Support on macOS
nushell   the same split
rio       ~/.config even on macOS, %LOCALAPPDATA% on Windows
git       ~/.gitconfig everywhere, Windows included
```

`steps/appdirs.nu` lists the ones that deviate and links the config a second
time, into the directory that application actually opens. The copy under
`~/.config` stays, so configs remain findable in one place.

Files, never the whole directory: applications keep state next to their config
-- lazygit writes `github_pull_requests.json` there, nushell its history and
plugin registry -- and linking the directory would drag all of it in here.

## Per-system settings

`home/` is linked everywhere. `platform/<name>/` is the same mirror, linked
only where `<name>` matches the machine:

```
platform/macos/.config/git/platform.conf   ->  ~/.config/git/platform.conf, on macOS only
platform/linux/...                             on anything that is not macOS
platform/debian/...                            on Debian and Ubuntu
platform/ubuntu/...                            on Ubuntu alone
```

Three names can match, and they are linked from broad to exact -- the
operating system, then the package manager family, then the distribution -- so
a file in `platform/ubuntu/` wins over the same path in `platform/debian/`.
On macOS all three names are `macos`, which collapses to one.

It is the same code as `home/`, pointed at a different directory: there are no
rules of its own to learn, and `--dry-run`, the backups and the dead-link
pruning all behave identically. Linking is one step rather than two because
pruning has to see every link this repo owns at once; done per directory, each
pass would tidy away the others.

This exists for the file formats that have no condition of their own. git is
the case in hand: `includeIf` can ask about a directory, a branch or a remote,
but not about which machine it is running on. What it does have is that an
`[include]` naming a file that does not exist is silently ignored -- so the
file's existence becomes the condition, and this step is what decides it:

```gitconfig
# home/.gitconfig, last so it overrides what is above
[include]
	path = ~/.config/git/platform.conf
```

The first use is the credential store. `home/.gitconfig` asks for `plaintext`,
which is the honest answer on a headless Linux box -- there is no secret
service to talk to, and the credentials go to `~/.gcm/store` unencrypted.
macOS has the Keychain, so `platform/macos/` puts it back:

```gitconfig
[credential "https://dev.azure.com"]
	credentialStore = keychain
```

A misspelled directory -- `platform/darwin/`, say -- would link nothing and
say nothing, so `tests/unit/configs.nu` fails on any name that cannot match a
system this repo supports.

## macOS

macOS is the only target here that is a workstation rather than something
reached over ssh, and the overlay reflects that: the Nerd Font is installed
because the terminal is on this machine, and nothing is fetched from a GitHub
release because Homebrew carries every tool in `packages/common.nu`.

It is also the only platform where `bootstrap.sh` has to supply the package
manager instead of assuming it. On a fresh Mac it:

1. checks for the Command Line Tools, which is where `git` and the compiler
   come from, and stops with an instruction if they are not installed -- that
   installer is a GUI dialog and there is nothing useful to wait for;
2. installs Homebrew if `brew` is not on PATH, which will ask for your password
   because it creates its prefix under `/opt`;
3. runs `brew shellenv`, since Homebrew's own installer only prints that line
   and leaves you to put it somewhere. `home/.zshrc` and `home/.profile` do the
   same for every later shell;
4. installs nushell and hands over to `install.nu` as everywhere else.

Run it as yourself. Homebrew refuses to run as root, so `bootstrap.sh` stops
early rather than getting half way and being turned away by `brew install`.

### What comes from where

Most of `common.nu` is a formula. Three groups are not:

- **a cask** -- the Nerd Font, installed with `brew install --cask`;
- **already in the base system** -- zsh, curl, tar, make, the compiler,
  diffutils, the terminfo database, and npm (which arrives with the `node`
  formula). These are in `PROVIDED` with the reason, and the install prints one
  line each rather than passing over them in silence. Installing Homebrew's
  version of any of them would mean a second copy that either shadows the
  system one or, being keg-only, is not even on PATH;
- **deliberately absent** -- `neovim-python`, because there is no `pynvim`
  formula and Homebrew's python is PEP 668 managed, and `podman-docker`, which
  has no macOS equivalent. `.zshrc` aliases `docker` to `podman` instead, but
  only when podman is installed and no real docker is.

`podman` itself installs, but a container needs a Linux kernel to run in:
`podman machine init` once, then `podman machine start`. That is left to you
rather than done by the installer, because it downloads and boots a VM.

The font is `font-meslo-lg-nerd-font` **pending a visual review** -- it is what
Oh My Zsh's documentation assumes and what the `jonathan` theme and the tmux
status separators were drawn against, so it is the safe default rather than a
considered preference. `font-jetbrains-mono-nerd-font` and
`font-hack-nerd-font` are one-word changes in `packages/macos.nu`.

`lib/fallback.nu` stays Linux-only, and refuses to run anywhere else rather
than quietly unpacking an ELF binary into `~/.local/bin`. If a future Homebrew
drops one of these formulae, the answer is a `PROVIDED` or `OMITTED` entry, or
a macOS asset table -- not the existing one.

### System defaults

`install.nu --only macos` applies the settings in `steps/macos.nu`: key repeat
that actually repeats (macOS opens the accent picker instead, which is a
surprise the first time you hold `j` in neovim), no smart quotes or em dashes,
Finder showing extensions and the path bar, screenshots as png in
`~/Screenshots`, and a Dock that stops appending recent applications.

What it will not do is change how the machine looks. There is nothing about
appearance, wallpaper, accent colour, or the Dock's position, size or autohide;
`tests/unit/macos.nu` names those keys and fails if one appears. Nothing here
uses sudo or writes outside this user's own preference domains.

It reads before it writes, so a second run reports every setting as already
applied and restarts nothing. Only the applications whose domain actually
changed are restarted -- Finder, the Dock or SystemUIServer -- because a
preference is read at launch and a running Finder would otherwise go on showing
the old value. The keyboard settings live in `NSGlobalDomain`, which every
application reads as it starts, so those reach an already-running application
at its next launch.

This step only runs on macOS. Asking for it by name anywhere else says so
rather than failing.

## Prompt and status line

The prompt is Oh My Zsh's `jonathan` theme. zsh is the only shell anyone types
into here -- bash and nushell are for scripts -- so there is nothing for a
cross-shell prompt to buy.

starship was tried in this role and removed. It is the right answer when you
use several interactive shells, because it gives them all one prompt; against
that, it is packaged on Tumbleweed alone, so Leap, Fedora and Ubuntu each meant
fetching and re-fetching an upstream binary to draw a prompt Oh My Zsh already
draws.

powerline is gone from both jobs it used to do. The prompt is the omz theme
above; the tmux status line is now drawn by tmux's own formats, with no python
daemon starting up behind every new session.

Status line colours come from the ArchPillar design system, not from anything
invented here: `~/.config/tmux/themes/` holds one file per theme it defines
(cyberpunk, professional, modern), each naming the token every value came from.
`tmux-theme` lists them and applies one to a running server; the `source-file`
line in `.tmux.conf` picks the default.

They are the design system's exact hex. tmux approximates them itself where
true colour is unavailable, which beats approximating for everyone -- xterm's
24 greys are strictly neutral, so pre-converting flattens every blue-tinted
neutral in that palette to plain grey.

The status line separators need a Nerd Font in the terminal you are looking at.
Installing fonts on a machine you ssh into does nothing for them, which is why
`nerd-fonts` is omitted on the distributions that do not package it rather than
fetched. macOS is where that rule points the other way -- it is the machine you
are looking at -- so there the font is installed, as a cask.

## Secret scanning

`githooks/pre-commit` runs `gitleaks` over staged changes and blocks the commit
on a hit. It is enabled by `install.nu` setting `core.hooksPath`, so it arrives
with a clone rather than needing a separate install.

It fails closed: if `gitleaks` is missing the commit is refused, because a
scanner that quietly does nothing is worse than none. For a false positive,
prefer a `gitleaks:allow` comment on the line or an entry in `.gitleaksignore`
over `--no-verify`; the first two leave a record.

## Tools

Not part of the install; run them when you want them. All of these are
Linux-only -- the macOS equivalent of `gdm.nu`, the settings with no switch
worth clicking twice, is a step rather than a tool. See
[System defaults](#system-defaults).

```sh
nu tools/install-claude.nu     # Claude Code, for this user
nu tools/gdm.nu                # GNOME settings with no switch in Settings
nu tools/gdm.nu apply          # apply this session's policy (autostart)
```
