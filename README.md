# dotfiles

Shell environment for openSUSE (Tumbleweed and Leap), Fedora, Ubuntu, macOS,
and Windows as a workstation.

```sh
git clone https://github.com/tibold/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

On Windows, from PowerShell:

```powershell
git clone https://github.com/tibold/dotfiles.git
cd dotfiles
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 --with claude
```

(unsigned scripts are blocked by default, so the first run needs
`-ExecutionPolicy Bypass`, which applies to that one process only; once
PowerShell is configured to allow local scripts, `.\bootstrap.ps1` works on
its own.)

A fresh Windows machine has no git: install it first with
`winget install --exact --id Git.Git` (and open a new terminal so it is on
PATH), or download the repository as a zip and run `bootstrap.ps1` from the
unpacked folder -- the packages step installs git either way.

`bootstrap.sh` and `bootstrap.ps1` install nushell and hand over to
`install.nu`, which does everything else. It is safe to re-run: every step
checks before it acts.

On macOS it installs Homebrew first, since that is the one platform where there
is no package manager to assume -- see [macOS](#macos) below. On Windows see
[Windows](#windows) below for what `bootstrap.ps1` does instead.

## Layout

```
bootstrap.sh      POSIX sh. Installs nushell, then runs install.nu.
bootstrap.ps1     Windows PowerShell 5.1 counterpart -- that is what a fresh
                  machine already has, before install.nu gets pwsh 7 onto it.
install.nu        The installer. Runs the steps in order.

home/             Mirrors $HOME. Every file here is linked to the same
                  relative path under ~, so home/.config/lazygit/config.yml
                  becomes ~/.config/lazygit/config.yml. There is no manifest;
                  adding a config means adding a file. Not linked on Windows
                  at all -- see "Windows".

platform/         The same mirror, per system. platform/macos/.config/... is
                  linked only on macOS, platform/windows/... only on Windows.
                  See "Per-system settings".

packages/         What to install. common.nu is one logical name per tool;
                  the others map those names onto each system.
lib/              system detection, package resolution, linking, the
                  upstream-release fallback, the step order and per-platform
                  applicability (steps.nu), and a Windows-only fix for paths
                  handed to nushell's glob (paths.nu). No side effects except
                  in apply.
steps/            The parts of an install: packages, nushell plugins,
                  cleanup, links, app config dirs, zsh, the pwsh profile
                  (Windows), Claude Code (opt-in), neovim, git hooks, macOS
                  defaults.
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
nu install.nu --with claude         # everything, plus the opt-in Claude Code step
nu install.nu --only claude         # just Claude Code
nu install.nu --only powershell     # just the pwsh profile stub (Windows only)
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
  nerd-fonts: "font-0xproto-nerd-font"    # installed with brew install --cask
}
```

A logical name in `CASKS` is answered by that and never looked up as a formula,
so it needs no override and no null.

## Nushell plugins

`from ini`, `query json` and `inc` are not built into nushell; each is
a separate `nu_plugin_*` executable that the shell ignores until it is written
into the per-user plugin registry. The list lives in `NUSHELL_PLUGINS` in
`packages/common.nu`. Tumbleweed installs them as `nushell-plugin_*` packages;
on Windows winget's `Nushell.Nushell` puts them beside `nu.exe`; everywhere
else they come out of the same upstream archive as `nu`. The `plugins` step
then registers whichever ones are installed, and every nu started after that
has them.

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

Windows has no container tests either, for a different reason -- see
[Windows](#windows).

## Applications that keep their config elsewhere

Everything here lives under `home/.config/<app>/`, so there is one place to
look. Some applications then read it from somewhere else, and they disagree
with each other about where:

```
lazygit   ~/.config on Linux, ~/Library/Application Support on macOS,
          %LOCALAPPDATA% on Windows
nushell   the same split on macOS, for the same reason: both follow the
          platform's own convention; %APPDATA% on Windows, not %LOCALAPPDATA%
rio       ~/.config even on macOS, ignoring the convention above, and
          %LOCALAPPDATA% on Windows
git       ~/.gitconfig everywhere, Windows included -- the one entry here
          that names a file rather than a directory
```

`steps/appdirs.nu` lists the ones that deviate and links the config a second
time, into the directory that application actually opens. The copy under
`~/.config` stays, so configs remain findable in one place.

One more entry exists for a different reason: Windows does not mirror `home/`
at all (see [Windows](#windows)), so a `tmux-themes` entry links
`~/.config/tmux/themes` back to the same place it already sits, purely to get
the files onto a Windows machine at all -- `psmux`, tmux's Windows stand-in,
reads them from there unchanged.

Files, never the whole directory: applications keep state next to their config
-- lazygit writes `github_pull_requests.json` there, nushell its history and
plugin registry -- and linking the directory would drag all of it in here.

## Per-system settings

`home/` is linked everywhere except Windows, which does not mirror it at all
-- see [Windows](#windows). `platform/<name>/` is the same mirror, linked only
where `<name>` matches the machine, Windows included:

```
platform/macos/.config/git/platform.conf     ->  ~/.config/git/platform.conf, on macOS only
platform/windows/.config/git/platform.conf   ->  ~/.config/git/platform.conf, on Windows only
platform/linux/...                               on any Linux distribution
platform/debian/...                              on Debian and Ubuntu
platform/ubuntu/...                              on Ubuntu alone
```

Three names can match, and they are linked from broad to exact -- the
operating system, then the package manager family, then the distribution -- so
a file in `platform/ubuntu/` wins over the same path in `platform/debian/`.
On macOS all three names are `macos`, and on Windows all three are `windows`,
which each collapse to one.

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

Windows has the Credential Manager, so `platform/windows/` does the same with
`wincred`:

```gitconfig
[credential "https://dev.azure.com"]
	credentialStore = wincred
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

