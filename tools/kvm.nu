#!/bin/env nu

use ../lib/distro.nu 
use ../lib/log.nu 

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

def "main install" [] {
  log step 'Installing KVM server'
  zypper --non-interactive install -t pattern kvm_server kvm_tools
  zypper --non-interactive install qemu-ovmf-x86_64
  log ok "Install complete"

  log step 'Starting KVM server'
  let result = systemctl enable --now libvirtd | complete
  if ($result.exit_code != 0) {
    systemctl enable --now virtqemud.socket virtstoraged.socket virtnetworkd.socket virtnodedevd.socket virtlogd.socket
  }
  log ok 'Started'
}

def "main install lvm-pool" [
  name: string
  vgname: string
  --start
  --auto-start
] {
  let pool_xml = virsh pool-dumpxml $name | complete
  if $pool_xml.exit_code == 0 {
    let pool = $pool_xml.stdout | from xml
    if $pool.attributes.type != 'logical' {
      error make {
        msg: $'Pool ($name) already exists with a different type'
        pool: $pool
      }
    }
    
    let pool_source_name = $pool.content 
      | find tag == 'source'
      | get content.0
      | find tag == 'name'
      | get content.0.content.0
    if $pool_source_name != $vgname {
      error make {
        msg: $'Pool ($name) already exists with a different vg source'
        pool: $pool
      }
    }
    log step $'Using existing LVM pool ($name)'
  } else {
    log step $'Creating LVM pool ($name)'
    virsh pool-define-as $name logical --source-name $vgname --target $'/dev/($vgname)'
  }

  let pool = virsh pool-info $name | from yaml
  
  if (
      ($start or $auto_start) and
      $pool.State != 'running'
  ) {
    log info $'Starting pool ($name)'
    virsh pool-start $name
  }
  if ($auto_start and $pool.Autostart == 'no') {
    log info $'Set pool ($name) to auto start'
    virsh pool-autostart $name
  }
  log ok $'LVM pool ($name) created'
}

def "main download" [] {
  help commands download
}

def "main download opensuse" [] {
  log step 'Fetch available images'
  let applianceUrl = 'https://download.opensuse.org/distribution/leap/16.0/appliances/'
  let libvirtdImageStore = '/var/lib/libvirt/images/'
  let images = http get $'($applianceUrl)?json'
  let selected = $images 
    | where { |x| $x.name | str ends-with '.qcow2' } 
    | select name size 
    | update size {into filesize }
    | input list
  let localPath = $libvirtdImageStore | path join $selected.name

  if ($localPath | path exists) {
    log ok 'File already exists (contents not verified)'
  } else {
    let imageSourceUrl = $applianceUrl | path join $selected.name
    log info $'Downloading image from ($imageSourceUrl)'
    try {
      http get $imageSourceUrl --raw 
        | save $localPath --progress 
    } catch { |x|
      if ($localPath | path exists ) {
        rm $localPath
      }
    }
    log ok 'Download complete,'
  }
}

