#!/bin/env nu

use ../lib/distro.nu 
use ../lib/log.nu 
use ../lib/repo.nu 

let system = (distro detect)
if ($system.family != 'suse') {
  error make { 
    msg: "Current OS is not supported", system: $system
  }
}

if (not (is-admin)) {
  error make {
    msg: "This script must be run as admin"
  }
}

def main [] {
  help main
}

def "main install" [
  --role: string = "agent"      # server | agent
  --version: string             # pinned, e.g. v1.36.4+rke2r1
  --channel: string = "stable"   # used only when --version is absent
] {
  if $role not-in ["server" "agent"] {
    error make {msg: $"role must be server or agent, got ($role)"}
  }
  log info 'Find rke2 version'
  let version = if ($version | is-empty) { rke2-channel-version $channel } else { $version }

  main configure firewalld
  main configure nmcli

  log step 'Installing RKE2'
  with-env {
    INSTALL_RKE2_METHOD: "rpm"
    INSTALL_RKE2_TYPE: $role
    INSTALL_RKE2_VERSION: $version
  } { 
    http get https://get.rke2.io | ^sh - 
  }

  # The RPM path is what pulls in rke2-selinux. A tarball fallback would not,
  # and otherwise looks like a clean install.
  let pkgs = (^rpm -q rke2-common rke2-selinux | complete)
  if $pkgs.exit_code != 0 {
    error make {msg: $"RPM install did not take, fell back to tarball\n($pkgs.stdout)"}
  }
  log ok 'done.'
}

# Build and load the RKE2 SELinux policy from source.
#
# The packaged .pp is compiled at policydb module version 24; Leap 16's
# libsepol accepts 4-22, so it can never load. Building against the local
# toolchain sidesteps the version entirely. Must run before first start,
# and again whenever rke2-selinux is upgraded.
export def "main install rke2-policy" [
  --tag: string = "v0.23.stable.1"
  --variant: string = "slemicro"   # closest base to Leap 16
  --force                          # rebuild even if a module is loaded
] {
  if not $force and (^semodule -l | lines | any { |m| $m == "rke2" }) {
    print "rke2 policy already loaded; pass --force to rebuild"
    return
  }

  ^zypper --non-interactive install selinux-policy-devel checkpolicy

  let src = (repo clone "https://github.com/rancher/rke2-selinux" $tag)

  # layout has moved between tags; find the variant's .te rather than assume
  let te = (
    glob $"($src)/**/*($variant)*/rke2.te"
    | append (glob $"($src)/**/rke2.te")
    | get -o 0
  )
  if ($te | is-empty) {
    error make {msg: $"no rke2.te found for variant ($variant) at ($tag)"}
  }

  cd ($te | path dirname)
  ^make -f /usr/share/selinux/devel/Makefile rke2.pp
  ^semodule -i rke2.pp

  if not (^semodule -l | lines | any { |m| $m == "rke2" }) {
    error make {msg: "build succeeded but module did not load"}
  }
  print $"loaded rke2 policy built from ($tag)"

  restorecon -RFv /var/lib/rancher /var/lib/kubelet /etc/rancher

  # stop upgrades reintroducing the unloadable .pp
  ^zypper addlock rke2-selinux
}

# Render server config. Safe to re-run; restart rke2-server to apply.
def "main configure server" [
  --token: string               # generated on first start if omitted, but
                                # it also encrypts etcd bootstrap data, so
                                # supplying one keeps restores possible
  --node-ip: string
  --api-vip: string = "10.20.10.10"   # reserved, not yet assigned
] {
  let status = main status
  if ('server' not-in $status.installed) {
    error make {
      msg: 'RKE2 server is not installed'
    }
  }
  if ('agent' == $status.configured) {
    error make {
      msg: 'RKE2 agent is already configured. Refusing to also configure a server.'
    }
  }
  let name = (hostname | split row "." | first)
  {
    "node-name": $name
    "node-ip": (resolve-ip $node_ip)
    # set before first start: adding a VIP later is then a DNS change,
    # not a certificate regeneration across every node
    "tls-san": [$api_vip "api.lab" $"($name).lab"]
    "node-taint": ["CriticalAddonsOnly=true:NoExecute"]
    selinux: true
  }
  | merge (if ($token | is-empty) { {} } else { {token: $token} })
  | write-config
}

