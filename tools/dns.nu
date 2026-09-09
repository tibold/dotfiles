#!/bin/env nu

use ../lib/distro.nu 

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


# dns.nu — resolver configuration for openSUSE hosts
#
# Target-local: runs on the host being configured, as root.
#
# Puts systemd-resolved in the path and routes named domains to a specified
# resolver on a specified connection, leaving everything else on whatever the
# other connections provide.
#
# `dns=systemd-resolved` hands the config to resolved over D-Bus, and with
# `rc-manager` left at its default of `auto` NetworkManager then leaves
# /etc/resolv.conf alone. No need to set rc-manager explicitly; `unmanaged`
# would also stop NetworkManager writing a fallback file if resolved is ever
# stopped.
#
# Order matters. Setting dns=systemd-resolved before the package is installed
# means NetworkManager cannot use it, falls back to writing resolv.conf as a
# regular file, and that file survives the later install — neither daemon
# replaces a resolv.conf it did not create. The result is resolved running,
# correctly configured, and used by nothing: `resolv.conf mode: foreign`.
# Hence install first, then the drop-in, then the symlink.
#
# Leap 16 and Tumbleweed dropped netconfig along with wicked, so nothing else
# contends for the file. On Leap 15 or SLES, `NETCONFIG_DNS_POLICY` in
# /etc/sysconfig/network/config would also need clearing.
#
#   use dns.nu *
#   main status
#   main setup resolved
#   main configure zones wg0 10.1.10.10 [lab.example.com env.example.com]
#   main verify host.lab.example.com

const NM_DROPIN = "/etc/NetworkManager/conf.d/dns.conf"
const STUB = "/run/systemd/resolve/stub-resolv.conf"

# ── helpers ───────────────────────────────────────────────────────────────────

def pkg-installed [name: string] {
    (^rpm -q $name | complete | get exit_code) == 0
}

def unit [name: string] {
    {
        enabled: (^systemctl is-enabled $name | complete | get stdout | str trim)
        active: (^systemctl is-active $name | complete | get stdout | str trim)
    }
}

def resolv-target [] {
    let out = (^readlink /etc/resolv.conf | complete)
    if $out.exit_code == 0 { $out.stdout | str trim } else { "" }
}

def nm-dns-backend [] {
    let out = (^NetworkManager --print-config | complete)
    if $out.exit_code != 0 { return "unknown" }
    let hit = ($out.stdout | lines | where ($it | str starts-with "dns="))
    if ($hit | is-empty) { "default" } else { $hit | first | str replace "dns=" "" }
}

# Reported for diagnosis only. `auto` is correct alongside
# dns=systemd-resolved; `default` means the setting is absent, which is also
# `auto`. Anything else was set deliberately.
def nm-rc-manager [] {
    let out = (^NetworkManager --print-config | complete)
    if $out.exit_code != 0 { return "unknown" }
    let hit = ($out.stdout | lines | where ($it | str starts-with "rc-manager="))
    if ($hit | is-empty) { "default" } else { $hit | first | str replace "rc-manager=" "" }
}

# The device a connection is bound to. `device reapply` applies changes to a
# live interface without dropping it, which matters when the connection in
# question is carrying the session.
def nm-device [connection: string] {
    let out = (^nmcli -g GENERAL.DEVICES connection show $connection | complete)
    if $out.exit_code == 0 { $out.stdout | str trim } else { "" }
}

def step [label: string, dry: bool, block: closure] {
    if $dry {
        print $"would: ($label)"
    } else {
        print $"($label)"
        do $block
    }
}

# ── status ────────────────────────────────────────────────────────────────────

# What the resolver stack looks like and whether each piece is where
# `setup resolved` would put it. Changes nothing.
def "main status" [] {
    let resolved = (unit "systemd-resolved")
    let target = (resolv-target)

    [
        {
            check: "systemd-resolved installed"
            actual: (if (pkg-installed "systemd-resolved") { "yes" } else { "no" })
            want: "yes"
        }
        { check: "systemd-resolved enabled" actual: $resolved.enabled want: "enabled" }
        { check: "systemd-resolved active" actual: $resolved.active want: "active" }
        { check: "NetworkManager dns backend" actual: (nm-dns-backend) want: "systemd-resolved" }
        {
            check: "/etc/resolv.conf target"
            actual: (if ($target | is-empty) { "regular file" } else { $target })
            want: $STUB
        }
    ]
    | insert ok {|r| $r.actual == $r.want }
    | append {
        check: "NetworkManager rc-manager"
        actual: (nm-rc-manager)
        want: "auto or default"
        ok: ((nm-rc-manager) in ["auto" "default" "unmanaged"])
    }
}

# Per-link resolver configuration, which is where zone routing actually lives.
def "main status links" [] {
    ^nmcli -t -f NAME,DEVICE,TYPE connection show --active
    | lines
    | where ($it | is-not-empty)
    | each {|l|
        let f = ($l | split row ":")
        let name = ($f | first)
        {
            connection: $name
            device: ($f | get 1)
            dns: (^nmcli -g ipv4.dns connection show $name | complete | get stdout | str trim)
            search: (^nmcli -g ipv4.dns-search connection show $name | complete | get stdout | str trim)
            ignore_auto: (^nmcli -g ipv4.ignore-auto-dns connection show $name | complete | get stdout | str trim)
        }
    }
}

