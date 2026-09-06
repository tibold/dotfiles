# dotfiles

Shell environment for openSUSE (Tumbleweed and Leap), Fedora and Ubuntu.

```sh
git clone https://github.com/tibold/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` installs nushell and hands over to `install.nu`, which does
everything else. It is safe to re-run: every step checks before it acts.

## Layout

```
bootstrap.sh      POSIX sh. Installs nushell, then runs install.nu.
install.nu        The installer. Runs the steps in order.

home/             Mirrors $HOME. Every file here is linked to the same
                  relative path under ~, so home/.config/lazygit/config.yml
                  becomes ~/.config/lazygit/config.yml. There is no manifest;
                  adding a config means adding a file.

packages/         What to install. common.nu is one logical name per tool;
                  the others map those names onto each distribution.
lib/              distro detection, package resolution, linking, and the
                  upstream-release fallback. No side effects except in apply.
steps/            The parts of an install: packages, nushell plugins,
                  cleanup, links, zsh, neovim, git hooks.
tools/            Standalone utilities, not run by the installer.
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

`null` means the distribution cannot supply it, and then it must be accounted
for one of two ways:

- add it to `lib/fallback.nu` to fetch the binary from its upstream release, or
- add it to that overlay's `OMITTED` with a reason, if we are choosing to do
  without it there.

`tests/unit/packages.nu` fails if a tool is nulled and neither applies, so a
tool cannot quietly disappear from one distribution's environment.

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
fetched.

## Secret scanning

`githooks/pre-commit` runs `gitleaks` over staged changes and blocks the commit
on a hit. It is enabled by `install.nu` setting `core.hooksPath`, so it arrives
with a clone rather than needing a separate install.

It fails closed: if `gitleaks` is missing the commit is refused, because a
scanner that quietly does nothing is worse than none. For a false positive,
prefer a `gitleaks:allow` comment on the line or an entry in `.gitleaksignore`
over `--no-verify`; the first two leave a record.

## Tools

Not part of the install; run them when you want them.

```sh
nu tools/install-claude.nu     # Claude Code, for this user
nu tools/gdm.nu                # GNOME settings with no switch in Settings
nu tools/gdm.nu apply          # apply this session's policy (autostart)
```
