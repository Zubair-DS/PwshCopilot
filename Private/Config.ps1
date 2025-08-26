$Script:ConfigPath = "$env:USERPROFILE\.pwshcopilot_config.json"
$ConfigPath = $Script:ConfigPath

<#
.SYNOPSIS
Initialize or reconfigure core LLM provider settings for PwshCopilot.
.DESCRIPTION
Creates or updates the JSON configuration file storing provider choice (Azure OpenAI / OpenAI / Claude) and required authentication & model/deployment values. Prompts interactively for missing fields. Use -Force to overwrite existing config.
.PARAMETER Force
Re-run interactive setup even if a valid configuration exists.
.EXAMPLE
Initialize-PwshCopilot -Force
Re-enters setup allowing provider/model changes.
#>
function Initialize-PwshCopilot {
    param([switch]$Force)
    # Ensure config exists and has required provider-specific fields
    $needsConfig = $true
    if (-not $Force) {
        if (Test-Path $ConfigPath) {
            try {
                $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
                # Back-compat: if no Provider, assume AzureOpenAI
                if (-not $config.Provider) { $config | Add-Member -NotePropertyName Provider -NotePropertyValue 'AzureOpenAI' -Force }

                $isValid = $false
                switch ($config.Provider) {
                    'OpenAI' {
                        if ($config.ApiKey -and $config.Model) { $isValid = $true }
                    }
                    'Claude' {
                        if ($config.ApiKey -and $config.Model -and $config.AnthropicVersion) { $isValid = $true }
                    }
                    default { # AzureOpenAI
                        if ($config.Endpoint -and $config.ApiKey -and $config.ApiVersion -and $config.Deployment) { $isValid = $true }
                    }
                }

                if ($isValid) { $needsConfig = $false }
            }
            catch {
                $needsConfig = $true
            }
        }
    }

    if ($needsConfig) {
        Write-Host "Welcome to PwshCopilot! Let's set up your LLM connection..." -ForegroundColor Cyan
        Write-Host "Choose provider:" -ForegroundColor Cyan
        Write-Host "  1) Azure OpenAI" -ForegroundColor Cyan
        Write-Host "  2) OpenAI" -ForegroundColor Cyan
        Write-Host "  3) Claude (Anthropic)" -ForegroundColor Cyan
        $choice = Read-Host "Enter 1, 2, or 3"
        switch ($choice) {
            '2' { $provider = 'OpenAI' }
            '3' { $provider = 'Claude' }
            default { $provider = 'AzureOpenAI' }
        }

        if ($Force -and (Test-Path $ConfigPath)) {
            Write-Host "Overwriting existing configuration at $ConfigPath" -ForegroundColor Yellow
        }

        switch ($provider) {
            'OpenAI' {
                $apikey = Read-Host "Enter your OpenAI API key"
                $model = Read-Host "Enter the OpenAI model (e.g., gpt-4o-mini)"
                if ([string]::IsNullOrWhiteSpace($model)) { $model = 'gpt-4o-mini' }
                $config = @{
                    Provider = 'OpenAI'
                    ApiKey   = $apikey
                    Model    = $model
                    # BaseUrl optional: default https://api.openai.com/v1
                }
            }
            'Claude' {
                $apikey = Read-Host "Enter your Anthropic API key"
                $model = Read-Host "Enter the Claude model (e.g., claude-3-5-sonnet-20240620)"
                if ([string]::IsNullOrWhiteSpace($model)) { $model = 'claude-3-5-sonnet-20240620' }
                $anthVer = Read-Host "Enter Anthropic API version (default: 2023-06-01)"
                if ([string]::IsNullOrWhiteSpace($anthVer)) { $anthVer = '2023-06-01' }
                $config = @{
                    Provider          = 'Claude'
                    ApiKey            = $apikey
                    Model             = $model
                    AnthropicVersion  = $anthVer
                    # BaseUrl optional: default https://api.anthropic.com/v1
                }
            }
            default { # AzureOpenAI
                $endpoint = Read-Host "Enter your Azure OpenAI endpoint (e.g., https://your-resource-name.openai.azure.com)"
                $apikey = Read-Host "Enter your API key"
                $apiversion = Read-Host "Enter your API version (e.g., 2024-12-01-preview)"
                $deployment = Read-Host "Enter your deployment name"

                # Normalize endpoint by trimming trailing slashes
                if ($endpoint) { $endpoint = $endpoint.TrimEnd('/') }

                $config = @{
                    Provider  = 'AzureOpenAI'
                    Endpoint  = $endpoint
                    ApiKey    = $apikey
                    ApiVersion = $apiversion
                    Deployment = $deployment
                }
            }
        }

        $config | ConvertTo-Json | Set-Content -Path $ConfigPath
        Write-Host "Configuration saved to $ConfigPath" -ForegroundColor Green
    }
}