The font is 0xProto (`font-0xproto-nerd-font`), picked by eye in Rio after
Meslo -- Oh My Zsh's default, and this repo's first choice -- read poorly at
terminal sizes. Windows installs the same family, and Rio's config names it;
`tests/unit/configs.nu` fails if the three drift apart. Any other Nerd Font is
a one-word change in each.

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

## Windows

Windows is the third platform here, after Linux and macOS, and the odd one
out: it is a workstation, like macOS, but has no zsh, no Oh My Zsh and no tmux
to inherit. Their roles are taken by pwsh, oh-my-posh and psmux instead,
configured separately in `platform/windows/` rather than adapted from the Unix
originals. Windows PowerShell 5.1 -- whatever a fresh machine already has --
is used for exactly one thing, `bootstrap.ps1`; everything after that,
`install.nu` and the pwsh profile it sets up, runs in nushell and pwsh 7.

On a fresh machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 --with claude
```

Unsigned scripts are blocked by default, so the first run needs
`-ExecutionPolicy Bypass`, which applies to that one process only; once
PowerShell is configured to allow local scripts, `.\bootstrap.ps1` works on
its own. `bootstrap.ps1`:

1. checks Developer Mode
   (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`), which is
   what lets it create symlinks without admin rights, and stops with
   instructions if it is off and `--copy` was not passed -- turn Developer
   Mode on, or run with `--copy` and get files instead of links;
2. looks for `nu` on PATH, then at its known install location
   (`%LOCALAPPDATA%\Programs\nu\bin\nu.exe`), and only installs it with winget
   if neither has it -- then checks that known location again, since winget
   does not update the current session's PATH;
3. runs `install.nu`, passing every argument through -- `--with claude` above
   reaches it this way.

It does not install git: having the repo already implies git or a zip, and the
packages step installs (or confirms) git right after.

### What comes from where

Packages come from winget, one exact id at a time
(`winget install --exact --id <id> --source winget ...`), skipped when
`winget list --exact --id <id>` already finds it. Unlike the Linux and macOS
transactions, this is not all-or-nothing: a failing id warns and the rest keep
installing, since one publisher's installer refusing is no reason to leave
twenty other tools uninstalled. UAC prompts from individual installers are not
suppressed.

Most of `packages/windows.nu` is a straight logical-name-to-winget-id mapping,
but a few tools are Windows equivalents living under a Linux/macOS name rather
than the same tool:

```
tmux     marlocarlo.psmux   ships tmux.exe
htop     marlocarlo.pstop   ships htop.exe
gcc      LLVM.LLVM          the C compiler nvim-treesitter's parser builds find
nodejs   Schniz.fnm         Node arrives through fnm, not a winget id of its own
```

fnm is the one with a step of its own: once it is installed, `fnm default`
says whether an LTS is already the default, and only if none exists does the
step run `fnm install --lts` and `fnm default lts-latest` -- an existing
default is left alone. Global npm packages install through
`fnm exec --using default -- npm.cmd install --global <pkgs>` -- `npm.cmd`
because fnm exec cannot spawn `npm` by its bare name on Windows, and no sudo:
fnm's prefix belongs to the user.

The Nerd Font is winget's counterpart to Homebrew's `CASKS` -- `FONTS` in
`packages/windows.nu` -- installed with
`oh-my-posh font install 0xProto --headless` and skipped when a 0xProto Nerd
Font is already in the user or system font directory. Installed for the same
reason macOS installs its cask: the terminal is on this machine, not something
reached over ssh, so the font belongs here.

