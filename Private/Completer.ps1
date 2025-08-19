function Register-PSCopilotCompleter {
    Register-ArgumentCompleter -CommandName '*' -ParameterName '*' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $inputLine = $commandAst.Extent.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($inputLine)) { return }

        # Ask LLM: what should come next?
        $prompt = "User is typing a PowerShell command. Suggest the next possible continuation:\n$inputLine"
        $suggestion = Invoke-PSCopilotLLM -Prompt $prompt

        if ($suggestion) {
            [System.Management.Automation.CompletionResult]::new(
                $suggestion,
                $suggestion,
                'ParameterValue',
                "Suggested by PwshCopilot"
            )
        }
    }
}
