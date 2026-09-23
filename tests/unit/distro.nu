use ../../lib/distro.nu
use std/testing *
use std/assert

const TUMBLEWEED = 'NAME="openSUSE Tumbleweed"
# VERSION="20260830"
ID="opensuse-tumbleweed"
ID_LIKE="opensuse suse"
VERSION_ID="20260830"
PRETTY_NAME="openSUSE Tumbleweed"
CPE_NAME="cpe:2.3:o:opensuse:tumbleweed:20260830:*:*:*:*:*:*:*"'

const UBUNTU = 'NAME="Ubuntu"
VERSION="24.04.1 LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04.1 LTS"
VERSION_ID="24.04"'

@test
export def "os-release values keep their quotes off" [] {
  let parsed = (distro parse-os-release $TUMBLEWEED)
  assert equal ($parsed | get ID) "opensuse-tumbleweed"
  assert equal ($parsed | get PRETTY_NAME) "openSUSE Tumbleweed"
}

@test
export def "os-release ignores comments" [] {
  let parsed = (distro parse-os-release $TUMBLEWEED)
  # VERSION is commented out on Tumbleweed; VERSION_ID is not.
  assert equal ($parsed | get --optional VERSION) null
  assert equal ($parsed | get VERSION_ID) "20260830"
}

@test
export def "os-release splits on the first equals only" [] {
  # A value containing "=" must survive intact. Splitting on every "=" is the
  # obvious mistake here and it silently truncates.
  let parsed = (distro parse-os-release 'FOO=a=b=c')
  assert equal ($parsed | get FOO) "a=b=c"
}

@test
export def "os-release accepts unquoted values" [] {
  let parsed = (distro parse-os-release $UBUNTU)
  assert equal ($parsed | get ID) "ubuntu"
  assert equal ($parsed | get ID_LIKE) "debian"
}

@test
export def "families cover the distributions we target" [] {
  assert equal (distro family-of "opensuse-tumbleweed" ["opensuse" "suse"]) "suse"
  assert equal (distro family-of "opensuse-leap" ["opensuse" "suse"]) "suse"
  assert equal (distro family-of "fedora" []) "fedora"
  assert equal (distro family-of "ubuntu" ["debian"]) "debian"
  assert equal (distro family-of "debian" []) "debian"
}

@test
export def "derivatives are placed by ID_LIKE" [] {
  # The point of consulting ID_LIKE at all: distributions we have never heard
  # of land in the right family without being listed.
  assert equal (distro family-of "linuxmint" ["ubuntu"]) "debian"
  assert equal (distro family-of "rocky" ["rhel" "centos" "fedora"]) "fedora"
}

@test
export def "an unknown distribution is not guessed at" [] {
  assert equal (distro family-of "plan9" []) "unknown"
  assert equal (distro manager-of "unknown") "unknown"
}

@test
export def "describe produces the record the steps consume" [] {
  let described = (distro describe (distro parse-os-release $UBUNTU))
  assert equal $described.id "ubuntu"
  assert equal $described.family "debian"
  assert equal $described.manager "apt-get"
  assert equal $described.version "24.04"
  assert equal $described.pretty "Ubuntu 24.04.1 LTS"
}

@test
export def "install commands name the right package manager" [] {
  assert str contains (distro install-command "suse" ["git"] | str join " ") "zypper"
  assert str contains (distro install-command "fedora" ["git"] | str join " ") "dnf"
  assert str contains (distro install-command "debian" ["git"] | str join " ") "apt-get"
}

@test
export def "install commands are non-interactive" [] {
  # A prompt in the middle of an unattended install hangs the container tests
  # rather than failing them, which is a much worse way to find out.
  assert str contains (distro install-command "suse" ["git"] | str join " ") "--non-interactive"
  assert str contains (distro install-command "fedora" ["git"] | str join " ") "-y"
  assert str contains (distro install-command "debian" ["git"] | str join " ") "-y"
}

@test
export def "an empty package list produces no command" [] {
  assert equal (distro install-command "suse" []) []
}

@test
export def "only apt needs an index refresh" [] {
  assert equal (distro refresh-command "suse") []
  assert equal (distro refresh-command "fedora") []
  assert str contains (distro refresh-command "debian" | str join " ") "apt-get update"
}

# --- macOS --------------------------------------------------------------------
#
# macOS never reaches parse-os-release or family-of: it has no os-release file,
# and detect recognises it from the running nushell before looking for one. So
# what is worth asserting here is the record it builds instead, and that the
# commands keyed off it do not carry Linux habits across.

@test
export def "macOS describes itself without an os-release file" [] {
  let described = (distro describe-macos "26.6.2")
  assert equal $described.id "macos"
  assert equal $described.family "macos"
  assert equal $described.manager "brew"
  assert equal $described.version "26.6.2"
  assert equal $described.pretty "macOS 26.6.2"
}

