# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog and adheres to Semantic Versioning.

## [1.2.1] - 2025-08-26
### Added
- Voice functionality documentation and setup guidance (Whisper integration) in README.
- Comment-based help for exported functions (Get-Help support).
- Publish helper script `Publish-PwshCopilot.ps1` for safe, repeatable releases.
- Metadata (Tags, ProjectUri, LicenseUri, IconUri, ReleaseNotes) in module manifest.

### Changed
- Refined exported function list to only public, supported commands.
- Enhanced README with installation, troubleshooting, contributing, and roadmap sections.

### Removed
- Hidden legacy internal voice session entry points from manifest export list (kept internal).

## [1.2.0] - 2025-08-??
### Added
- Initial public voice session scaffolding (pre-docs).

## [1.0.0] - 2025-07-??
### Added
- Initial release: core LLM suggestion, explanation, script generation, chat session, AI completions.

[1.2.1]: https://github.com/Zubair-DS/PwshCopilot/releases/tag/v1.2.1
