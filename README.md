# WezTerm Dotfiles

This repository tracks the minimum files needed to reproduce the current WezTerm setup on a new Windows machine:

- `.wezterm.lua`
- `Documents/PowerShell/Microsoft.PowerShell_profile.ps1`

The WezTerm config controls tab naming and UI behavior.
The PowerShell profile sends OSC 7 so WezTerm can track the current directory after `cd`.

## Files

- [`/.wezterm.lua`](C:\Users\cnnby\.wezterm.lua): WezTerm config
- [`/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`](C:\Users\cnnby\Documents\PowerShell\Microsoft.PowerShell_profile.ps1): PowerShell prompt hook for OSC 7
- [`/scripts/install.ps1`](C:\Users\cnnby\scripts\install.ps1): install/copy these files onto a new machine

## Install On A New Machine

1. Install WezTerm Nightly.
2. Install PowerShell 7.
3. Clone this repository anywhere.
4. In PowerShell, run:

```powershell
pwsh -NoLogo -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

5. Restart WezTerm, or reload config with `Ctrl+b r`.
6. Open a new PowerShell tab.

## What The Installer Does

- Copies `.wezterm.lua` to `$HOME\.wezterm.lua`
- Copies `Microsoft.PowerShell_profile.ps1` to `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
- Creates a timestamped backup if either target file already exists

## Notes

- Directory tracking depends on the PowerShell profile. If only `.wezterm.lua` is copied, tab titles will not follow `cd` reliably.
- The PowerShell profile only emits OSC 7 when `TERM_PROGRAM=WezTerm`, so it is safe to reuse in other terminals.
- `im-select.exe` is referenced by `.wezterm.lua`. If a new machine does not have it, either install it or remove that hook.
