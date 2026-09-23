# The neovim configuration, which lives in its own repository.

use ../lib/log.nu
use ../lib/links.nu

# Public, so a plain https clone works everywhere with no credentials. This
# used to choose between https and ssh depending on whether gh or an ssh agent
# could authenticate; making the repository public removed the reason for that
# entirely.
const REPO = "https://github.com/tibold/astrovim-init.git"

export const MARKETPLACE = "tibold-nvim"
export const PLUGIN = "nvim@tibold-nvim"

# Where neovim reads its config. XDG everywhere but Windows, where it is
# %LOCALAPPDATA%\nvim.
export def destination [home: path, family: string]: nothing -> path {
  if $family == "windows" { $home | path join "AppData" "Local" "nvim" } else { $home | path join ".config" "nvim" }
}

# The neovim config is also a Claude Code plugin marketplace -- claude/ inside
# it drives the running editor. Registered from the checkout itself, so a pull
# is all an update needs. A marketplace of the same name pointing anywhere else
# is someone's deliberate setup and is left alone, as clone-or-update leaves an
# unfamiliar checkout alone.
#
# Compared with links is-inside rather than string equality: claude reports
# the path back however the platform's tooling happened to spell it (drive
# letter case, backslash vs forward slash on Windows), and a real match
# spelled differently must not read as "elsewhere" forever. Checked both
# directions so a genuine subdirectory relationship -- which is not this --
# does not pass as equal.
export def marketplace-action [marketplaces: list, dest: path]: nothing -> string {
  let found = ($marketplaces | where name == $MARKETPLACE)
  if ($found | is-empty) { return "add" }
  let m = ($found | first)
  let path = ($m.path? | default "")
  if (
    $m.source == "directory"
    and ($path | is-not-empty)
    and (links is-inside $path $dest)
    and (links is-inside $dest $path)
  ) { "ok" } else { "elsewhere" }
}

export def plugin-action [plugins: list, pulled: bool]: nothing -> string {
  if ($plugins | where id == $PLUGIN | is-empty) { "install" } else if $pulled { "update" } else { "ok" }
}

# Clone unless it is already there, and refuse to touch a directory that holds
# something else. Silently pulling over an unrelated checkout, or over someone's
# hand-written config, would be worse than stopping.
export def clone-or-update [
  url: string
  dest: path
  --backup-root: path   # where a displaced lazy-lock.json is kept
  --dry-run
]: nothing -> record<changed: bool> {
  if not ($dest | path exists) {
    if $dry_run {
      log info $"would clone ($url) into ($dest)"
      return { changed: false }
    } else {
      log shell ["git" "clone" $url $dest]
      log ok $dest
      return { changed: true }
    }
  }

  if not ($dest | path join ".git" | path exists) {
    log warn $"($dest) exists but is not a git repository -- leaving it alone"
    return { changed: false }
  }

  let origin = (do { ^git -C $dest remote get-url origin } | complete)
  let existing = ($origin.stdout | str trim)

  if $origin.exit_code != 0 or $existing != $url {
    log warn $"($dest) points at ($existing), not ($url) -- leaving it alone"
    return { changed: false }
  }

  if $dry_run {
    log info $"would pull ($dest)"
    return { changed: false }
  }

  let before = (do { ^git -C $dest rev-parse HEAD } | complete | get stdout | str trim)

  # Local changes, sorted out before the pull rather than letting it refuse.
  #
  # lazy.nvim rewrites lazy-lock.json on every plugin update, so the checkout
  # almost always has it modified, and a pull that also changes it used to stop
  # the whole step. The lock file is generated: when the incoming commits touch
  # it, the repository's version wins and the local one is kept in the backup.
  # Anything else modified is somebody's edit. If the pull would change one of
  # those files, nothing happens and the step says which; otherwise --autostash
  # carries them across the pull, and they apply back cleanly because the pull
  # touched none of them.
  let fetched = (do { ^git -C $dest fetch --quiet } | complete)
  let upstream = (do { ^git -C $dest rev-parse --verify --quiet "@{upstream}" } | complete)
  if $fetched.exit_code == 0 and $upstream.exit_code == 0 {
    let incoming = (^git -C $dest diff --name-only HEAD "@{upstream}" | lines)
    let modified = (^git -C $dest status --porcelain --untracked-files=no
      | lines
      | each {|l| $l | str substring 3.. | str trim --char '"' })

    let clashing = ($modified | where {|p| $p != "lazy-lock.json" and $p in $incoming })
    if ($clashing | is-not-empty) {
      log warn $"($dest) has local edits the pull would overwrite -- leaving it exactly as it is"
      for p in $clashing { log info $p }
      log info "commit or discard them there, then: nu install.nu --only neovim"
      return { changed: false }
    }

    if ("lazy-lock.json" in $modified) and ("lazy-lock.json" in $incoming) {
      let stamp = (date now | format date "%Y%m%d-%H%M%S")
      let saved = ($backup_root | path join $stamp "lazy-lock.json")
      mkdir ($saved | path dirname)
      cp ($dest | path join "lazy-lock.json") $saved
      ^git -C $dest checkout --quiet -- lazy-lock.json
      log warn $"local lazy-lock.json replaced by the repository's; kept in ($saved)"
    }
  }

  # A pull that cannot fast-forward is reported and left alone -- not forced,
  # and not fatal.
  #
  # --ff-only already refuses to invent a merge commit; what this adds is that
  # its refusal no longer takes the whole install with it. There are two ways
  # to arrive here, a local commit in the config or an upstream that was
  # force-pushed, and both are somebody's work. Resolving either means looking
  # at the checkout, which is a thing to do deliberately rather than something
  # an installer should decide halfway through.
  #
  # It matters more than it looks because of where this step sits: the git
  # hooks are installed after it, so an unmergeable neovim config used to mean
  # a repository left with no secret scanning and nothing on screen saying why.
  let result = (do { ^git -C $dest pull --ff-only --autostash } | complete)

  if $result.exit_code == 0 {
    log ok $"($dest) up to date"
    let after = (do { ^git -C $dest rev-parse HEAD } | complete | get stdout | str trim)
    return { changed: ($before != $after) }
  }

  log warn $"($dest) cannot be fast-forwarded -- leaving it exactly as it is"
  # git's hints are addressed to someone standing in that repository, and this
  # is not that. The reason is worth repeating; the suggestions are not.
  for line in ($result.stderr
    | lines
    | where {|l| ($l | str trim | is-not-empty) and (not ($l | str starts-with "hint:")) }) {
    log info $line
  }
  log info "sort it out there, then: nu install.nu --only neovim"
  { changed: false }
}

