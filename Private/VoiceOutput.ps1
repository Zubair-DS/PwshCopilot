<#
.SYNOPSIS
    Basic Text-to-Speech helper leveraging Azure Speech (if available) or Windows SAPI.
.DESCRIPTION
    Invoke-PSCopilotVoiceOutput will speak text.
      Priority order:
        1. Azure Speech (env AZ_SPEECH_KEY + AZ_SPEECH_REGION) synthesizes to a WAV then plays (needs default Windows audio device).
        2. Windows SAPI.SpVoice COM as quick fallback.
.NOTES
    For Azure Speech you need:
      Set-Item Env:AZ_SPEECH_KEY    "<your key>"
      Set-Item Env:AZ_SPEECH_REGION "<region>"
    Optionally set AZ_SPEECH_VOICE (e.g. en-US-JennyNeural). Defaults to en-US-JennyNeural.
#>
function Invoke-PSCopilotVoiceOutput {
    [CmdletBinding()] param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline)] [string] $Text,
        [ValidateSet('auto','azure','local')] [string] $Engine = 'auto',
        [string] $OutFile,
        [switch] $PassThru
    )
    begin { $all = @() }
    process { if ($Text) { $all += $Text } }
    end {
        if (-not $all) { return }
        $fullText = ($all -join ' ')
        $haveAzure = $env:AZ_SPEECH_KEY -and $env:AZ_SPEECH_REGION
        if ($Engine -eq 'azure' -or ($Engine -eq 'auto' -and $haveAzure)) {
            $voice = if ($env:AZ_SPEECH_VOICE) { $env:AZ_SPEECH_VOICE } else { 'en-US-JennyNeural' }
            $ssml = "<speak version='1.0' xml:lang='en-US'><voice name='$voice'>$( [System.Web.HttpUtility]::HtmlEncode($fullText) )</voice></speak>"
            try {
                $endpoint = "https://$($env:AZ_SPEECH_REGION).tts.speech.microsoft.com/cognitiveservices/v1"
                $headers = @{ 'Ocp-Apim-Subscription-Key' = $env:AZ_SPEECH_KEY; 'Content-Type' = 'application/ssml+xml'; 'X-Microsoft-OutputFormat'='riff-16khz-16bit-mono-pcm' }
                $bytes = Invoke-RestMethod -Uri $endpoint -Method POST -Headers $headers -Body $ssml -ErrorAction Stop
                if (-not $OutFile) { $OutFile = Join-Path $env:TEMP ("pscopilot_tts_" + [guid]::NewGuid().ToString() + '.wav') }
                [IO.File]::WriteAllBytes($OutFile, $bytes)
                try { Add-Type -AssemblyName System.Media -ErrorAction SilentlyContinue; (New-Object System.Media.SoundPlayer $OutFile).PlaySync() } catch { Write-Verbose "Playback failed: $_" }
                if ($PassThru) { return $OutFile }
                return
            } catch { Write-Warning "Azure TTS failed: $_. Falling back to local." }
        }
        # Local fallback
        try {
            $voiceObj = New-Object -ComObject SAPI.SpVoice
            $voiceObj.Speak($fullText) | Out-Null
            if ($PassThru) { return $fullText }
        } catch { Write-Error "Local TTS failed: $_" }
    }
}

Export-ModuleMember -Function Invoke-PSCopilotVoiceOutput
