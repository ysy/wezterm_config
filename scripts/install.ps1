param(
    [string]$RepoRoot = $(Split-Path -Parent $PSScriptRoot),
    [string]$HomePath = $HOME
)

$ErrorActionPreference = "Stop"

function Backup-IfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$Path.bak.$timestamp"
        Copy-Item -Path $Path -Destination $backupPath -Force
        Write-Host "Backed up $Path -> $backupPath"
    }
}

$weztermSource = Join-Path $RepoRoot "wezterm.lua"
$user = $env:USERNAME
$weztermTarget = "C:\\Users\\$user\\.config\\wezterm\\wezterm.config"
$weztermTargetDir = Split-Path -Parent $weztermTarget

$profileSource = Join-Path $RepoRoot "Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1"
$profileDir = Join-Path $HomePath "Documents\\PowerShell"
$profileTarget = Join-Path $profileDir "Microsoft.PowerShell_profile.ps1"

if (-not (Test-Path $weztermSource)) {
    throw "Missing source file: $weztermSource"
}

if (-not (Test-Path $profileSource)) {
    throw "Missing source file: $profileSource"
}

New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
New-Item -ItemType Directory -Force -Path $weztermTargetDir | Out-Null

Backup-IfExists -Path $weztermTarget
Backup-IfExists -Path $profileTarget

Copy-Item -Path $weztermSource -Destination $weztermTarget -Force
Copy-Item -Path $profileSource -Destination $profileTarget -Force

Write-Host "Installed WezTerm config to $weztermTarget"
Write-Host "Installed PowerShell profile to $profileTarget"
Write-Host "Restart WezTerm or reload config with Ctrl+b r, then open a new pwsh tab."
