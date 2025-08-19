
# PwshCopilot

![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PwshCopilot?label=PwshCopilot&logo=powershell)
![Downloads](https://img.shields.io/powershellgallery/dt/PwshCopilot)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-PowerShell%205.1%2B%20%7C%20Core%207+-purple)

## Post-installation: Required Setup for End Users

After installing the module with:
```powershell
Install-Module PwshCopilot -Scope CurrentUser
```
You must run the following commands to complete setup before using any features:
```powershell
Import-Module PwshCopilot
Initialize-PwshCopilot
```
This will prompt you to configure your LLM credentials. You only need to do this once, or whenever you want to change your provider or credentials.


A PowerShell Copilot with:
- Natural language → PowerShell commands
- Command explanations
- Full script generation
- Live inline suggestions with Tab-completion (Copilot-like)

## Installation
```powershell
Install-Module PwshCopilot -Scope CurrentUser
```



## First-time setup (required)
You must run the interactive setup to use LLM features. After installing the module, run:

```powershell
Import-Module PwshCopilot
Initialize-PwshCopilot
```

This will prompt you to choose an LLM provider and enter the required fields. If you skip this step, the first time you use any LLM-powered command (such as `Get-PSCommandSuggestion` or `Start-PSCopilotSession`), you will be prompted to complete the setup.

Providers:
- 1) Azure OpenAI
- 2) OpenAI
- 3) Claude (Anthropic)

## What's New in 1.2.0

- Automatic configuration reset on upgrade or reinstall so you re-enter credentials (ensures fresh, valid settings)
- Improved error handling: failed LLM calls clear invalid config and prompt you to re-run `Initialize-PwshCopilot`
- Documentation clean-up

If you upgrade from an earlier version, simply run:
```powershell
Import-Module PwshCopilot -Force
Initialize-PwshCopilot
```
to restore functionality.
## Troubleshooting

- If you are not prompted for LLM credentials, ensure the config file does not exist or is not corrupt:
	```powershell
	Remove-Item "$env:USERPROFILE\.pwshcopilot_config.json" -Force -ErrorAction SilentlyContinue
	Initialize-PwshCopilot
	```
- All LLM-powered commands will prompt for setup if configuration is missing or incomplete.

## Usage examples
```powershell
Get-PSCommandSuggestion -Description "top 5 processes by CPU"
Get-PSCommandExplanation -Command "Get-Process | Sort-Object CPU -Descending | Select-Object -First 5"
New-PSHelperScript -Description "monitor disk space and alert if below 10%"
Enable-PSCopilotCompletion
```

## Commands
- **Get-PSCommandSuggestion**: Convert a natural language description into a PowerShell command.
- **Get-PSCommandExplanation**: Explain what a PowerShell command does in plain English.
- **New-PSHelperScript**: Generate a PowerShell script from a description and save it to disk.
- **Start-PSCopilotSession**: Start an interactive session with inline AI suggestions.
- **Enable-PSCopilotCompletion**: Enable Tab-triggered AI completions for the current session.
- **Initialize-PwshCopilot**: Run interactive setup or reconfigure provider/credentials.

## Contributing

PwshCopilot is open source and welcomes contributions of all sizes:

1. Fork the repo and create a branch (`feature/your-idea`)
2. Run / update tests (none yet—see roadmap) and ensure scripts lint clean with PSScriptAnalyzer
3. Submit a Pull Request with a clear description and screenshots / transcripts where helpful

Please open an Issue first for larger changes (new providers, architectural changes) so we can discuss direction.

### Good First Contribution Ideas
- Add unit tests around config validation
- Add provider-specific key format pre-validation
- Add streaming output support
- Improve completion ranking heuristics
- Add a `Remove-PwshCopilotConfig` convenience function

## Roadmap (Early Draft)
- [ ] Pluggable provider model (drop new provider without core edits)
- [ ] Caching layer for repeated prompts
- [ ] Script inline annotations (explain each line)
- [ ] Optional telemetry (opt-in) for feature usage to guide roadmap
- [ ] Pester test suite
- [ ] GitHub Action: CI (PSScriptAnalyzer + minimal Pester tests)

## Security & Privacy
No credentials are stored outside your user profile config file. They are never sent anywhere except directly to the chosen LLM API endpoint. Always review generated commands before execution.

## Feedback & Recommendations
Have ideas to make this more useful? Open an Issue titled `Idea:` or start a Discussion. Looking especially for:
- Edge case prompts that failed or produced unsafe commands
- Desired providers / models
- UX improvements for the interactive session
- Completion speed & quality feedback

## Star & Share
If this helps you, please star the repository—it helps others discover it and guides future investment.