# Render agent config. Safe to re-run; restart rke2-agent to apply.
def "main configure agent" [
  --token: string               # required
  --node-ip: string
  --server: string = "https://api.lab:9345"
] {
  let status = main status
  if ('agent' not-in $status.installed) {
    error make {
      msg: 'RKE2 agent is not installed'
    }
  }
  if ('server' == $status.configured) {
    error make {
      msg: 'RKE2 server is already configured. Refusing to also configure an agent.'
    }
  }
  if ($token | is-empty) { error make {msg: "--token is required"} }
  {
    token: $token
    "node-name": (hostname | split row "." | first)
    "node-ip": (resolve-ip $node_ip)
    server: $server
    selinux: true
  }
  | write-config
}

def "main configure firewalld" [] {

  log step 'Disabling firewalld'

  let status = systemctl is-active firewalld | complete

  if $status.exit_code == 0 {
    systemctl stop firewalld
  }
  systemctl mask firewalld

  log ok 'done.'
}

def "main configure nmcli" [] {
  log step 'Configuring NetworkManager'

  let conf = '[keyfile]
unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali'
  $conf | save '/etc/NetworkManager/conf.d/rke2-canal.conf' --force 

  systemctl reload NetworkManager

  log ok 'done.'
}

def "main start" [] { 
  let unit = (unit)
  log step $'Starting ($unit)...'
  ^systemctl start $unit
}

def "main stop" [] { 
  let unit = (unit)
  log step $'Stopping ($unit)...'
  ^systemctl stop (unit) 
}

def "main enable" [--now] {
  let unit = (unit)
  if $now { 
    ^systemctl enable --now $unit
  } else { 
    ^systemctl enable $unit 
  }
}

def "main disable" [--now] {
  let unit = (unit)
  if $now { 
    ^systemctl disable --now $unit
  } else { 
    ^systemctl disable $unit
  }
}

def "main status" []: nothing -> record {
  let installed = (
    ["server" "agent"]
    | where { |r| (^rpm -q $"rke2-($r)" | complete).exit_code == 0 }
  )
  let config = if ("/etc/rancher/rke2/config.yaml" | path exists) {
    open /etc/rancher/rke2/config.yaml
  } else { null }
  let enabled = (
    ["server" "agent"]
    | where { |r| (^systemctl is-enabled $"rke2-($r)" | complete).exit_code == 0 }
  )
  let active = (
    ["server" "agent"]
    | where { |r| (^systemctl is-active $"rke2-($r)" | complete).exit_code == 0 }
  )
  {
    installed: $installed
    # a config with `server:` is an agent, without is a server
    configured: (if $config == null { null } else if "server" in ($config | columns) { "agent" } else { "server" })
    enabled: $enabled
    active: $active
    version: (
      if (which rke2 | is-empty) { null } else {
        (^rke2 --version | complete).stdout | lines | get -o 0
      }
    )
  }
}