# ── setup ─────────────────────────────────────────────────────────────────────

# Put systemd-resolved in the path. No site facts involved — this only changes
# which component owns resolution, not what it resolves.
#
# Idempotent: each step checks its own state, so re-running after a partial
# failure is safe.
def "main setup resolved" [--dry-run] {
    if not (pkg-installed "systemd-resolved") {
        step "install systemd-resolved" $dry_run {
            ^zypper --non-interactive install systemd-resolved
        }
    } else {
        print "ok: systemd-resolved installed"
    }

    if (nm-dns-backend) != "systemd-resolved" {
        step $"write ($NM_DROPIN)" $dry_run {
            mkdir ($NM_DROPIN | path dirname)
            "[main]\ndns=systemd-resolved\n" | save --force --raw $NM_DROPIN
        }
    } else {
        print "ok: NetworkManager hands DNS to resolved"
    }

    # Neither daemon overwrites a resolv.conf it did not create, so this is
    # manual when switching backends on a running host.
    if (resolv-target) != $STUB {
        step $"symlink /etc/resolv.conf -> ($STUB)" $dry_run {
            if ("/etc/resolv.conf" | path exists) {
                ^mv /etc/resolv.conf /etc/resolv.conf.pre-resolved
            }
            ^ln -s $STUB /etc/resolv.conf
        }
    } else {
        print "ok: /etc/resolv.conf points at the stub"
    }

    step "enable resolved, reload NetworkManager" $dry_run {
        ^systemctl enable --now systemd-resolved
        ^systemctl reload NetworkManager
    }

    if not $dry_run {
        print ""
        main status
    }
}

# Undo `setup resolved`, putting NetworkManager back in charge of the file.
def "main revert resolved" [--dry-run] {
    step "hand resolv.conf back to NetworkManager" $dry_run {
        # Removing the drop-in makes rc-manager=auto fall back to writing the
        # file directly again, once resolved is gone.
        ^rm -f $NM_DROPIN
        ^rm -f /etc/resolv.conf
        ^systemctl disable --now systemd-resolved
        ^systemctl reload NetworkManager
    }
}

# ── zone routing ──────────────────────────────────────────────────────────────

# Route named domains to a resolver, on one connection.
#
# The `~` prefix makes each domain routing-only: queries for that suffix go to
# this link's resolver, and the domain is never appended as a search suffix.
# Pass --search to add one as a genuine search domain as well.
#
# Binding the resolver to the connection that reaches it means resolved drops
# the config when that interface goes down, rather than sending queries into a
# black hole.
def "main configure zones" [
    connection: string             # NM connection reaching the resolver
    server: string                 # resolver address
    ...zones: string            # domains to route there
    --search: list<string> = []    # subset also used as search suffixes
    --dry-run
] {
    if ($zones | is-empty) {
        error make { msg: "no zones given" }
    }

    let routed = (
        $zones | each {|z|
            if ($z in $search) { $z } else { $"~($z)" }
        } | str join ","
    )

    let device = (nm-device $connection)
    if ($device | is-empty) {
        print $"warning: ($connection) has no active device; changes apply on next up"
    }

    step $"($connection): dns=($server) dns-search=($routed)" $dry_run {
        ^nmcli connection modify $connection ipv4.dns $server
        ^nmcli connection modify $connection ipv4.dns-search $routed
        if ($device | is-not-empty) {
            ^nmcli device reapply $device
        }
    }
}

# Replace a connection's DHCP-supplied resolvers and search list.
#
# `ignore-auto-dns` is all-or-nothing, so dropping an unwanted search domain
# means supplying the nameservers explicitly. Separate command because this is
# the one place a mistake takes general resolution down.
def "main configure servers" [
    connection: string
    ...servers: list<string>
    --search: list<string> = []
    --dry-run
] {
    let device = (nm-device $connection)

    step $"($connection): dns=($servers | str join ',') ignore-auto-dns=yes" $dry_run {
        ^nmcli connection modify $connection ipv4.dns ($servers | str join ",")
        ^nmcli connection modify $connection ipv4.ignore-auto-dns yes
        ^nmcli connection modify $connection ipv4.dns-search ($search | str join ",")
        if ($device | is-not-empty) {
            ^nmcli device reapply $device
        }
    }
}

# ── verify ────────────────────────────────────────────────────────────────────

# Resolve names and report which link answered and whether it came from cache.
def "main verify" [...names: string] {
    ^resolvectl status

    for name in $names {
        print ""
        print $"── ($name) ──"
        ^resolvectl query $name
    }
}

# Clear resolved's cache, including negative entries — a cached NXDOMAIN from
# before a record existed is the usual cause of "I added it and it still does
# not resolve".
def "main flush" [] {
    ^resolvectl flush-caches
    print "resolved cache flushed"
}

def main [] {
    help commands main
}

