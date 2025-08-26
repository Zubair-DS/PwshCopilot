<#
.SYNOPSIS
    Transcribe audio to text using Azure OpenAI Whisper deployment.
.DESCRIPTION
    Invoke-WhisperTranscription captures microphone audio (optional) or uses an existing wav file,
    then calls the Azure OpenAI Whisper REST endpoint:
      POST {endpoint}/openai/deployments/{deployment}/audio/transcriptions?api-version={apiVersion}
    Returns plain text transcription.

    Required config fields (stored via Initialize-PwshCopilotVoice when selecting Whisper):
      SpeechProvider      = 'AzureOpenAIWhisper'
      WhisperEndpoint     = 'https://<resource>.openai.azure.com'
      WhisperApiKey       = '<key>'
      WhisperDeployment   = 'whisper'
      WhisperApiVersion   = '2023-09-01-preview'

    NOTE: This uses basic ffmpeg capture if available; otherwise you must supply -AudioPath.
#>
function Invoke-WhisperTranscription {
    [CmdletBinding()] param(
        [switch] $UseMicrophone,
        [string] $AudioPath,
        [int] $Seconds = 5,
        [switch] $KeepTemp,
        [string] $ResponseFormat = 'text',
        [string] $DeviceName,
        [switch] $ListDevices
    )

    $cfg = Get-PSCopilotVoiceConfig
    if ($cfg.SpeechProvider -ne 'AzureOpenAIWhisper') {
        Write-Error "Voice provider is not AzureOpenAIWhisper. Run Initialize-PwshCopilotVoice to reconfigure."; return
    }
    foreach ($f in 'WhisperEndpoint','WhisperApiKey','WhisperDeployment','WhisperApiVersion') {
        if (-not $cfg.$f) { Write-Error "Missing config field $f"; return }
    }
    $endpoint = $cfg.WhisperEndpoint.TrimEnd('/')
    $deployment = $cfg.WhisperDeployment
    $apiVersion = $cfg.WhisperApiVersion

    if ($UseMicrophone -and -not $AudioPath) {
        if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            Write-Error "ffmpeg not found. Install ffmpeg (e.g. winget install Gyan.FFmpeg) or supply -AudioPath."; return
        }

        if ($ListDevices) {
            $list = ffmpeg -list_devices true -f dshow -i dummy 2>&1
            Write-Host "Available DirectShow audio devices:" -ForegroundColor Cyan
            $list | Where-Object { $_ -match 'DirectShow audio devices' -or $_ -match '".*"' } | ForEach-Object { Write-Host $_ }
            return
        }

        if (-not $DeviceName) {
            $list = ffmpeg -list_devices true -f dshow -i dummy 2>&1
            $micLine = ($list | Select-String -Pattern '".*Microphone.*"' | Select-Object -First 1).Line
            if (-not $micLine) { $micLine = ($list | Select-String -Pattern '"virtual-audio-capturer"' | Select-Object -First 1).Line }
            if (-not $micLine) { $micLine = ($list | Select-String -Pattern '".*"' | Select-Object -First 1).Line }
            if ($micLine -and $micLine -match '"([^"]+)"') { $DeviceName = $Matches[1]; Write-Verbose "Auto-selected audio device: $DeviceName" }
            else { Write-Warning "Could not auto-detect an audio device. Run Invoke-WhisperTranscription -UseMicrophone -ListDevices and specify -DeviceName."; return }
        }

        $AudioPath = Join-Path $env:TEMP ("pscopilot_whisper_" + [guid]::NewGuid().ToString() + '.wav')
        Write-Verbose "Capturing microphone ($Seconds s) from '$DeviceName' to $AudioPath"
        try {
            ffmpeg -y -f dshow -i audio="$DeviceName" -t $Seconds -ac 1 -ar 16000 -acodec pcm_s16le $AudioPath 2>$null | Out-Null
        } catch { Write-Error "ffmpeg capture failed: $_"; return }
    }

    if (-not $AudioPath -or -not (Test-Path $AudioPath)) { Write-Error "Audio file not found or not provided. If using microphone, list devices with: Invoke-WhisperTranscription -UseMicrophone -ListDevices"; return }

    try {
        $url = "$endpoint/openai/deployments/$deployment/audio/transcriptions?api-version=$apiVersion"

        $fileBytes = [IO.File]::ReadAllBytes($AudioPath)
        $ext = [IO.Path]::GetExtension($AudioPath).ToLowerInvariant()
        switch ($ext) {
            '.wav' { $mime = 'audio/wav' }
            '.mp3' { $mime = 'audio/mpeg' }
            default { $mime = 'application/octet-stream' }
        }
        $handler = New-Object System.Net.Http.HttpClientHandler
        $client  = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add('api-key', $cfg.WhisperApiKey)

        $content = New-Object System.Net.Http.MultipartFormDataContent
    # Use static ctor to avoid PS 5.1 treating byte[] as multiple args
    $ba = [System.Net.Http.ByteArrayContent]::new($fileBytes)
    $ba.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($mime)
        $content.Add($ba, 'file', [IO.Path]::GetFileName($AudioPath))
        if ($ResponseFormat) {
            $rf = New-Object System.Net.Http.StringContent($ResponseFormat)
            $content.Add($rf, 'response_format')
        }

        $response = $client.PostAsync($url, $content).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw "Whisper transcription failed: $($response.StatusCode) $body"
        }
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return ($text.Trim())
    }
    catch {
        Write-Error $_
    }
    finally {
        if (-not $KeepTemp -and $UseMicrophone -and (Test-Path $AudioPath)) { Remove-Item $AudioPath -Force -ErrorAction SilentlyContinue }
    }
}

Export-ModuleMember -Function Invoke-WhisperTranscription