# Wipe cluster state. Leaves packages installed — rke2-uninstall.sh removes those.
def "main reset" [
  --keep-config        # leave /etc/rancher/rke2 inexport place  
  --volumes            # local-path / hostPath provisioner directories
  --lvm: string        # volume group to empty, e.g. "data" — LVs are removed
  --longhorn           # /var/lib/longhorn replica data
  --force
] {
  let name = (hostname | split row "." | first)
  if not $force {
    let s = (main status)
    print $"about to wipe RKE2 state on ($name) \(configured: ($s.configured | default 'none'))"
    if (input "type the hostname to confirm: ") != $name {
      error make {msg: "aborted"}
    }
  }

  # killall first: it stops the unit and unmounts kubelet pod volumes. Deleting
  # underneath a live mount is how you lose data that was never on this node.
  if ("/usr/bin/rke2-killall.sh" | path exists) { 
    log step 'Kill all rke2 services'
    ^/usr/bin/rke2-killall.sh export
    log ok 'done.'
  }

  log step 'Clear config dirs'
  [
    /var/lib/rancher/rke2
    /var/lib/kubelet
    /var/lib/cni
    /etc/cni/net.d
    /run/k3s
  ] | each { |d| if ($d | path exists) { rm -rf $d } }

  if not $keep_config {
    rm -rf /etc/rancher/rke2
  }
  log ok 'done.'

  if $volumes {
    log step 'Deleting volumes'
    [/var/lib/rancher/local-path /opt/local-path-provisioner]
    | each { |d| if ($d | path exists) { rm -rf $d } }
    log ok 'done.'
  }

  if $longhorn and ("/var/lib/longhorn" | path exists) {
    log step 'Deleting longhorn'
    rm -rf /var/lib/longhorn
    log ok 'done.'
  }

  if ($lvm | is-not-empty) {
    log step 'Deleting lvm volumes'
    let vg = $lvm
    let root_vg = (^findmnt -no SOURCE / | complete).stdout | str trim
    if ($root_vg | str contains $"/($vg)-") or ($root_vg | str contains $"/($vg)/") {
      error make {msg: $"refusing: ($vg) holds the root filesystem"}
    }
    let lvs = (^lvs --noheadings -o lv_name --select $"vg_name=($vg)" | complete)
    if $lvs.exit_code != 0 {
      error make {msg: $"volume group ($vg) not found"}
    }
    $lvs.stdout | lines | each { |lv|
      let name = ($lv | str trim)
      log info $"Removing ($vg)/($name)"
      ^lvremove -f $"($vg)/($name)"
    }
    log ok 'done.'
  }
}

def "main token" []: nothing -> string {
  let s = (main status)
  let configured = (
    if ("/etc/rancher/rke2/config.yaml" | path exists) {
      open /etc/rancher/rke2/config.yaml | get -o token
    } else { null }
  )
  # the file is authoritative — a server with no token in config generated one
  let onfile = (
    if ("/var/lib/rancher/rke2/server/token" | path exists) {
      open --raw /var/lib/rancher/rke2/server/token | str trim
    } else { null }
  )
  match [$onfile $configured] {
    [null null] => (error make {msg: "no token; server has not started yet, or agent is unconfigured"}),
    [null $c] => $c,
    [$f null] => $f,
    [$f $c] => {
      if $f != $c {
        print -e $"warning: config token differs from ($f | str substring 0..8)… in use"
      }
      $f
    }
  }
}

# For nested LVM on nvme enable this
def "main fstrim enable" [] {
  systemctl enable --now fstrim.timer
}

# --- Helpers ---

def write-config []: record -> nothing {
  mkdir /etc/rancher/rke2
  $in | to yaml | save -f /etc/rancher/rke2/config.yaml
  open /etc/rancher/rke2/config.yaml
}

# Resolve a release channel to a concrete version string.
def rke2-channel-version [channel: string] {
  http get https://update.rke2.io/v1-release/channels
  | get data
  | where id == $channel
  | get 0.latest
}

# Resolve this host's IPv4 address. With no argument, requires exactly one candidate.
def resolve-ip [ip?: string]: nothing -> string {
  let addrs = (
    sys net
    | where name != "lo"
    | get ip
    | flatten
    | where protocol == "ipv4"
    | get address
    | where $it !~ '^169\.254\.'
  )

  if ($ip | is-not-empty) {
    if $ip not-in $addrs {
      error make {msg: $"($ip) is not configured here; found ($addrs | str join ', ')"}
    }
    return $ip
  }

  match ($addrs | length) {
    1 => ($addrs | first),
    0 => (error make {msg: "no IPv4 address found"}),
    _ => (error make {msg: $"ambiguous, pass one explicitly: ($addrs | str join ', ')"})
  }
}

# The unit this node should be running, from what's configured and installed.
def unit []: nothing -> string {
  let s = (main status)
  if $s.configured == null {
    error make {msg: "no /etc/rancher/rke2/config.yaml — run configure first"}
  }
  if $s.configured not-in $s.installed {
    error make {msg: $"configured as ($s.configured) but only ($s.installed | str join ', ') installed"}
  }
  return $"rke2-($s.configured)"
}

