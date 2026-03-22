$script:wezterm_original_prompt = $function:prompt

function global:prompt {
    $location = $executionContext.SessionState.Path.CurrentLocation

    if ($env:TERM_PROGRAM -eq "WezTerm" -and $location.Provider.Name -eq "FileSystem") {
        $ansi = [char]27
        $bel = [char]7
        $providerPath = $location.ProviderPath -replace "\\", "/"
        $osc7 = "$ansi]7;file://${env:COMPUTERNAME}/${providerPath}$bel"
        $Host.UI.Write($osc7)
    }

    if ($script:wezterm_original_prompt) {
        & $script:wezterm_original_prompt
        return
    }

    "PS $location$('>' * ($nestedPromptLevel + 1)) "
}