function Get-PSCopilotConfig {
    if (-not (Test-Path $ConfigPath)) {
        Initialize-PwshCopilot
    }

    try {
        $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    }
    catch {
        Write-Host "Existing configuration file is invalid JSON. Re-initializing..." -ForegroundColor Yellow
        Initialize-PwshCopilot
        $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    }

    # Back-compat: default to Azure if Provider missing
    if (-not $config.Provider) { $config | Add-Member -NotePropertyName Provider -NotePropertyValue 'AzureOpenAI' -Force }

    $missing = @()
    switch ($config.Provider) {
        'OpenAI' {
            if ([string]::IsNullOrWhiteSpace($config.ApiKey)) { $missing += 'ApiKey' }
            if ([string]::IsNullOrWhiteSpace($config.Model)) { $missing += 'Model' }
        }
        'Claude' {
            if ([string]::IsNullOrWhiteSpace($config.ApiKey)) { $missing += 'ApiKey' }
            if ([string]::IsNullOrWhiteSpace($config.Model)) { $missing += 'Model' }
            if ([string]::IsNullOrWhiteSpace($config.AnthropicVersion)) { $missing += 'AnthropicVersion' }
        }
        default { # AzureOpenAI
            if ([string]::IsNullOrWhiteSpace($config.Endpoint)) { $missing += 'Endpoint' }
            if ([string]::IsNullOrWhiteSpace($config.ApiKey)) { $missing += 'ApiKey' }
            if ([string]::IsNullOrWhiteSpace($config.ApiVersion)) { $missing += 'ApiVersion' }
            if ([string]::IsNullOrWhiteSpace($config.Deployment)) { $missing += 'Deployment' }
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host ("Configuration missing fields: {0}. Launching setup..." -f ($missing -join ', ')) -ForegroundColor Yellow
        Initialize-PwshCopilot
        $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    }

    return $config
}

if ($MyInvocation.InvocationName -ne '.') {
    Initialize-PwshCopilot -Force
}

<#
VOICE CONFIGURATION
Adds parallel setup for Azure Speech (STT/TTS) similar to LLM provider configuration.
Persists additional JSON keys in the existing config file:
  SpeechProvider (currently only 'AzureSpeech')
  SpeechKey
  SpeechRegion
  SpeechVoice (optional, default en-US-JennyNeural)
Use Initialize-PwshCopilotVoice (or alias Initialize-VoiceCopilot) to configure / reconfigure.
Get-PSCopilotVoiceConfig returns a validated hashtable or triggers setup if missing.
#>

<#
.SYNOPSIS
Configure voice / transcription provider (Azure Speech legacy or Azure OpenAI Whisper).
.DESCRIPTION
Adds or updates voice-related fields inside the shared configuration JSON. Supports switching between legacy Azure Speech (STT/TTS) and Whisper (speech→text only). When switching providers, removes obsolete keys from the other provider to keep config clean.
.PARAMETER Force
Re-run voice configuration even if an existing valid voice section is present.
.EXAMPLE
Initialize-PwshCopilotVoice
Interactive prompts for Whisper or Azure Speech settings.
#>
function Initialize-PwshCopilotVoice {
    [CmdletBinding()] param([switch]$Force)

    $config = $null
    if (Test-Path $ConfigPath) {
        try { $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json } catch { $config = [pscustomobject]@{} }
    } else { $config = [pscustomobject]@{} }

    $needsConfig = $Force
    if (-not $needsConfig) {
        if (-not $config.SpeechProvider) { $needsConfig = $true }
        elseif ($config.SpeechProvider -eq 'AzureSpeech' -and (-not $config.SpeechKey -or -not $config.SpeechRegion)) { $needsConfig = $true }
        elseif ($config.SpeechProvider -eq 'AzureOpenAIWhisper' -and (-not $config.WhisperEndpoint -or -not $config.WhisperApiKey -or -not $config.WhisperDeployment -or -not $config.WhisperApiVersion)) { $needsConfig = $true }
    }

    if (-not $needsConfig) { Write-Verbose "Voice configuration already present. Use -Force to reconfigure."; return }

    Write-Host "Select voice / transcription provider:" -ForegroundColor Cyan
    Write-Host "  1) Azure Speech (legacy STT/TTS)" -ForegroundColor Cyan
    Write-Host "  2) Azure OpenAI Whisper (recommended)" -ForegroundColor Cyan
    $choice = Read-Host "Enter 1 or 2"
    switch ($choice) {
        '2' { $provider = 'AzureOpenAIWhisper' }
        default { $provider = 'AzureSpeech' }
    }

    if ($provider -eq 'AzureSpeech') {
        $speechKey = Read-Host "Enter your Azure Speech key"
        $speechRegion = Read-Host "Enter your Azure Speech region (e.g., eastus)"
        $speechVoice = Read-Host "Enter default voice (blank for en-US-JennyNeural)"
        if ([string]::IsNullOrWhiteSpace($speechVoice)) { $speechVoice = 'en-US-JennyNeural' }
        $config | Add-Member -NotePropertyName SpeechProvider -NotePropertyValue $provider -Force
        $config | Add-Member -NotePropertyName SpeechKey -NotePropertyValue $speechKey -Force
        $config | Add-Member -NotePropertyName SpeechRegion -NotePropertyValue $speechRegion -Force
        $config | Add-Member -NotePropertyName SpeechVoice -NotePropertyValue $speechVoice -Force
        # Clean Whisper keys if switching
        'WhisperEndpoint','WhisperApiKey','WhisperDeployment','WhisperApiVersion' | ForEach-Object { if ($config.PSObject.Properties.Name -contains $_) { $config.PSObject.Properties.Remove($_) } }
    }
    else { # AzureOpenAIWhisper
        $wEndpoint = Read-Host "Enter Whisper Azure OpenAI endpoint (e.g., https://your-resource.openai.azure.com)"
        if ($wEndpoint) { $wEndpoint = $wEndpoint.TrimEnd('/') }
        $wKey = Read-Host "Enter Whisper Azure OpenAI API key"
        $wDeployment = Read-Host "Enter Whisper deployment name (default: whisper)"
        if ([string]::IsNullOrWhiteSpace($wDeployment)) { $wDeployment = 'whisper' }
        $wApiVersion = Read-Host "Enter Whisper API version (default: 2023-09-01-preview)"
        if ([string]::IsNullOrWhiteSpace($wApiVersion)) { $wApiVersion = '2023-09-01-preview' }
        $config | Add-Member -NotePropertyName SpeechProvider -NotePropertyValue $provider -Force
        $config | Add-Member -NotePropertyName WhisperEndpoint -NotePropertyValue $wEndpoint -Force
        $config | Add-Member -NotePropertyName WhisperApiKey -NotePropertyValue $wKey -Force
        $config | Add-Member -NotePropertyName WhisperDeployment -NotePropertyValue $wDeployment -Force
        $config | Add-Member -NotePropertyName WhisperApiVersion -NotePropertyValue $wApiVersion -Force
        # Remove legacy speech fields if present (except SpeechProvider)
        'SpeechKey','SpeechRegion','SpeechVoice' | ForEach-Object { if ($config.PSObject.Properties.Name -contains $_) { $config.PSObject.Properties.Remove($_) } }
    }

    $config | ConvertTo-Json | Set-Content -Path $ConfigPath
    Write-Host "Voice/transcription configuration saved to $ConfigPath" -ForegroundColor Green
}

Set-Alias -Name Initialize-VoiceCopilot -Value Initialize-PwshCopilotVoice

<#
.SYNOPSIS
Retrieve (and if missing, create) the validated voice configuration.
.DESCRIPTION
Loads the combined configuration JSON, ensures required fields for the selected voice provider are present, and launches interactive setup if not. Returns the config object for downstream functions.
#>
function Get-PSCopilotVoiceConfig {
    $cfg = Get-PSCopilotConfig
    $missing = @()
    if (-not $cfg.SpeechProvider) { $missing += 'SpeechProvider' }
    elseif ($cfg.SpeechProvider -eq 'AzureSpeech') {
        if (-not $cfg.SpeechKey) { $missing += 'SpeechKey' }
        if (-not $cfg.SpeechRegion) { $missing += 'SpeechRegion' }
    }
    elseif ($cfg.SpeechProvider -eq 'AzureOpenAIWhisper') {
        foreach ($f in 'WhisperEndpoint','WhisperApiKey','WhisperDeployment','WhisperApiVersion') { if (-not $cfg.$f) { $missing += $f } }
    }
    if ($missing.Count -gt 0) {
        Write-Host ("Voice configuration missing fields: {0}. Launching setup..." -f ($missing -join ', ')) -ForegroundColor Yellow
        Initialize-PwshCopilotVoice
        $cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    }
    return $cfg
}

# Check and report missing prerequisites (ffmpeg, keys, etc.)
<#
.SYNOPSIS
Check presence of required external tools & voice config fields.
.DESCRIPTION
Validates availability of ffmpeg for microphone capture and required Whisper / Speech keys depending on provider. Returns $true if all mandatory elements exist; otherwise prints guidance. With -Silent, suppresses info output (still returns status).
.PARAMETER Silent
Reduce console output; only return success/failure.
.EXAMPLE
Test-PSCopilotPrerequisites
Displays missing components and install guidance.
#>
function Test-PSCopilotPrerequisites {
    [CmdletBinding()] param([switch]$Silent)
    $cfg = $null; try { $cfg = Get-PSCopilotConfig } catch {}
    $voice = $null; try { $voice = Get-PSCopilotVoiceConfig } catch {}

    $issues = @()
    $advise = @()

    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        $issues += 'ffmpeg (required for microphone audio capture)'
        $advise += 'Install ffmpeg: winget install Gyan.FFmpeg   OR   choco install ffmpeg -y   OR download: https://www.gyan.dev/ffmpeg/builds/'
    }

    if ($voice -and $voice.SpeechProvider -eq 'AzureOpenAIWhisper') {
        foreach ($f in 'WhisperEndpoint','WhisperApiKey','WhisperDeployment','WhisperApiVersion') {
            if (-not $voice.$f) { $issues += "Whisper field missing: $f" }
        }
    }
    elseif ($voice -and $voice.SpeechProvider -eq 'AzureSpeech') {
        foreach ($f in 'SpeechKey','SpeechRegion') { if (-not $voice.$f) { $issues += "Azure Speech field missing: $f" } }
    }

    if ($issues.Count -eq 0) {
        if (-not $Silent) { Write-Host 'PwshCopilot prerequisites: OK' -ForegroundColor Green }
        return $true
    }
    if (-not $Silent) {
        Write-Warning ('Missing prerequisites: ' + ($issues -join '; '))
        foreach ($a in $advise) { Write-Host $a -ForegroundColor Yellow }
    }
    return $false
}
