# pwsh profile, linked from the dotfiles repo (platform/windows/).
#
# $PROFILE itself lives under Documents -- which OneDrive may redirect -- so it
# is not linked. steps/powershell.nu writes a one-line stub there that
# dot-sources this file.
#
# Machine-specific settings go in ~/.config/powershell/local.ps1, which is not
# in the repo and is loaded last so it can override anything here.

# Only when it is not there already: a pwsh started from another pwsh inherits
# the parent's PATH, and prepending again at every level of nesting would
# stack up copies of it. Compared with one separator and no trailing one, and
# -eq ignores case, the way Windows compares paths.
$localBin = Join-Path $HOME '.local/bin'
$spell = { param($p) $p.Replace('/', '\').TrimEnd('\') }
$onPath = $env:PATH -split ';' | Where-Object { (& $spell $_) -eq (& $spell $localBin) }
if ((Test-Path $localBin) -and -not $onPath) { $env:PATH = "$localBin;$env:PATH" }

# psql, from `nu install.nu --with databases`. The EDB installer puts it in
# Program Files\PostgreSQL\<major>\bin and never on PATH; the newest major
# wins. Most machines never install it, so nothing happens when it is absent.
$pgBin = Get-ChildItem (Join-Path $env:ProgramFiles 'PostgreSQL\*\bin') -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [int]($_.Parent.Name -replace '\D', '') } -Descending | Select-Object -First 1
if ($pgBin -and -not ($env:PATH -split ';' | Where-Object { (& $spell $_) -eq (& $spell $pgBin.FullName) })) {
    $env:PATH = "$($pgBin.FullName);$env:PATH"
}

Set-Alias -Name k -Value kubectl
Set-Alias -Name tf -Value terraform
Set-Alias -Name vim -Value nvim

# The docker alias, as .zshrc does it on macOS: podman, but only when there is
# no real docker to shadow.
if ((Get-Command podman -ErrorAction SilentlyContinue) -and -not (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)) {
    Set-Alias -Name docker -Value podman
}

function reset-mouse-tracking {
    # psmux leaves any-event mouse tracking on when something exits badly, so mouse
    # moves arrive as input. Every report starts with ESC, which takes Escape and
    # nvim's Backspace down with it.
    [Console]::Write("`e[?1000l`e[?1002l`e[?1003l`e[?1005l`e[?1006l")
}

if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config (Join-Path $HOME '.config/oh-my-posh/archpillar-cyberpunk.omp.toml') | Invoke-Expression
}

# Rio's own shell integration, which reports the working directory with OSC 7
# at every prompt. Rio injects it by itself only into a bare pwsh, one it
# starts with no arguments, and Rio's config starts this one with some; Rio
# still names the script's directory in RIO_SHELL_INTEGRATION in every pane,
# so any shell can load it. After oh-my-posh, because it wraps the prompt
# function oh-my-posh defines. Rio uses the directory to resolve the relative
# paths a hint opens; on Windows it does not yet use it for new tabs.
if ($env:RIO_SHELL_INTEGRATION) {
    $rioScript = Join-Path $env:RIO_SHELL_INTEGRATION 'powershell/rio.ps1'
    if (Test-Path $rioScript) { . $rioScript }
}

# pwsh draws directories on a blue background bar by default, which no palette
# makes readable. Coloured text instead, from the terminal's own ANSI slots so
# it follows whatever palette Rio carries. $PSStyle is pwsh 7.2 and later.
if ($PSStyle) {
    $PSStyle.FileInfo.Directory = $PSStyle.Bold + $PSStyle.Foreground.Cyan
}

# Kept to one line on purpose: tests/unit/configs.nu checks that the last
# active line of this file is what loads local.ps1, so nothing added below
# this point can silently load after the machine-specific overrides.
$local = Join-Path $HOME '.config/powershell/local.ps1'; if (Test-Path $local) { . $local }
