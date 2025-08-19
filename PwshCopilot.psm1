# Load internals
. "$PSScriptRoot\Private\Config.ps1"
. "$PSScriptRoot\Private\LLMClient.ps1"
. "$PSScriptRoot\Private\Completer.ps1"

# Load optional community providers from Providers/*.ps1
$providerFolder = Join-Path $PSScriptRoot 'Providers'
if (Test-Path $providerFolder) {
    Get-ChildItem -Path $providerFolder -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# Internal registry for dynamic providers
if (-not $Script:PwshCopilotProviders) { $Script:PwshCopilotProviders = @{} }

function Register-PwshCopilotProvider {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ScriptBlock]$Invoke,
        [ScriptBlock]$Validate,
        [string]$Description = 'Community provider'
    )
    $Script:PwshCopilotProviders[$Name] = [pscustomobject]@{
        Name        = $Name
        Invoke      = $Invoke
        Validate    = $Validate
        Description = $Description
        Registered  = (Get-Date)
    }
}

function Get-PwshCopilotProviders {
    [CmdletBinding()] param()
    $Script:PwshCopilotProviders.GetEnumerator() | ForEach-Object { $_.Value }
}


# Ensure configuration on import (prompts on first run if missing or on version change)
$PwshCopilotConfigPath = "$env:USERPROFILE\.pwshcopilot_config.json"
$PwshCopilotVersionPath = "$env:USERPROFILE\.pwshcopilot_version.txt"
$CurrentModuleVersion = '1.2.0'
if (Test-Path $PwshCopilotVersionPath) {
    $lastVersion = Get-Content $PwshCopilotVersionPath -ErrorAction SilentlyContinue
    if ($lastVersion -ne $CurrentModuleVersion) {
        Remove-Item $PwshCopilotConfigPath -Force -ErrorAction SilentlyContinue
        Write-Host "[PwshCopilot] Module upgraded or reinstalled. Please re-run Initialize-PwshCopilot to set up your LLM credentials." -ForegroundColor Yellow
    }
} else {
    # First install
    Remove-Item $PwshCopilotConfigPath -Force -ErrorAction SilentlyContinue
    Write-Host "[PwshCopilot] Please run 'Initialize-PwshCopilot' to set up your LLM credentials before using LLM features." -ForegroundColor Yellow
}
Set-Content -Path $PwshCopilotVersionPath -Value $CurrentModuleVersion -Force

function Get-PSCommandSuggestion {
    param([string]$Description)
    $prompt = "Convert to PowerShell:\n$Description"
    Invoke-PSCopilotLLM -Prompt $prompt
}

if ($MyInvocation.InvocationName -eq 'PwshCopilot') {
    Write-Host "[PwshCopilot] Please run 'Initialize-PwshCopilot' to set up your LLM credentials before using LLM features." -ForegroundColor Yellow
}
# Helper: extract PowerShell code from LLM responses
function Convert-LLMResponseToPSCommand {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $codeBlockMatch = [regex]::Match($Text, '(?s)```(?:[a-zA-Z]+)?\s*(.*?)```')
    if ($codeBlockMatch.Success) {
        return ($codeBlockMatch.Groups[1].Value.Trim())
    }

    $lines = $Text -split "(`r`n|`n|`r)"
    $candidateLines = $lines | Where-Object {
        $_ -and ($_ -match '(\||\b(Get|Set|New|Remove|Start|Stop|Restart|Invoke|Enable|Disable|Select|Sort|Where|ForEach|Import|Export|Test|Measure|Write|Add|Clear|Copy|Move|Rename|Join|Split|Out|Format)-\w+)')
    }
    if ($candidateLines.Count -gt 0) {
        return (($candidateLines -join "`n").Trim())
    }

    return $Text.Trim()
}

# Helper: detect exit intent from natural language
function Test-PSCopilotExitIntent {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $patterns = @(
        '^\s*(exit|quit|quite|q)\b',
        '^\s*(bye|goodbye)\b',
        '^\s*(end|stop|close|terminate)\b',
        'close\s+(the\s+)?(session|chat|pscopilotsession)\b',
        'end\s+(the\s+)?(session|chat)\b',
        '(session|chat)\s+(close|end)\b',
        '\bthank\s*(you)?\b'
    )
    foreach ($p in $patterns) {
        if ($Text -match $p) { return $true }
    }
    return $false
}

# Helper: detect assistant invitation to continue
function Test-PSCopilotInviteToContinue {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $patterns = @(
        'more\s+questions',
        'anything\s+else',
        'feel\s+free\s+to\s+ask',
        'let\s+me\s+know\s+if',
        'any\s+other\s+question',
        'what\s+else\s+can\s+i\s+help',
        'need\s+anything\s+else',
        'do\s+you\s+have\s+any\s+other'
    )
    foreach ($p in $patterns) { if ($Text -match $p) { return $true } }
    return $false
}

# Helper: detect a simple negative response like "no"
function Test-PSCopilotNegativeResponse {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $patterns = @(
        '^\s*(no|nope|nah)\b',
        '^\s*(not\s+now|nothing|all\s+good)\b',
        '^(that''s|that\s+is)\s+all\b',
        '^\s*(i\s*(am|''m)\s+good)\b',
        '^\s*(no\s+thanks?|no\s+thank\s+you)\b'
    )
    foreach ($p in $patterns) { if ($Text -match $p) { return $true } }
    return $false
}

function Get-PSCommandExplanation {
    param([string]$Command)
    $prompt = "Explain in plain English what this does:\n$Command"
    Invoke-PSCopilotLLM -Prompt $prompt
}
Set-Alias -Name Explain-PSCommand -Value Get-PSCommandExplanation

