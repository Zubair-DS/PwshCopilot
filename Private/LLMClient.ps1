function Invoke-PSCopilotLLM {
    param ([string]$Prompt)

    $config = Get-PSCopilotConfig

    try {
        switch ($config.Provider) {
            'OpenAI' {
                $baseUrl = if ($config.BaseUrl) { $config.BaseUrl.TrimEnd('/') } else { 'https://api.openai.com/v1' }
                $uri = "$baseUrl/chat/completions"
                $headers = @{
                    'Content-Type'  = 'application/json'
                    'Authorization' = "Bearer $($config.ApiKey)"
                }
                $body = @{
                    model       = $config.Model
                    messages    = @(@{ role = 'user'; content = $Prompt })
                    temperature = 0.2
                    max_tokens  = 256
                } | ConvertTo-Json -Depth 6

                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
                if ($response -and $response.choices -and $response.choices.Count -gt 0) {
                    return $response.choices[0].message.content
                }
                return $null
            }
            'Claude' {
                $baseUrl = if ($config.BaseUrl) { $config.BaseUrl.TrimEnd('/') } else { 'https://api.anthropic.com/v1' }
                $uri = "$baseUrl/messages"
                $headers = @{
                    'Content-Type'       = 'application/json'
                    'x-api-key'          = $config.ApiKey
                    'anthropic-version'  = $config.AnthropicVersion
                }
                $body = @{
                    model      = $config.Model
                    max_tokens = 256
                    messages   = @(@{
                        role    = 'user'
                        content = @(@{ type = 'text'; text = $Prompt })
                    })
                } | ConvertTo-Json -Depth 6

                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
                if ($response -and $response.content -and $response.content.Count -gt 0) {
                    return $response.content[0].text
                }
                return $null
            }
            default { # AzureOpenAI
                # {endpoint}/openai/deployments/{deployment}/chat/completions?api-version={apiVersion}
                $baseEndpoint = $config.Endpoint.TrimEnd('/')
                $deployment = $config.Deployment
                $apiVersion = $config.ApiVersion
                $uri = "$baseEndpoint/openai/deployments/$deployment/chat/completions?api-version=$apiVersion"

                $headers = @{
                    'Content-Type' = 'application/json'
                    'api-key'      = $config.ApiKey
                }

                $body = @{
                    messages    = @(@{ role = 'user'; content = $Prompt })
                    temperature = 0.2
                    max_tokens  = 256
                    # Azure uses deployment in the path; do not send "model"
                } | ConvertTo-Json -Depth 6

                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
                if ($response -and $response.choices -and $response.choices.Count -gt 0) {
                    return $response.choices[0].message.content
                }
                return $null
            }
        }
    }
    catch {
        Write-Error "LLM request failed: $_"
    }
}

# Chat-capable variant that preserves context
function Invoke-PSCopilotLLMChat {
    param (
        [Parameter(Mandatory=$true)] [object[]]$Messages,
        [string]$SystemPrompt
    )

    $config = Get-PSCopilotConfig

    try {
        switch ($config.Provider) {
            'OpenAI' {
                $baseUrl = if ($config.BaseUrl) { $config.BaseUrl.TrimEnd('/') } else { 'https://api.openai.com/v1' }
                $uri = "$baseUrl/chat/completions"
                $headers = @{
                    'Content-Type'  = 'application/json'
                    'Authorization' = "Bearer $($config.ApiKey)"
                }
                $msgs = @()
                if ($SystemPrompt) { $msgs += @{ role = 'system'; content = $SystemPrompt } }
                $msgs += $Messages
                $body = @{
                    model       = $config.Model
                    messages    = $msgs
                    temperature = 0.2
                    max_tokens  = 256
                } | ConvertTo-Json -Depth 6
                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
                if ($response -and $response.choices -and $response.choices.Count -gt 0) {
                    return $response.choices[0].message.content
                }
                return $null
            }
            'Claude' {
                $baseUrl = if ($config.BaseUrl) { $config.BaseUrl.TrimEnd('/') } else { 'https://api.anthropic.com/v1' }
                $uri = "$baseUrl/messages"
                $headers = @{
                    'Content-Type'       = 'application/json'
                    'x-api-key'          = $config.ApiKey
                    'anthropic-version'  = $config.AnthropicVersion
                }
                $claudeMsgs = @()
                foreach ($m in $Messages) {
                    $claudeMsgs += @{ role = $m.role; content = @(@{ type = 'text'; text = [string]$m.content }) }
                }
                $body = @{
                    model      = $config.Model
                    max_tokens = 256
                    messages   = $claudeMsgs
                }
                if ($SystemPrompt) { $body.system = $SystemPrompt }
                $bodyJson = $body | ConvertTo-Json -Depth 8
                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $bodyJson
                if ($response -and $response.content -and $response.content.Count -gt 0) {
                    return $response.content[0].text
                }
                return $null
            }
            default { # AzureOpenAI
                $baseEndpoint = $config.Endpoint.TrimEnd('/')
                $deployment = $config.Deployment
                $apiVersion = $config.ApiVersion
                $uri = "$baseEndpoint/openai/deployments/$deployment/chat/completions?api-version=$apiVersion"
                $headers = @{
                    'Content-Type' = 'application/json'
                    'api-key'      = $config.ApiKey
                }
                $msgs = @()
                if ($SystemPrompt) { $msgs += @{ role = 'system'; content = $SystemPrompt } }
                $msgs += $Messages
                $body = @{
                    messages    = $msgs
                    temperature = 0.2
                    max_tokens  = 256
                } | ConvertTo-Json -Depth 6
                $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
                if ($response -and $response.choices -and $response.choices.Count -gt 0) {
                    return $response.choices[0].message.content
                }
                return $null
            }
        }
    }
    catch {
        Write-Error "LLM request failed: $_"
    }
}
