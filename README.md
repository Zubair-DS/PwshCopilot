# PwshCopilot

AI + Voice powered assistant for PowerShell.

Key features:
* Natural language → PowerShell command generation
* Command explanations (alias: `Explain-PSCommand`)
* Script scaffolding from descriptions
* Interactive chat session with confirm-before-run safety
* Optional voice-driven loop (Azure OpenAI Whisper transcription)
* Inline AI Tab completions aware of your last commands & errors

---
## 1. Install (Gallery)
```powershell
Install-Module PwshCopilot -Scope CurrentUser -Force
Import-Module PwshCopilot -Force   # triggers first-time setup prompts
```
Update later:
```powershell
Update-Module PwshCopilot
```

Minimum PowerShell: 5.1 (works in 7.x as well).

## 2. First-time setup
On first import you select: provider (Azure OpenAI / OpenAI / Anthropic), model/deployment name, and API key.

From a cloned repo (dev mode):
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module .\PwshCopilot.psd1 -Force
Get-PSCommandSuggestion -Description "list files"
```

Config is stored at: `$env:USERPROFILE\.pwshcopilot_config.json`.

## 3. Reconfigure / switch provider
```powershell
Remove-Item "$env:USERPROFILE\.pwshcopilot_config.json" -Force -ErrorAction SilentlyContinue
Import-Module PwshCopilot -Force   # or .\PwshCopilot.psd1
# or interactive re-run without deleting:
. .\Private\Config.ps1
Initialize-PwshCopilot -Force
```

## 4. Core usage
```powershell
Get-PSCommandSuggestion -Description "top 5 processes by CPU"
Get-PSCommandExplanation -Command "Get-Process | Sort-Object CPU -Descending | Select-Object -First 5"
New-PSHelperScript -Description "monitor disk space and alert if below 10%"
Enable-PSCopilotCompletion
Start-PSCopilotSession
```

## 5. Exported commands
| Command | Purpose |
|---------|---------|
| Get-PSCommandSuggestion | NL description → PowerShell command |
| Get-PSCommandExplanation (alias: Explain-PSCommand) | Explain a command |
| New-PSHelperScript | Generate & save a script from description |
| Start-PSCopilotSession | Text interactive chat |
| Enable-PSCopilotCompletion | AI Tab completions |
| Initialize-PwshCopilotVoice / Initialize-VoiceCopilot | Configure voice (Whisper) |
| Invoke-WhisperTranscription | Mic / file speech → text |
| Test-PSCopilotPrerequisites | Check ffmpeg & env readiness |
| Start-VoiceCopilot | Unified voice loop (primary entry) |

Legacy (still callable if present in session): `Invoke-PSCopilotVoiceInput`, `Invoke-PSCopilotVoiceOutput`.

## 6. Voice / Whisper setup
Prerequisites:
* `ffmpeg` (check: `ffmpeg -version`)
	* Install: `winget install Gyan.FFmpeg` OR `choco install ffmpeg -y`
* Working microphone

Configure:
```powershell
Initialize-PwshCopilotVoice   # alias: Initialize-VoiceCopilot
Test-PSCopilotPrerequisites
```
Prompts request:
* Whisper endpoint (Azure): https://<resource>.openai.azure.com
* API key (stored locally only)
* Deployment name (default: whisper)
* API version (default: 2024-06-01)

Usage:
```powershell
Invoke-WhisperTranscription -UseMicrophone -Seconds 5
Invoke-WhisperTranscription -AudioPath .\sample.wav
Start-VoiceCopilot -CaptureSeconds 5 -VerboseTranscripts
```

Confirmation flow:
1. Speak request
2. LLM proposes a command
3. Confirm via voice (yes/no) OR type y/n
4. Execute or skip, repeat; say "thank you" / "exit" to end

## 7. Quick verification checklist
```powershell
Import-Module PwshCopilot -Force
Get-Command -Module PwshCopilot | Select-Object Name
Test-PSCopilotPrerequisites
Get-PSCommandSuggestion -Description "list services"
Start-VoiceCopilot -CaptureSeconds 4   # after voice setup
```

## 8. Configuration file
Path: `$env:USERPROFILE\.pwshcopilot_config.json`
Delete to trigger fresh interactive setup.

## 9. Security notes
* Do NOT hard-code API keys in scripts; prefer `$env:OPENAI_API_KEY` or secure vaults.
* Generated commands are executed only after explicit confirmation (or your choice to paste them).
* Always review commands involving destructive actions (remove / stop / restart).

## 10. Contributing
Issues / PRs welcome at: https://github.com/Zubair-DS/PwshCopilot
Suggested workflow:
1. Fork & clone
2. Create feature branch: `git checkout -b feat/<short-name>`
3. Make changes, update README / inline help
4. Bump version (patch/minor as appropriate) in `PwshCopilot.psd1`
5. Run: `pwsh -NoProfile -Command "Test-ModuleManifest -Path .\\PwshCopilot.psd1 | Format-List ModuleVersion, FunctionsToExport"`
6. Submit PR with clear description & before/after examples

## 11. Releasing (maintainers)
1. Update `ModuleVersion` in `PwshCopilot.psd1`
2. Update this README (and optionally CHANGELOG)
3. Tag (optional): `git tag v<version>; git push origin v<version>`
4. Publish locally: 
```powershell
$key = Read-Host "NuGet API Key" -AsSecureString
Publish-Module -Path (Resolve-Path .) -NuGetApiKey ( [System.Net.NetworkCredential]::new('', $key).Password ) -Verbose
```
5. Verify on PowerShell Gallery

Avoid pasting raw API keys into history; use secure string or environment variable.

## 12. Troubleshooting
| Symptom | Fix |
|---------|-----|
| `ffmpeg` not found | Install via winget/choco; reopen terminal |
| No mic devices | List with: `Invoke-WhisperTranscription -UseMicrophone -ListDevices` |
| Empty transcription | Increase `-Seconds`, check input level, test plain ffmpeg recording |
| Slow responses | Reduce context (clear history), try smaller model/deployment |
| Tab completion silent | Re-run `Enable-PSCopilotCompletion` in current session |

## 13. Roadmap (ideas)
* Streaming partial suggestions
* Local model backend option
* Inline risk scoring for destructive commands
* TTS output for Whisper mode

## 14. License
See repository (add LICENSE file if missing).

---
Happy scripting!
