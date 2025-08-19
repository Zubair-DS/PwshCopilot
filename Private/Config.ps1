$Script:ConfigPath = "$env:USERPROFILE\.pwshcopilot_config.json"
$ConfigPath = $Script:ConfigPath

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
        while ($true) {
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
                    }
                }
                default { # AzureOpenAI
                    $endpoint = Read-Host "Enter your Azure OpenAI endpoint (e.g., https://your-resource-name.openai.azure.com)"
                    $apikey = Read-Host "Enter your API key"
                    $apiversion = Read-Host "Enter your API version (e.g., 2024-12-01-preview)"
                    $deployment = Read-Host "Enter your deployment name"
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

            # Basic error handling: check for obviously invalid input
            $invalid = $false
            switch ($provider) {
                'OpenAI' {
                    if ([string]::IsNullOrWhiteSpace($config.ApiKey) -or $config.ApiKey.Length -lt 10) { $invalid = $true }
                }
                'Claude' {
                    if ([string]::IsNullOrWhiteSpace($config.ApiKey) -or $config.ApiKey.Length -lt 10) { $invalid = $true }
                }
                default {
                    if ([string]::IsNullOrWhiteSpace($config.Endpoint) -or $config.Endpoint.Length -lt 10 -or [string]::IsNullOrWhiteSpace($config.ApiKey) -or $config.ApiKey.Length -lt 10) { $invalid = $true }
                }
            }
            if ($invalid) {
                Write-Host "Invalid or incomplete configuration. Please try again." -ForegroundColor Red
                Remove-Item $ConfigPath -Force -ErrorAction SilentlyContinue
                continue
            }
            break
        }
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
