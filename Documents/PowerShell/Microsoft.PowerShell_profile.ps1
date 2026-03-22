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
        [scriptblock]$Command
    )

    Set-WezTermPaneTitle -Program $Program
    try {
        & $Command
    }
    finally {
        Send-WezTermOsc7
        Set-WezTermPaneTitle -Program "pwsh"
    }
}

function global:nvim {
    Invoke-WezTermTitledCommand -Program "nvim" -Command {
        & nvim.exe @args
    }
}

function global:vim {
    Invoke-WezTermTitledCommand -Program "vim" -Command {
        & vim.exe @args
    }
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
