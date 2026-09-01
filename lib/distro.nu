# Which distribution we are on, and what that implies.
#
# Two identifiers matter downstream and they are deliberately not the same
# thing:
#
#   family  what the package manager and most package names key off. Leap and
#           Tumbleweed are both "suse"; Ubuntu and Debian are both "debian".
#   id      the exact ID= from os-release. Only consulted where two members of
#           a family genuinely diverge, which in practice is Leap vs Tumbleweed
#           -- Leap's repos are years behind and simply lack some of these
#           tools.

# Parse os-release into a flat record.
#
# The file is shell syntax in principle, but in practice a KEY=VALUE list with
# optional quotes and comments. Parsing it directly rather than sourcing it
# means this works identically inside a nushell script and inside a test, with
# no shell-out and no chance of the file executing something.
export def parse-os-release [text: string]: nothing -> record {
  $text
  | lines
  | each {|l| $l | str trim }
  | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "#")) and ($l | str contains "=") }
  | reduce --fold {} {|line, acc|
      let key = ($line | split row "=" | first | str trim)
      # Split on the FIRST "=" only: values such as CPE_NAME legitimately
      # contain more of them.
      let value = ($line
        | str replace --regex '^[^=]*=' ''
        | str trim
        | str trim --char '"'
        | str trim --char "'")
      $acc | insert $key $value
    }
}

# Collapse an ID plus its ID_LIKE list into one of the families we support.
#
# ID_LIKE is what makes derivatives work without listing every one of them:
# Linux Mint says ID_LIKE=ubuntu, Rocky says ID_LIKE="rhel centos fedora".
export def family-of [id: string, id_like: list<string>]: nothing -> string {
  let names = ([$id] ++ $id_like)
  if (($names | any {|n| $n in ["opensuse" "opensuse-leap" "opensuse-tumbleweed" "suse" "sles" "sled"]})) {
    "suse"
  } else if (($names | any {|n| $n in ["fedora" "rhel" "centos" "rocky" "almalinux"]})) {
    "fedora"
  } else if (($names | any {|n| $n in ["debian" "ubuntu"]})) {
    "debian"
  } else {
    "unknown"
  }
}

export def manager-of [family: string]: nothing -> string {
  match $family {
    "suse" => "zypper"
    "fedora" => "dnf"
    "debian" => "apt-get"
    _ => "unknown"
  }
}

# Turn a parsed os-release record into the shape the rest of the code uses.
export def describe [os: record]: nothing -> record {
  let id = ($os | get --optional ID | default "unknown")
  let id_like = ($os
    | get --optional ID_LIKE
    | default ""
    | split row " "
    | where {|s| $s | is-not-empty })
  let family = (family-of $id $id_like)

  {
    id: $id
    version: ($os | get --optional VERSION_ID | default "")
    pretty: ($os | get --optional PRETTY_NAME | default $id)
    family: $family
    manager: (manager-of $family)
  }
}

export def detect [--file: path = "/etc/os-release"]: nothing -> record {
  if not ($file | path exists) {
    error make { msg: $"($file) does not exist -- cannot identify this system" }
  }
  describe (parse-os-release (open --raw $file))
}

# argv to refresh the package index before installing.
#
# Only apt genuinely requires this -- it will fail to find packages that exist
# if the lists are stale, which is the normal state of a fresh container image.
# zypper and dnf refresh themselves as needed, so they get a no-op rather than
# an expensive redundant sync.
export def refresh-command [family: string]: nothing -> list<string> {
  match $family {
    "debian" => ["sudo" "apt-get" "update"]
    _ => []
  }
}

export def install-command [family: string, packages: list<string>]: nothing -> list<string> {
  if ($packages | is-empty) { return [] }
  match $family {
    "suse" => (["sudo" "zypper" "--non-interactive" "install" "--auto-agree-with-licenses"] ++ $packages)
    "fedora" => (["sudo" "dnf" "install" "-y"] ++ $packages)
    "debian" => (["sudo" "apt-get" "install" "-y" "--no-install-recommends"] ++ $packages)
    _ => { error make { msg: $"no install command for family '($family)'" } }
  }
}
