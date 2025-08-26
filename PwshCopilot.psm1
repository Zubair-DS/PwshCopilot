# Load internals
. "$PSScriptRoot\Private\Config.ps1"
. "$PSScriptRoot\Private\LLMClient.ps1"
. "$PSScriptRoot\Private\Completer.ps1"
. "$PSScriptRoot\Private\WhisperClient.ps1"

# Explicitly export voice init if loaded (helps when reloading in existing session)
if (Get-Command Initialize-PwshCopilotVoice -ErrorAction SilentlyContinue) {
    Export-ModuleMember -Function Initialize-PwshCopilotVoice -Alias Initialize-VoiceCopilot -ErrorAction SilentlyContinue
}
if (Get-Command Test-PSCopilotPrerequisites -ErrorAction SilentlyContinue) {
    Export-ModuleMember -Function Test-PSCopilotPrerequisites -ErrorAction SilentlyContinue
}
if (Get-Command Invoke-WhisperTranscription -ErrorAction SilentlyContinue) {
    Export-ModuleMember -Function Invoke-WhisperTranscription -ErrorAction SilentlyContinue
}

# Ensure configuration on import (prompts on first run if missing)
Initialize-PwshCopilot

function Get-PSCommandSuggestion {
    param([string]$Description)
    $prompt = "Convert to PowerShell:\n$Description"
    Invoke-PSCopilotLLM -Prompt $prompt
}
Export-ModuleMember -Function Get-PSCommandSuggestion -ErrorAction SilentlyContinue

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
Export-ModuleMember -Function Get-PSCommandExplanation -Alias Explain-PSCommand -ErrorAction SilentlyContinue

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
Export-ModuleMember -Function New-PSHelperScript -ErrorAction SilentlyContinue

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
Export-ModuleMember -Function Start-PSCopilotSession -ErrorAction SilentlyContinue

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
Export-ModuleMember -Function Invoke-PSCopilotDemo -ErrorAction SilentlyContinue

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
Export-ModuleMember -Function Enable-PSCopilotCompletion -ErrorAction SilentlyContinue

