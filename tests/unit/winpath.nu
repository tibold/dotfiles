use ../../lib/winpath.nu
use std/testing *
use std/assert

# lib/winpath.nu's merge is pure, so these run on every platform with fixture
# strings in place of the registry.

@test
export def "the rebuilt PATH puts the prepends first, then machine, then user" [] {
  let got = (winpath merge [] 'C:\Windows;C:\Program Files\Git\cmd' 'C:\Users\me\bin' --prepend ['C:\Users\me\.local\bin'])
  assert equal $got ['C:\Users\me\.local\bin' 'C:\Windows' 'C:\Program Files\Git\cmd' 'C:\Users\me\bin']
}

@test
export def "an MSI directory that only the registry knows about is picked up" [] {
  let current = ['C:\Windows' 'C:\Users\me\AppData\Local\Microsoft\WinGet\Links']
  let got = (winpath merge $current 'C:\Windows;C:\Program Files\PowerShell\7\' '')
  assert ('C:\Program Files\PowerShell\7\' in $got)
}

@test
export def "directories already on PATH but not in the registry are kept at the end" [] {
  # What bootstrap.ps1 or Git Bash added for this session only.
  let got = (winpath merge ['C:\Program Files\Git\usr\bin' 'C:\Windows'] 'C:\Windows' '')
  assert equal $got ['C:\Windows' 'C:\Program Files\Git\usr\bin']
}

@test
export def "each directory appears once, whatever its case or trailing separator" [] {
  let got = (winpath merge ['c:\windows\'] 'C:\Windows;C:\WINDOWS' 'C:\Windows/' --prepend ['C:\Windows'])
  assert equal $got ['C:\Windows']
}

@test
export def "empty and blank entries in the registry value are dropped" [] {
  let got = (winpath merge [] 'C:\Windows;;  ;' '')
  assert equal $got ['C:\Windows']
}

@test
export def "a user with no PATH of their own still gets the machine one" [] {
  assert equal (winpath merge [] 'C:\Windows' '') ['C:\Windows']
}
