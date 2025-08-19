<#
Template: Community LLM Provider for PwshCopilot
Copy to Providers/MyProvider.ps1 and edit values.

Required: call Register-PwshCopilotProvider -Name 'YourName' -Invoke { param($Prompt,$Context) ... }.
Optionally add -Validate { ... } to preflight credentials.
The Invoke scriptblock receives:
 - $Prompt : string (user prompt)
 - $Context : hashtable (may include History, LastError, etc. future use)
Return: string response text.
#>

Register-PwshCopilotProvider -Name 'SampleEcho' -Description 'Echoes the prompt back (demo)' -Invoke {
    param($Prompt,$Context)
    "[EchoProvider] $Prompt"
} -Validate {
    # Return $true / throw on invalid config; simple example
    return $true
}