# Voice-driven session: capture spoken requests -> generate command -> confirm -> optional execute
function Start-PSCopilotVoiceSession {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [int] $CaptureSeconds = 5,
        [switch] $AutoExecuteOnSingleSuggestion,
        [switch] $NoAudioOutput,
        [switch] $VerboseTranscripts,
        [string] $DeviceName
    )

    # Ensure configs
    if (-not (Test-PSCopilotPrerequisites -Silent)) {
        Write-Host "Run 'Test-PSCopilotPrerequisites' after installing missing components, then retry." -ForegroundColor Yellow
    }
    $voiceCfg = $null
    try { $voiceCfg = Get-PSCopilotVoiceConfig } catch { Write-Warning "Voice config incomplete; continuing with local fallback if available." }

    # Choose transcription + (optional) output strategy based on provider
    $useWhisper = $voiceCfg -and $voiceCfg.SpeechProvider -eq 'AzureOpenAIWhisper'
    if ($useWhisper) {
        $transcribe = { param($secs,$dev) Invoke-WhisperTranscription -UseMicrophone -Seconds $secs -DeviceName $dev }
        $speak = { param($text) Write-Host $text -ForegroundColor Gray } # No TTS path for Whisper (yet)
    }
    else {
        $transcribe = { param($secs,$dev) Invoke-PSCopilotVoiceInput -UseMicrophone -Seconds $secs }
        $speak = { param($text) if (-not $NoAudioOutput) { $text | Invoke-PSCopilotVoiceOutput } else { Write-Host $text -ForegroundColor Gray } }
    }

    $systemPrompt = "Convert user's natural language request into a valid PowerShell command. Do not execute. Return only the command." # As requested

    Write-Host "Voice session started. When prompted, speak your request then stay silent. Say 'thank you' or 'exit' to finish." -ForegroundColor Cyan

    $exit = $false
    while (-not $exit) {
        Write-Host "Listening ($CaptureSeconds s)..." -ForegroundColor DarkGray
    $userText = & $transcribe $CaptureSeconds $DeviceName
        if (-not $userText -and ($voiceCfg.SpeechProvider -eq 'AzureOpenAIWhisper')) {
            if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
                Write-Warning "ffmpeg not found. Install it (e.g. winget install Gyan.FFmpeg) OR record a WAV and pass -AudioPath via Invoke-WhisperTranscription."; break
            }
            Write-Host "(No audio captured. If this persists, list devices with: Invoke-WhisperTranscription -UseMicrophone -ListDevices)" -ForegroundColor Yellow
        }
        if ($VerboseTranscripts) { Write-Host "[You]: $userText" -ForegroundColor Magenta }
        if (-not $userText) { Write-Host "(No speech detected)" -ForegroundColor Yellow; continue }
        if (Test-PSCopilotExitIntent -Text $userText) { break }

        # Build single-turn messages for clarity
        $messages = @(@{ role = 'user'; content = $userText })
        Write-Host "Processing (transcription -> command)..." -ForegroundColor DarkGray
        $command = Invoke-PSCopilotLLMChat -Messages $messages -SystemPrompt $systemPrompt
        if ([string]::IsNullOrWhiteSpace($command)) {
            $speak = "I couldn't derive a command. Please try again.";
            if (-not $NoAudioOutput) { $speak | Invoke-PSCopilotVoiceOutput } else { Write-Host $speak -ForegroundColor Yellow }
            continue
        }

        # Strip any accidental formatting (code fences)
        $command = ($command -replace '(?s)```(?:powershell|ps1)?','' -replace '```','').Trim()

        Write-Host "Suggested command:" -ForegroundColor Green
        Write-Host $command -ForegroundColor Cyan

        if ($AutoExecuteOnSingleSuggestion) {
            Write-Host "(AutoExecute enabled)" -ForegroundColor Yellow
            try { Invoke-Expression -Command $command } catch { Write-Error $_ }
            continue
        }

        $confirmPrompt = "Confirm (voice: say yes/no OR type y/n). Press Enter to skip confirmation and speak a new request.";
        Write-Host $confirmPrompt -ForegroundColor Gray
        # Offer immediate typed answer
        $typedFirst = Read-Host "Type y to run, n to skip, or just Enter to use voice"
        $confirmSpeech = $null
        if (-not [string]::IsNullOrWhiteSpace($typedFirst)) {
            $norm = $typedFirst.ToLowerInvariant()
        } else {
            Write-Host "Listening (confirmation 3s)..." -ForegroundColor DarkGray
            $confirmSpeech = & $transcribe 3 $DeviceName
            if ($VerboseTranscripts) { Write-Host "[Confirm]: $confirmSpeech" -ForegroundColor DarkCyan }
            if (-not $confirmSpeech) { continue }
            if (Test-PSCopilotExitIntent -Text $confirmSpeech) { $exit = $true; break }
            $norm = $confirmSpeech.ToLowerInvariant()
        }
        $yesTokens = 'y','yes','yeah','sure','run','execute','do it'
        $noTokens  = 'n','no','nope','skip','cancel'
        if ($yesTokens -contains $norm) {
            try {
                if ($PSCmdlet.ShouldProcess($command,'Invoke generated command')) {
                    Write-Host "Executing..." -ForegroundColor Yellow
                    Invoke-Expression -Command $command | Out-Host
                    Write-Host "Done." -ForegroundColor DarkGray
                } else {
                    Write-Host "WhatIf: Skipped execution." -ForegroundColor DarkYellow
                }
            } catch { Write-Error $_ }
        }
        elseif ($noTokens -contains $norm) {
            Write-Host "Skipped." -ForegroundColor DarkYellow
            continue
        }
        else {
            # Treat as next request text: loop continues using this as new userText (tail recursion style)
            if ($VerboseTranscripts) { Write-Host "Treating confirmation speech as new request." -ForegroundColor DarkYellow }
            $userText = if ($confirmSpeech) { $confirmSpeech } else { $typedFirst }
            if (Test-PSCopilotExitIntent -Text $userText) { $exit = $true; break }
            $messages = @(@{ role = 'user'; content = $userText })
            $command = Invoke-PSCopilotLLMChat -Messages $messages -SystemPrompt $systemPrompt
            if ($command) {
                $command = ($command -replace '(?s)```(?:powershell|ps1)?','' -replace '```','').Trim()
                Write-Host "Suggested command:" -ForegroundColor Green
                Write-Host $command -ForegroundColor Cyan
            }
        }
    }

    $goodbye = "Ending voice session. Goodbye.";
    Write-Host $goodbye -ForegroundColor Cyan
}


