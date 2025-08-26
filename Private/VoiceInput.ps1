<#
.SYNOPSIS
    Speech-to-Text helper (Azure Speech preferred; falls back to Windows offline engine).

.DESCRIPTION
    Provides a simple function Invoke-PSCopilotVoiceInput that:
      1. If Azure Speech credentials (env vars AZ_SPEECH_KEY + AZ_SPEECH_REGION) are present and a WAV/PCM file path is passed, sends it to Azure Speech REST API and returns the transcript.
      2. If -UseMicrophone is specified, attempts a quick one-shot microphone capture to a temp WAV (requires ffmpeg.exe on PATH OR Windows SoundRecorder fallback) then transcribes.
      3. If Azure creds not present, falls back to the legacy System.Speech.Recognition API (Windows only) for a short dictation (English locale assumed) when -UseMicrophone.

    This is intentionally lightweight and not a full streaming implementation. Improve as needed.

.NOTES
    For Azure Speech:
      Set-Item Env:AZ_SPEECH_KEY    "<your key>"
      Set-Item Env:AZ_SPEECH_REGION "<region>"   # e.g. eastus

    Optional config extension: you can also store these in the JSON config if you extend Config.ps1.
#>

function Invoke-PSCopilotVoiceInput {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)] [string] $AudioPath,
        [switch] $UseMicrophone,
        [int] $Seconds = 5,
        [ValidateSet('azure','local','auto')] [string] $Engine = 'auto'
    )

    if ($UseMicrophone -and -not $AudioPath) {
        $AudioPath = Join-Path $env:TEMP ("pscopilot_voice_" + [guid]::NewGuid().ToString() + ".wav")
        Write-Verbose "Capturing microphone to $AudioPath for $Seconds second(s)..."
        if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
            # Capture default input (Windows). Adjust as needed for specific devices.
            # Uses dshow; if that fails, user must configure.
            $device = 'audio="virtual-audio-capturer"'
            try {
                ffmpeg -y -f dshow -i $device -t $Seconds -ac 1 -ar 16000 -acodec pcm_s16le $AudioPath 2>$null | Out-Null
            } catch { Write-Verbose "ffmpeg capture failed: $_" }
            if (-not (Test-Path $AudioPath)) { Write-Warning "ffmpeg didn't produce audio. Falling back to System.Speech capture." }
        }
        if (-not (Test-Path $AudioPath)) {
            try {
                Add-Type -AssemblyName System.Speech -ErrorAction Stop
                $rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine
                $rec.SetInputToDefaultAudioDevice()
                $rec.LoadGrammar([System.Speech.Recognition.DictationGrammar]::new())
                $rec.RecognizeAsyncStop()
                $rec.RecognizeAsyncCancel()
                $rec.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Single)
                Write-Host "Speak now..." -ForegroundColor Cyan
                $result = $rec.Recognize()
                if ($result) { return $result.Text }
                else { return $null }
            } catch { Write-Error "Local recognition failed: $_"; return }
        }
    }

    # Decide engine
    $haveAzure = $env:AZ_SPEECH_KEY -and $env:AZ_SPEECH_REGION
    if ($Engine -eq 'azure' -or ($Engine -eq 'auto' -and $haveAzure)) {
        if (-not $AudioPath) { Write-Error "AudioPath required for Azure STT (or use -UseMicrophone)."; return }
        if (-not (Test-Path $AudioPath)) { Write-Error "Audio file not found: $AudioPath"; return }
        try {
            $bytes = [IO.File]::ReadAllBytes($AudioPath)
            $endpoint = "https://$($env:AZ_SPEECH_REGION).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US"
            $headers = @{ 'Ocp-Apim-Subscription-Key' = $env:AZ_SPEECH_KEY; 'Content-Type' = 'audio/wav; codecs=audio/pcm; samplerate=16000' }
            $resp = Invoke-RestMethod -Uri $endpoint -Method POST -Headers $headers -Body $bytes -ErrorAction Stop
            if ($resp.DisplayText) { return $resp.DisplayText }
            if ($resp.RecognitionStatus) { Write-Verbose ($resp | ConvertTo-Json -Depth 5) }
            return $null
        } catch { Write-Error "Azure STT failed: $_"; return }
    }
    else {
        if (-not $UseMicrophone) { Write-Error "Local engine only supports -UseMicrophone currently."; return }
        # We already handled local path capture earlier (System.Speech) so if we get here no result
        return $null
    }
}

Export-ModuleMember -Function Invoke-PSCopilotVoiceInput
