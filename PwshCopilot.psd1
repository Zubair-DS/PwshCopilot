@{
    RootModule        = 'PwshCopilot.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'f3b78a18-b1c3-4db6-a7a3-abcdef123456'
    Author            = 'PwshCopilot'
    CompanyName       = 'PwshCopilot'
    Copyright         = '(c) 2025 PwshCopilot. All rights reserved.'
    Description       = 'PowerShell Copilot using LLM API for natural language to PowerShell code suggestions.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-PSCommandSuggestion',
        'Get-PSCommandExplanation',
        'New-PSHelperScript',
        'Start-PSCopilotSession',
        'Invoke-PSCopilotDemo',
        'Enable-PSCopilotCompletion',
    'Initialize-PwshCopilot',
    'Get-PwshCopilotProviders',
    'Register-PwshCopilotProvider'
    )
    AliasesToExport = @('Explain-PSCommand')
    FileList = @('PwshCopilot.psm1')
}

