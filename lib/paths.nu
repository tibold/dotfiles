# Paths as glob patterns.
#
# nushell's glob reads a backslash as an escape, so a Windows path handed to it
# as-is -- C:\Users\... -- fails with "failed to parse glob expression".
# Forward slashes are accepted by Windows and by glob alike, so every path that
# becomes a pattern goes through here first. On Linux and macOS it changes
# nothing.
export def for-glob []: string -> string {
  str replace --all '\' '/'
}
