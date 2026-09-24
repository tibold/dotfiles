use ../../lib/rio.nu
use ../../packages/windows.nu
use std/testing *
use std/assert

# lib/rio.nu's decisions are pure, so these run on every platform. The
# downloads, signatures and shortcut need Windows and the network, and are
# exercised by a real run.

@test
export def "versions compare as numbers, not as text" [] {
  assert equal (rio compare-versions "0.5.28" "0.5.9") 1
  assert equal (rio compare-versions "v0.5.28" "0.5.28") 0
  assert equal (rio compare-versions "0.5.28" "0.6.0") (-1)
  # A file version drops leading zeros, a NuGet build number keeps them.
  assert equal (rio compare-versions "1.24.2607.1001" "1.24.2607.01001") 0
  assert equal (rio compare-versions "1.24" "1.24.0.0") 0
}

@test
export def "the latest stable ConPTY skips previews, whatever order NuGet lists them in" [] {
  let versions = ["1.24.260303001" "1.25.260710002-preview" "1.24.260710001" "1.24.260512001"]
  assert equal (rio latest-stable $versions) "1.24.260710001"
}

@test
export def "a NuGet ConPTY version maps to the version stamped in its DLL" [] {
  # Both pairs read off real files: Rio's copy from 1.24.260710001, and the
  # one Contour 0.7.0 bundles from 1.24.251216004.
  assert equal (rio conpty-file-version "1.24.260710001") "1.24.2607.10001"
  assert equal (rio conpty-file-version "1.24.251216004") "1.24.2512.16004"
  assert error { rio conpty-file-version "1.24" }
}

@test
export def "a component is installed when absent, upgraded when older, else left" [] {
  assert equal (rio action-for null "0.5.28") "install"
  assert equal (rio action-for "0.5.27" "0.5.28") "upgrade"
  assert equal (rio action-for "0.5.28" "0.5.28") "current"
  # Newer than upstream's latest -- a hand-placed build -- is not downgraded.
  assert equal (rio action-for "0.6.0" "0.5.28") "current"
  assert equal (rio action-for "1.24.2607.10001" (rio conpty-file-version "1.24.260710001")) "current"
}

@test
export def "only a valid signature by Microsoft itself passes" [] {
  let microsoft = "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"
  assert (rio microsoft-signed "Valid" $microsoft)
  assert not (rio microsoft-signed "HashMismatch" $microsoft)
  assert not (rio microsoft-signed "NotSigned" "")
  # An organisation that merely starts with the name is someone else.
  assert not (rio microsoft-signed "Valid" "CN=x, O=Microsoft Corporation Fans Ltd, C=US")
}

@test
export def "the checksum for an asset is read from the checksums file of its release" [] {
  # Lines as the v0.5.28 release publishes them.
  let checksums = "e9cec1728670d6af37dccc4bf7422320d0a122181d28f55706376084d2d8117d  rio-installer-aarch64.msi
F1236741544923CAE67A7F8812C5C8CFEC729BC038D07920BBC677186941A003  rio-portable-aarch64.exe
7c567ee7f512694caab13fc01517c191a3ff6c3acc1942eb619b53bcd3a00180  rio-portable-x86_64.exe
"
  assert equal (rio checksum-for $checksums "rio-portable-x86_64.exe") "7c567ee7f512694caab13fc01517c191a3ff6c3acc1942eb619b53bcd3a00180"
  # Compared against `hash sha256`, which is lowercase.
  assert equal (rio checksum-for $checksums "rio-portable-aarch64.exe") "f1236741544923cae67a7f8812c5c8cfec729bc038d07920bbc677186941a003"
  # A name that is only a prefix of another, or absent, finds nothing.
  assert equal (rio checksum-for $checksums "rio-portable") null
  assert equal (rio checksum-for "" "rio-portable-x86_64.exe") null
}

@test
export def "every architecture with a Rio build has the ConPTY files to go with it" [] {
  assert equal ($rio.ASSETS | columns | sort) ($rio.CONPTY_FILES | columns | sort)
  for arch in ($rio.CONPTY_FILES | columns) {
    assert equal ($rio.CONPTY_FILES | get $arch | columns | sort) ["OpenConsole.exe" "conpty.dll"]
  }
}

@test
export def "Rio is installed one way only" [] {
  # winget's Rio is the per-machine MSI that lib/rio.nu replaces; listing both
  # would put two Rios on the machine, and the MSI's upgrades would need the
  # administrator this avoids.
  assert not ("raphamorim.rio" in $windows.EXTRA)
}
