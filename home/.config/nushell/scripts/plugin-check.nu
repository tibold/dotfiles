# Noticing a plugin registry that points at files which are gone.
#
# `plugin add` records the plugin's path with every symlink resolved, so on
# Homebrew the registry holds /opt/homebrew/Cellar/nushell/<version>/bin/...
# even when it was handed the stable /opt/homebrew/bin link. `brew upgrade`
# deletes that versioned directory, and from then on every plugin command
# fails to spawn -- `from ini` included -- until the plugins step runs again.
# Nothing in nushell says so until a plugin is used, which is usually halfway
# through a script.
#
# The REPL gets this through autoload/plugins.nu.

# The names of the plugins whose executable no longer exists.
export def missing []: table<name: string, filename: string> -> list<string> {
  where {|p| not ($p.filename | path exists) } | get name
}

# Warn on stderr when any registered plugin's executable is gone.
export def warn []: nothing -> nothing {
  let gone = (plugin list | missing)
  if ($gone | is-empty) { return }

  print --stderr $"(ansi yellow)warn(ansi reset) nushell plugins point at files that no longer exist \(($gone | str join ', ')) -- probably an upgrade. Re-register them with `nu install.nu --only plugins` from the dotfiles repo."
}
