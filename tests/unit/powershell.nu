use ../../steps/powershell.nu
use std/testing *
use std/assert

@test
export def "no profile yet means create" [] {
  assert equal (powershell stub-action null) "create"
}

@test
export def "the stub is recognised however it was saved" [] {
  assert equal (powershell stub-action $powershell.STUB) "ok"
  # Notepad writes CRLF; that is still our file.
  assert equal (powershell stub-action ($powershell.STUB | str replace --all "\n" "\r\n")) "ok"
  assert equal (powershell stub-action $"($powershell.STUB)\n\n") "ok"
}

@test
export def "anything else in the profile is kept, not overwritten" [] {
  assert equal (powershell stub-action "oh-my-posh init pwsh | Invoke-Expression") "backup"
}

@test
export def "the stub loads the linked profile" [] {
  assert str contains $powershell.STUB ".config/powershell/profile.ps1"
}
