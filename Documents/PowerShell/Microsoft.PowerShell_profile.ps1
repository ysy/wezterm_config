$script:wezterm_original_prompt = $function:prompt

function Set-WezTermPaneTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Program,
        [string]$Directory = $executionContext.SessionState.Path.CurrentLocation.ProviderPath
    )

    if ($env:TERM_PROGRAM -ne "WezTerm") {
        return
    }

    $ansi = [char]27
    $bel = [char]7
    $dirName = Split-Path -Leaf $Directory

    if ([string]::IsNullOrWhiteSpace($dirName)) {
        $dirName = $Directory
    }

    $Host.UI.Write("$ansi]2;$Program-$dirName$bel")
}

function Send-WezTermOsc7 {
    $location = $executionContext.SessionState.Path.CurrentLocation

    if ($env:TERM_PROGRAM -ne "WezTerm" -or $location.Provider.Name -ne "FileSystem") {
        return
    }

    $ansi = [char]27
    $bel = [char]7
    $providerPath = $location.ProviderPath -replace "\\", "/"
    $Host.UI.Write("$ansi]7;file://${env:COMPUTERNAME}/${providerPath}$bel")
}

function Invoke-WezTermTitledCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Program,
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [AllowNull()]
        [object[]]$Arguments
    )

    if ($null -eq $Arguments) {
        $Arguments = @()
    }

    Set-WezTermPaneTitle -Program $Program
    try {
        & $Executable @Arguments
    }
    finally {
        Send-WezTermOsc7
        Set-WezTermPaneTitle -Program "pwsh"
    }
}

function Resolve-WezTermWrappedExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $resolved = Get-Command $CommandName -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -in @("Application", "ExternalScript") } |
        Select-Object -First 1

    if (-not $resolved) {
        return $null
    }

    return ($resolved.Path, $resolved.Source, $resolved.Definition | Where-Object { $_ } | Select-Object -First 1)
}

function Register-WezTermWrappedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Executable = $Name
    )

    $resolvedPath = Resolve-WezTermWrappedExecutable -CommandName $Executable
    if (-not $resolvedPath) {
        return
    }

    $escapedExecutable = $resolvedPath.Replace("'", "''")
    $escapedName = $Name.Replace("'", "''")
    $definition = @"
param([Parameter(ValueFromRemainingArguments = `$true)][object[]]`$CommandArgs)
Invoke-WezTermTitledCommand -Program '$escapedName' -Executable '$escapedExecutable' -Arguments `$CommandArgs
"@

    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($definition))
}

foreach ($commandName in @("nvim", "vim", "codex")) {
    Register-WezTermWrappedCommand -Name $commandName
}

function global:wtx {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Program,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$CommandArgs
    )

    $resolvedPath = Resolve-WezTermWrappedExecutable -CommandName $Program
    if (-not $resolvedPath) {
        throw "Command not found or not executable: $Program"
    }

    Invoke-WezTermTitledCommand -Program $Program -Executable $resolvedPath -Arguments $CommandArgs
}

function global:Add-WezTermWrappedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Executable = $Name
    )

    Register-WezTermWrappedCommand -Name $Name -Executable $Executable
    Write-Host "Registered WezTerm title wrapper for '$Name'."
}

function global:Show-WezTermWrappedCommands {
    @("nvim", "vim", "codex", "wtx <program> ...")
}

function global:prompt {
    Send-WezTermOsc7
    Set-WezTermPaneTitle -Program "pwsh"

    if ($script:wezterm_original_prompt) {
        & $script:wezterm_original_prompt
        return
    }

    $location = $executionContext.SessionState.Path.CurrentLocation
    "PS $location$('>' * ($nestedPromptLevel + 1)) "
}