def "main create rke2-host" [
  name: string
  cpu
  ram: filesize
  network: string = 'default'
  username:string = 'rke'
  vgName:string = 'vg0'
  --control-plane
] {
  let selected = ls /var/lib/libvirt/images/*.qcow2
    | input list
  let image = $selected.name

  virsh vol-create-as default $'($name)-os' 100G
  qemu-img convert -O raw $'($image)' $'/dev/($vgName)/($name)-os'
  mut disks = [
    '--disk', 
    $'vol=default/($name)-os,bus=virtio,cache=none,io=native,discard=unmap'
  ]
  if not $control_plane {
    virsh vol-create-as default $'($name)-data' 200G
    $disks = $disks | append [
      '--disk', 
      $'vol=default/($name)-data,bus=virtio,cache=none,io=native,discard=unmap'
    ]
  }

  let ssh_keys = open ~/.ssh/authorized_keys | lines
  
  mut user_data = {
    #cloud-config
    hostname: $name
    fqdn: $'($name).lab'
    ssh_pwauth: false
    growpart: { mode: auto, devices: ['/'] }
    users: [
      {
        name: $username
        groups: 'wheel'
        sudo: 'ALL=(ALL) NOPASSWD:ALL'
        ssh_authorized_keys: $ssh_keys
      }
    ]
  }
  if not $control_plane {
    $user_data = $user_data | merge {
      disk_setup: {
        '/dev/vdb': { table_type: 'gpt', layout: true, overwrite: true }
      }
      fs_setup: [
        { device: '/dev/vdb1', filesystem: 'xfs', label: 'data' }
      ]
      mounts: [
        ['LABEL=data', '/var/lib/data', 'xfs', "defaults,noatime", "0", "0"]
      ]
    }
  }

  let user_data_file = mktemp --dry
  "#cloud-config\n" | save $user_data_file --force 
  $user_data | to yaml | save $user_data_file --append

  let virt_install_args = [
      --name $name 
      --vcpus $cpu --cpu host-passthrough
      --memory ($ram / 1MiB | into int)
      --boot uefi
      --machine q35
      --osinfo opensuse16.0 
      ...$disks 
      --network $'network=($network),model=virtio'
      --cloud-init $'user-data=($user_data_file)'
      --console 'pty,target_type=serial'
      --graphics none
      --memballoon 'virtio,freePageReporting=on'
      --import
  ]

  virt-install ...$virt_install_args
}

def "main create network" [
    name: string                      # network name; also the DNS domain
    cidr: string                      # e.g. 10.20.10.0/24
    --domain: string                  # DNS domain, defaults to name
    --forward: string = "route"       # route, nat, open, bridge or none
    --bridge: string                  # bridge device, defaults to virbr-<name>
    --dhcp-start: int = 100           # offset from the network address
    --dhcp-end: int = 199
    --reservations: list<any> = []    # [{name, mac, ip}, ...]
    --dns-hosts: list<string> = []    # short names resolving to the gateway
    --no-start                        # define and autostart, but leave it down
] {
  if ($name in (virsh net-list --all --name | lines | str trim)) {
      error make {msg: $"libvirt network ($name) already exists"}
  }

  let xml = (
    main render network $name $cidr
      --domain $domain
      --forward $forward
      --bridge $bridge
      --dhcp-start $dhcp_start
      --dhcp-end $dhcp_end
      --reservations $reservations
      --dns-hosts $dns_hosts
  )

  let tmp = (mktemp --tmpdir --suffix .xml $"libvirt-net-($name)-XXXXXX")
  $xml | save --force $tmp

  try {
    virsh net-define $tmp
    virsh net-autostart $name
    if not $no_start { 
      virsh net-start $name 
    }
  } catch {|e|
    rm --force $tmp
    error make {msg: $"virsh failed: ($e.msg)"}
  }

  rm --force $tmp

  if not $no_start {
    let dev = ($bridge | default $"virbr-($name)")
    print $"($name) is up on ($dev)"
    print $"check the zone: firewall-cmd --get-zone-of-interface=($dev)"
  }
}

# --------------------------------------------------------------- xml build ---

def "main render network" [
    name: string
    cidr: string
    --domain: string
    --forward: string = "route"
    --bridge: string
    --dhcp-start: int = 100
    --dhcp-end: int = 199
    --reservations: list<any> = []
    --dns-hosts: list<string> = []
]: nothing -> string {
  let parts = ($cidr | split row "/")
  if ($parts | length) != 2 {
    error make {msg: $"cidr must look like 10.20.10.0/24, got ($cidr)"}
  }

  let prefix   = ($parts.1 | into int)
  let base_int = (ip-to-int $parts.0)
  let size     = (2 ** (32 - $prefix))

  if ($base_int mod $size) != 0 {
    error make {msg: $"($parts.0) is not the network address for a /($prefix)"}
  }
  if $dhcp_end >= ($size - 1) or $dhcp_start >= $dhcp_end {
    error make {msg: $"dhcp range ($dhcp_start)-($dhcp_end) does not fit a /($prefix)"}
  }

  let gateway = (int-to-ip ($base_int + 1))
  let dev     = ($bridge | default $"virbr-($name)")
  let dom     = ($domain | default $name)

  # dnsmasq silently ignores reservations outside the subnet.
  for r in $reservations {
    let host_int = (ip-to-int $r.ip)
    if $host_int <= $base_int or $host_int >= ($base_int + $size - 1) {
      error make {msg: $"reservation ($r.name) at ($r.ip) is outside ($cidr)"}
    }
  }

  let dns = if ($dns_hosts | is-empty) { [] } else {
    [(el dns {} [
      (el host {ip: $gateway} (
          $dns_hosts | each {|h| el hostname {} [(txt $"($h).($dom)")] }
      ))
    ])]
  }

  let dhcp_children = (
    [(el range {start: (int-to-ip ($base_int + $dhcp_start))
                end:   (int-to-ip ($base_int + $dhcp_end))})]
    | append ($reservations | each {|r|
        el host {mac: $r.mac, name: $r.name, ip: $r.ip}
    })
  )

  el network {} ([
      (el name {} [(txt $name)])
      (el forward {mode: $forward})
      (el bridge {name: $dev, stp: "on", delay: "0"})
      (el domain {name: $dom, localOnly: "yes"})
  ] | append $dns | append [
      (el ip {address: $gateway, netmask: (netmask-from-prefix $prefix)} [
          (el dhcp {} $dhcp_children)
      ])
  ])
  | to xml --self-closed --indent 2
}

# ---------------------------------------------------------------- helpers ---

def ip-to-int [ip: string]: nothing -> int {
    $ip | split row "." | each { $in | into int }
       | reduce --fold 0 {|octet, acc| $acc * 256 + $octet }
}

def int-to-ip [n: int]: nothing -> string {
    [24 16 8 0] | each {|s| $n | bit-shr $s | bit-and 255 | into string } | str join "."
}

def netmask-from-prefix [prefix: int]: nothing -> string {
    0..3 | each {|i|
        let raw = $prefix - ($i * 8)
        let bits = if $raw < 0 { 0 } else if $raw > 8 { 8 } else { $raw }
        255 | bit-shl (8 - $bits) | bit-and 255 | into string
    } | str join "."
}

def el [tag: string, attributes: record = {}, content: list = []] {
    {tag: $tag, attributes: $attributes, content: $content}
}

def txt [s: string] {
    {tag: null, attributes: null, content: $s}
}

