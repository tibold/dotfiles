#!/bin/env nu

use ../lib/distro.nu 
use ../lib/log.nu 
use ini.nu *

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
  help 
}

def "main install" [
  port: number = 51820 # Optional listen port for wireguard 
] {
  log step 'Installing wireguard-tools'
  zypper --non-interactive install wireguard-tools
  install -d -m 0700 /etc/wireguard
  log ok 'Installed'

  main configure keys 
  main configure forwarding 
  main configure firewall $port

  log ok 'All done.'
} 

def "main configure" [] {
  help main configure
}

def "main configure keys" [] {
  let hostname = hostnamectl hostname
  let key_path = $'/etc/wireguard/($hostname).key'
  let public_key_path = $'/etc/wireguard/($hostname).pub'

  log step 'Generating keys'
  mut key = ''
  if not ($key_path | path exists)  {
    $key = ^wg genkey 
    $key | save $key_path
    log ok 'Private key'
  } else {
    $key = open $key_path --raw 
    log ok 'Keeping existing key'
  }

  mut public_key = ''
  if not ($public_key_path | path exists) {
    let public_key = $key | wg pubkey
    $public_key | save $public_key_path
    log ok 'Public key'
  } else {
    $public_key = open $public_key_path --raw 
    log ok 'Keeping existing public key'
  }

  log info $"Machine's public key:\n\t($public_key)\n\n"
}

def "main configure forwarding" [] {
  log step 'Enable ipv3 forwarding'
  'net.ipv4.ip_forward = 1' | save /etc/sysctl.d/99-wireguard-forwarding.conf --force 
  log info 'Reloading sysctl'
  sysctl --system | complete
  log ok 'Forwarding enabled'
}

def "main configure firewall" [
  port: number = 51820 # Optional listen port for wireguard
] {
  log step 'Configuring firewall'
  firewall-cmd --permanent --zone=public $'--add-port=($port)/udp'
  log ok 'Incoming wireguard allowed'
  firewall-cmd --permanent --new-zone=wg
  firewall-cmd --permanent --zone=wg --add-interface=wg0
  firewall-cmd --permanent --zone=wg --add-service=ssh
  log ok 'Zone wg created'
  firewall-cmd --reload
  log ok 'Firewall reloaded'
}

def "main interface" [] {
  help main interface
}

def "main interface add" [
  id: number            # interface id such as 0 for wg0
  ip: string            # IPv4 with mask such as 10.0.0.1/24
  port: number = 51820  # Optional listen port for wireguard
  mtu: number = 1420    # Interface MTU
] {
  let hostname = hostnamectl hostname
  let key_path = $'/etc/wireguard/($hostname).key'
  let key = open $key_path --raw 

  let name = $'wg($id)'

  nmcli ...[
    connection add
    type wireguard
    con-name $name
    ifname $name
    autoconnect yes
    connection.zone wg
    ipv4.method manual
    ipv4.addresses $ip
    wireguard.listen-port $port
    wireguard.mtu $mtu
    wireguard.private-key $key
  ]
}

def "main interface start" [
  id: number # interface id such as 0 for wg0
] {
  let name = $'wg($id)'

  nmcli connection up $name
  wg show $name
  ip -4 addr show $name
  firewall-cmd --get-zone-of-interface=$name
}

def "main interface stop" [
  id: number # interface id such as 0 for wg0
] {
  let name = $'wg($id)'

  nmcli connection down $name
  wg show $name
}

def "main peer add" [
  id: number        # interface id such as 0 for wg0
  endpoint: string  # The remote endpoint in ip:port format
  allowed_ips: string # A list of allowed ips with subnet mask and terminated with a semicolon x.x.x.x/y;
  public_key: string # The public key of the peer
] {
  let name = $'wg($id)'
  let config_path = $'/etc/NetworkManager/system-connections/($name).nmconnection'
  log step $'Adding peer ($endpoint) to ($name)'
  let config = open $config_path | from ini
  let peer = {
    $'wireguard-peer.($public_key)': {
      endpoint: $endpoint
      allowed-ips: $allowed_ips
      persistent-keepalive: 25
    }
  }

  $config | merge $peer | to ini | save $config_path --force 

  log ok 'done.'

  log step 'Reloading nmcli'

  nmcli connection reload
  nmcli device reapply $name

  log ok 'done.'
}