As on macOS, some tools are already there -- `curl` and `tar` (both ship with
Windows), `git-credential-manager` (bundled with Git for Windows), `npm`
(comes with the node fnm installs), the nushell plugins (`nu_plugin_*.exe`
ship beside `nu.exe` in winget's Nushell package) -- and some are deliberately absent: `zsh`
(pwsh takes its role), `terminfo-extra` (no terminfo database on a Windows
console), `diffutils` (git bundles diff, rendered by delta), `make`,
`mkisofs`, `podman-docker` (the pwsh profile aliases `docker` to `podman` when
there is no real docker), `neovim-python` (no packaged `pynvim`), and `pipx`
(its only application, tmuxp, drives tmux and has nothing to drive here).

### Linking

`home/` is not mirrored on Windows at all -- most of it is zsh, tmux and POSIX
shell configuration with nothing on Windows to read it, and mirroring it
anyway would just mean a pile of dead files. What Windows does need arrives
through [`steps/appdirs.nu`](#applications-that-keep-their-config-elsewhere),
one named application at a time: lazygit and rio into `%LOCALAPPDATA%`,
nushell into `%APPDATA%`, the tmux theme files into their ordinary
`~/.config/tmux/themes` (psmux reads them from there directly), and
`~/.gitconfig` as the one entry that links a single file rather than a
directory. `tests/unit/appdirs.nu` fails for any `home/.config/<app>/` that is
not in `PLACES` for Windows and not named, with a reason, in `NOT_ON_WINDOWS`
-- currently just `tmux`, whose own config directory has no Windows reader at
all, only its themes -- so a new config added under `home/.config/` cannot
silently miss Windows.

`platform/windows/` is linked like any other platform directory (see
[Per-system settings](#per-system-settings)): `.psmux.conf`,
`.config/powershell/profile.ps1`,
`.config/oh-my-posh/archpillar-cyberpunk.omp.toml` and
`.config/git/platform.conf`.

pwsh reads `$PROFILE` from a fixed path under Documents, which OneDrive may
have redirected into a synced, organisation-named folder -- not somewhere a
symlink belongs, and not machine-independent either. So the `powershell` step
writes a one-line stub there instead:

```powershell
# Managed by dotfiles (nu install.nu --only powershell). Edit ~/.config/powershell/profile.ps1 instead.
. (Join-Path $HOME '.config/powershell/profile.ps1')
```

which loads the linked `platform/windows/.config/powershell/profile.ps1`.
Anything else already at `$PROFILE` is moved to `~/.dotfiles-backup/` first;
if it is already the stub, the step does nothing. The profile itself
dot-sources `~/.config/powershell/local.ps1` last, if it exists --
machine-specific PowerShell (an MSVC `PATH`, a Chocolatey profile, whatever
this machine needs) that, like the git file below, never enters the repo.

git also reads `~/.config/git/config`, alongside `~/.gitconfig`, and the repo
does not manage it -- the same trick [Per-system settings](#per-system-settings)
uses for `platform/windows/.config/git/platform.conf`, but for settings that
belong to one machine rather than to every Windows machine.

### Shell: pwsh, oh-my-posh, psmux

`platform/windows/.psmux.conf` deliberately mirrors `home/.tmux.conf` --
change a binding in one, change it in the other, and the file says so at the
top. It carries over the same bindings, mouse and clipboard behaviour, focus
events, status line, pane borders and message style, and drops what has no
Windows use: the terminfo and clipboard `if-shell` blocks, the cpu/mem/swap
status segment (`tmux-status` is a POSIX script), and the `default-shell`
line, since psmux starts pwsh by default. Its one real difference from
`.tmux.conf` is `set -sg escape-time 10`, needed so a lone Escape reaches nvim
immediately instead of waiting to see whether it is the start of an escape
sequence -- carried over from this machine's previous config and kept
Windows-only, since nothing asked for that change on Linux.

`platform/windows/.config/oh-my-posh/archpillar-cyberpunk.omp.toml` recolours
a powerlevel10k-style layout with the same ArchPillar tokens the tmux theme
names, so the pwsh prompt, the psmux status line and Rio agree. It is TOML
rather than JSON, which oh-my-posh reads equally well, so that every colour
can carry a comment naming the token it came from, the same convention the
tmux theme files use -- `tests/unit/configs.nu` fails on a colour that is
neither in that theme nor one of the documented `--danger`/`--warning`
tokens. If the prompt looks stale after changing the theme, oh-my-posh caches
its config on some machines -- `oh-my-posh cache clear` fixes it.

### Testing

The unit tests run natively on Windows, the same `nu tests/run.nu` as
anywhere else, from Git Bash or from a plain pwsh with none of Git's Unix
tools on PATH -- the suite needs nothing but nushell itself.

There is no disposable Windows equivalent of the container tests yet. Unlike
macOS, one is possible in principle -- Windows Sandbox -- it is just not wired
up here. `.\bootstrap.ps1 --dry-run`, reviewed by hand, then a real run, then a
second run reporting everything already done, is the closest rehearsal
available -- the same role `--dry-run` plays for `brew install` on macOS. Its
output now quotes any argument that needs it, POSIX-style, so what it prints
can be pasted straight into a POSIX shell such as Git Bash -- not into
PowerShell, whose quoting rules differ.

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

Windows has no zsh to carry a prompt at all, so oh-my-posh takes that role
instead of the Oh My Zsh theme, and psmux's status line replaces tmux's -- both
reading the same ArchPillar theme files as here. See [Windows](#windows).

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
nu tools/gdm.nu                # GNOME settings with no switch in Settings
nu tools/gdm.nu apply          # apply this session's policy (autostart)
```

To install Claude Code, use `nu install.nu --with claude` or `nu install.nu --only claude` instead.