@test
export def "macOS still describes itself when the version cannot be read" [] {
  # sw_vers is one more thing that can fail, and failing to name the version is
  # not a reason to refuse to install.
  assert equal (distro describe-macos "").pretty "macOS"
  assert equal (distro describe-macos "").family "macos"
}

@test
export def "Homebrew is never elevated" [] {
  # brew refuses to run as root, and does not need to: its prefix is owned by
  # the user who installed it. A sudo here would not be a harmless extra, it
  # would be a hard failure at the first package.
  assert not ((distro install-command "macos" ["git"] | str join " ") | str contains "sudo")
  assert not ((distro cask-install-command "macos" ["font-meslo-lg-nerd-font"] | str join " ") | str contains "sudo")
}

@test
export def "casks are installed as casks" [] {
  let command = (distro cask-install-command "macos" ["font-meslo-lg-nerd-font"] | str join " ")
  assert str contains $command "brew install --cask"
}

@test
export def "a family with no casks cannot be asked for one" [] {
  # Reaching this from Linux means an overlay grew a CASKS entry it has no way
  # to install, which should stop rather than be quietly dropped.
  assert error {|| distro cask-install-command "debian" ["font-hack-nerd-font"] }
  assert equal (distro cask-install-command "macos" []) []
}

@test
export def "a global npm install is elevated only where the prefix needs it" [] {
  # The distro packages put node under /usr, which needs root. Homebrew's
  # prefix is this user's, and running npm under sudo there leaves root-owned
  # files in it that the next un-elevated npm cannot update.
  assert equal (distro npm-global-command "macos" ["neovim"] | first) "npm"
  assert equal (distro npm-global-command "debian" ["neovim"] | first) "sudo"
  assert equal (distro npm-global-command "macos" []) []
}

@test
export def "brew needs no index refresh of its own" [] {
  # It updates itself before an install unless told otherwise, so a `brew
  # update` here would be the same fetch twice.
  assert equal (distro refresh-command "macos") []
}

@test
export def "a cask adopts what is already there rather than overwriting it" [] {
  # A font is the thing most likely to be installed by hand already, and a cask
  # refuses to write over files it did not place. --adopt takes over the ones
  # that are byte-identical; --force, the other way out of that error, would
  # overwrite a font someone chose.
  let command = (distro cask-install-command "macos" ["font-meslo-lg-nerd-font"] | str join " ")
  assert str contains $command "--adopt"
  assert not ($command | str contains "--force")
}

# --- platform directories -----------------------------------------------------

@test
export def "a platform directory is matched from broad to exact" [] {
  # The order is the whole mechanism: linked in this sequence, a file in the
  # more specific directory lands last and wins over the same path in a
  # broader one.
  assert equal (distro config-names { id: "ubuntu", family: "debian" }) ["linux" "debian" "ubuntu"]
  assert equal (distro config-names { id: "opensuse-leap", family: "suse" }) ["linux" "suse" "opensuse-leap"]
  assert equal (distro config-names { id: "fedora", family: "fedora" }) ["linux" "fedora"]
}

@test
export def "macOS collapses to a single platform name" [] {
  # os, family and id are all "macos" there, and linking the same directory
  # three times would back up its own link on the second pass.
  assert equal (distro config-names { id: "macos", family: "macos" }) ["macos"]
}

# --- Windows --------------------------------------------------------------

@test
export def "Windows describes itself without an os-release file" [] {
  let d = (distro describe-windows "26200")
  assert equal $d.id "windows"
  assert equal $d.family "windows"
  assert equal $d.manager "winget"
  assert equal $d.pretty "Windows (build 26200)"
  assert equal (distro describe-windows "").pretty "Windows"
}

@test
export def "Windows is its own single platform name" [] {
  assert equal (distro config-names { id: "windows", family: "windows" }) ["windows"]
}

@test
export def "winget installs one exact id without prompting" [] {
  let c = (distro winget-install-command "Git.Git")
  assert equal ($c | first) "winget"
  for flag in ["--exact" "--accept-package-agreements" "--accept-source-agreements" "--disable-interactivity"] {
    assert ($flag in $c) $"missing ($flag)"
  }
  assert equal ($c | skip until {|x| $x == "--id" } | get 1) "Git.Git"
  assert not ("sudo" in $c)
}

@test
export def "winget is not handed a list" [] {
  # One id per call is what lets one bad id fail alone.
  assert error {|| distro install-command "windows" ["Git.Git"] }
}

@test
export def "a global npm install on Windows goes through fnm" [] {
  let c = (distro npm-global-command "windows" ["neovim"])
  assert equal ($c | first 5) ["fnm" "exec" "--using" "default" "--"]
  # npm is a .cmd shim on Windows; fnm exec cannot spawn it by the bare name.
  assert equal ($c | get 5) "npm.cmd"
  assert equal ($c | last) "neovim"
}

@test
export def "winget needs no separate index refresh" [] {
  assert equal (distro refresh-command "windows") []
}