# Registers the neovim config as a Claude Code plugin marketplace, and
# installs or updates the plugin it carries. Only possible once Claude Code
# itself is on PATH -- see steps/claude.nu, which runs first for that reason.
def register-plugin [dest: path, changed: bool, --dry-run]: nothing -> nothing {
  if (which claude | is-empty) {
    log skipped "Claude plugin: claude is not installed (nu install.nu --with claude)"
    return
  }
  # Failures warn and carry on: the hooks step runs after this one, and a
  # plugin that could not be registered is no reason to leave the repository
  # without its secret scan.
  try {
    let markets = (^claude plugin marketplace list --json | from json)
    match (marketplace-action $markets $dest) {
      "add" => (log shell ["claude" "plugin" "marketplace" "add" $dest] --dry-run=$dry_run)
      "elsewhere" => { log warn $"a marketplace named ($MARKETPLACE) already exists and is not ($dest) -- leaving it alone"; return }
      _ => { log skipped $"($MARKETPLACE) marketplace already registered" }
    }
    let plugins = (^claude plugin list --json | from json)
    match (plugin-action $plugins $changed) {
      "install" => (log shell ["claude" "plugin" "install" $PLUGIN "--scope" "user"] --dry-run=$dry_run)
      "update" => {
        log shell ["claude" "plugin" "marketplace" "update" $MARKETPLACE] --dry-run=$dry_run
        log shell ["claude" "plugin" "update" $PLUGIN] --dry-run=$dry_run
      }
      _ => { log skipped $"($PLUGIN) already installed" }
    }
  } catch {|e|
    log warn $"could not register the Claude plugin: ($e.msg)"
  }
}

export def install [
  family: string
  --home: path
  --repo: string = $REPO   # overridable so a test can point at a local clone
  --dry-run
]: nothing -> nothing {
  log step "Neovim configuration"
  let dest = (destination $home $family)
  let result = (clone-or-update $repo $dest --backup-root ($home | path join ".dotfiles-backup" "nvim") --dry-run=$dry_run)
  register-plugin $dest $result.changed --dry-run=$dry_run
  log info "neovim installs its plugins on first start"
  # Worth saying, because the first run looks broken and is not.
  #
  # AstroNvim 6's nvim-treesitter builds each parser from source with the
  # tree-sitter CLI, and Mason fetches that CLI on the same first start. The
  # parsers lose the race: they download, reach the compile step before the CLI
  # has arrived, and report
  #
  #   Error during "tree-sitter build": ENOENT: no such file or directory
  #   (cmd): 'tree-sitter'
  #
  # which reads like a missing dependency and is really a missing few seconds.
  # nvim-treesitter logs to `:messages` and no further, so it is not in any file
  # afterwards either. The second start has the CLI and builds them.
  log info "treesitter parsers may fail on that first start, before Mason has fetched the tree-sitter CLI they build with -- reopen nvim and they compile"
}