function New-PSHelperScript {
    param([string]$Description, [string]$OutputPath = "$env:USERPROFILE\Documents\PwshCopilot")
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }

    $prompt = "Write a PowerShell script to do:\n$Description"
    $script = Invoke-PSCopilotLLM -Prompt $prompt

    $fileName = "Script_{0}.ps1" -f (Get-Date -Format "yyyyMMdd_HHmmss")
    $filePath = Join-Path $OutputPath $fileName
    $script | Set-Content $filePath
    Write-Host "Script saved: $filePath"
}

function Start-PSCopilotSession {
	Write-Host "PwshCopilot session started. Type 'exit' to quit."
	$messages = @()
	$systemPrompt = "You are a helpful PowerShell assistant. Answer concisely. When asked to generate commands, return only PowerShell unless explanation is explicitly requested. Prefer single-line commands for direct execution."
	$awaitingMore = $false
	while ($true) {
		$inputText = Read-Host "You"
		if ($inputText -eq "exit") { break }
		if ([string]::IsNullOrWhiteSpace($inputText)) { continue }

		if (Test-PSCopilotExitIntent -Text $inputText) {
			Write-Host "Ending session. Goodbye!" -ForegroundColor Cyan
			break
		}

		if ($awaitingMore -and (Test-PSCopilotNegativeResponse -Text $inputText)) {
			Write-Host "Okay, closing the session. Goodbye!" -ForegroundColor Cyan
			break
		}

		$messages += @{ role = 'user'; content = $inputText }
		$response = Invoke-PSCopilotLLMChat -Messages $messages -SystemPrompt $systemPrompt
		if (-not $response) { Write-Host "No response" -ForegroundColor Yellow; continue }

		$messages += @{ role = 'assistant'; content = $response }
		$awaitingMore = Test-PSCopilotInviteToContinue -Text $response

		$commandToRun = Convert-LLMResponseToPSCommand -Text $response

		Write-Host "Copilot:" -ForegroundColor Green
		Write-Host $response
		Write-Host "\nCommand candidate:" -ForegroundColor Green
		Write-Host $commandToRun -ForegroundColor Cyan

		$confirm = Read-Host "Run this command? (y/n)"
		if ($confirm -match '^(y|yes)$') {
			try {
				Write-Host "Executing..." -ForegroundColor Yellow
				Invoke-Expression -Command $commandToRun | Out-Host
			}
			catch {
				Write-Error $_
			}
		}
		else {
			Write-Host "Skipped."
		}
	}
}

function Invoke-PSCopilotDemo {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Prompts,
        [string]$ExitInput = 'thanks',
        [switch]$SimulateNoAfterInvite
    )

    $systemPrompt = 'You are a helpful PowerShell assistant. Answer concisely. When asked to generate commands, return only PowerShell unless explanation is explicitly requested. Prefer single-line commands for direct execution.'
    $messages = @()
    $awaitingMore = $false

    foreach ($p in $Prompts) {
        $messages += @{ role = 'user'; content = $p }
        $response = Invoke-PSCopilotLLMChat -Messages $messages -SystemPrompt $systemPrompt
        Write-Host "Assistant:" -ForegroundColor Green
        Write-Host $response
        $cmd = Convert-LLMResponseToPSCommand -Text $response
        Write-Host "Command:" -ForegroundColor Green
        Write-Host $cmd -ForegroundColor Cyan
        if ($cmd) {
            Write-Host "Executing..." -ForegroundColor Yellow
            Invoke-Expression -Command $cmd | Out-Host
        }
        $messages += @{ role = 'assistant'; content = $response }
        $awaitingMore = Test-PSCopilotInviteToContinue -Text $response
        if ($awaitingMore -and $SimulateNoAfterInvite) {
            Write-Host "User: no" -ForegroundColor Magenta
            if (Test-PSCopilotNegativeResponse -Text 'no') {
                Write-Host 'Okay, closing the session. Goodbye!' -ForegroundColor Cyan
                return
            }
        }
    }

    if (Test-PSCopilotExitIntent -Text $ExitInput) {
        Write-Host 'Ending session. Goodbye!' -ForegroundColor Cyan
    }
}

function Enable-PSCopilotCompletion {
    # Helper: Collect session context (recent commands + last error)
    function Get-PSCopilotContext {
        $history = (Get-History | Select-Object -Last 10 | ForEach-Object { $_.CommandLine }) -join "`n"
        $lastError = if ($Error.Count -gt 0) { $Error[0].ToString() } else { "" }

        return @{
            History   = $history
            LastError = $lastError
        }
    }

    # Override the completer to send context to LLM
    function Register-PSCopilotCompleter {
        Register-ArgumentCompleter -CommandName * -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParams)

            $context = Get-PSCopilotContext
            $prompt = @"
The user is typing a PowerShell command.
Recent history:
$($context.History)

Last error:
$($context.LastError)

Partial input: $wordToComplete
Suggest several possible next completions. Return them as a list.
"@

            # Call LLM using module helper
            $suggestions = Invoke-PSCopilotLLM -Prompt $prompt

            # Parse into multiple suggestions (split by newline or semicolon)
            $choices = $suggestions -split "[`n;]" | Where-Object { $_ -match '\\S' }

            foreach ($c in $choices) {
                [System.Management.Automation.CompletionResult]::new(
                    $c.Trim(),
                    $c.Trim(),
                    'ParameterValue',
                    $c.Trim()
                )
            }
        }
    }

    # Register the completer with AI backend
    Register-PSCopilotCompleter
    Write-Host "PwshCopilot live AI completion enabled! Use Tab to cycle through multiple AI suggestions."
}
