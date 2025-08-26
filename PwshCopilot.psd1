@{
    RootModule        = 'PwshCopilot.psm1'
    ModuleVersion     = '1.2.1'
    GUID              = 'f3b78a18-b1c3-4db6-a7a3-abcdef123456'
    Author            = 'PwshCopilot'
    CompanyName       = 'PwshCopilot'
    Copyright         = '(c) 2025 PwshCopilot. All rights reserved.'
    Description       = 'PowerShell Copilot with LLM API and integrated voice input/output functionality.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-PwshCopilotVoice',
        'Test-PSCopilotPrerequisites',
        'Invoke-WhisperTranscription',
        'Get-PSCommandSuggestion',
        'Get-PSCommandExplanation',
        'New-PSHelperScript',
        'Start-PSCopilotSession',
        'Invoke-PSCopilotDemo',
        'Enable-PSCopilotCompletion',
        'Start-VoiceCopilot'
    )
    AliasesToExport = @('Explain-PSCommand','Initialize-VoiceCopilot')
    FileList = @('PwshCopilot.psm1')
    PrivateData = @{
        PSData = @{
            Tags        = @('AI','Copilot','PowerShell','LLM','Voice','Whisper','Automation')
            ProjectUri  = 'https://github.com/Zubair-DS/PwshCopilot'
            LicenseUri  = 'https://github.com/Zubair-DS/PwshCopilot/blob/main/LICENSE'
            IconUri     = 'https://raw.githubusercontent.com/Zubair-DS/PwshCopilot/main/icon.png'
            ReleaseNotes = 'v1.2.1: Added integrated voice (Whisper) docs, refined exported function list, metadata improvements.'
        }
    }
}