# Basic voice session (no TTS): voice -> text -> command -> voice confirm -> execute
function Start-PSCopilotVoiceSessionBasic {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [int] $CaptureSeconds = 5,
        [switch] $VerboseTranscripts,
        [string] $DeviceName
    )
    Write-Host "Basic voice session (no audio output). Say a request. Say 'thank you' or 'exit' to end." -ForegroundColor Cyan
    $systemPrompt = "Convert user's natural language request into a valid PowerShell command. Do not execute. Return only the command." 
    if (-not (Test-PSCopilotPrerequisites -Silent)) {
        Write-Host "Run 'Test-PSCopilotPrerequisites' after installing missing components, then retry." -ForegroundColor Yellow
    }
    $voiceCfg = $null
    try { $voiceCfg = Get-PSCopilotVoiceConfig } catch {}
    $useWhisper = $voiceCfg -and $voiceCfg.SpeechProvider -eq 'AzureOpenAIWhisper'
    if ($useWhisper) { $transcribe = { param($secs,$dev) Invoke-WhisperTranscription -UseMicrophone -Seconds $secs -DeviceName $dev } }
    else { $transcribe = { param($secs,$dev) Invoke-PSCopilotVoiceInput -UseMicrophone -Seconds $secs } }
    while ($true) {
    Write-Host "Listening ($CaptureSeconds s)..." -ForegroundColor DarkGray
    $request = & $transcribe $CaptureSeconds $DeviceName
        if ($VerboseTranscripts) { Write-Host "[You]: $request" -ForegroundColor Magenta }
        if (-not $request) { Write-Host "(No speech)" -ForegroundColor Yellow; continue }
        if (Test-PSCopilotExitIntent -Text $request) { break }
        $cmd = Invoke-PSCopilotLLMChat -Messages @(@{ role='user'; content=$request }) -SystemPrompt $systemPrompt
        if (-not $cmd) { Write-Host "(No command generated)" -ForegroundColor Yellow; continue }
        $cmd = ($cmd -replace '(?s)```(?:powershell|ps1)?','' -replace '```','').Trim()
        Write-Host "Suggested:" -ForegroundColor Green
        Write-Host $cmd -ForegroundColor Cyan
        Write-Host "Say yes to run, no to skip, or an exit phrase to stop." -ForegroundColor Gray
    Write-Host "Listening (confirmation 3s)..." -ForegroundColor DarkGray
    Write-Host "Confirm (voice yes/no OR type y/n)." -ForegroundColor Gray
    $typedFirst = Read-Host "Type y to run, n to skip, or Enter to use voice"
    $confirm = $null
    if ([string]::IsNullOrWhiteSpace($typedFirst)) {
        Write-Host "Listening (confirmation 3s)..." -ForegroundColor DarkGray
        $confirm = & $transcribe 3 $DeviceName
    } else { $confirm = $typedFirst }
    if ($VerboseTranscripts) { Write-Host "[Confirm]: $confirm" -ForegroundColor DarkCyan }
    if (-not $confirm) { continue }
        if (Test-PSCopilotExitIntent -Text $confirm) { break }
        $cNorm = $confirm.ToLowerInvariant()
        if ($cNorm -in @('y','yes','yeah','run','execute','sure')) {
            try {
                if ($PSCmdlet.ShouldProcess($cmd,'Invoke generated command')) {
                    Write-Host "Executing..." -ForegroundColor Yellow; Invoke-Expression -Command $cmd | Out-Host
                } else { Write-Host 'WhatIf: Skipped execution.' -ForegroundColor DarkYellow }
            } catch { Write-Error $_ }
        } elseif ($cNorm -in @('n','no','nope','skip','cancel')) {
            Write-Host "Skipped." -ForegroundColor DarkYellow
        } else {
            # treat as new request on next loop iteration by reassigning
            if (Test-PSCopilotExitIntent -Text $cNorm) { break }
        }
    }
    Write-Host "Voice session ended." -ForegroundColor Cyan
}


function Start-VoiceCopilot {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [int] $CaptureSeconds = 5,
        [switch] $VerboseTranscripts,
        [switch] $Basic,
        [string] $DeviceName
    )
    if ($Basic) {
        Start-PSCopilotVoiceSessionBasic -CaptureSeconds $CaptureSeconds -VerboseTranscripts:$VerboseTranscripts -DeviceName $DeviceName
    }
    else {
        Start-PSCopilotVoiceSession -CaptureSeconds $CaptureSeconds -VerboseTranscripts:$VerboseTranscripts -DeviceName $DeviceName
    }
}

Export-ModuleMember -Function Start-VoiceCopilot

