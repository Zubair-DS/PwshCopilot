<#!
.SYNOPSIS
Helper script to publish PwshCopilot to PowerShell Gallery safely.

.DESCRIPTION
Stages the module into a temporary versioned folder (ModuleName\<version>) so Publish-Module
uses the intended manifest (avoids accidentally publishing an older installed copy when using -Name).
Prompts securely for the NuGet API key if not supplied via parameter or environment variable NUGET_API_KEY.
Optionally auto-bumps the patch version in the manifest before staging (-BumpPatch).

.PARAMETER ApiKey
Plain text NuGet API key (not recommended). Prefer environment variable or secure prompt.

.PARAMETER BumpPatch
Increment patch portion of ModuleVersion in manifest before staging/publishing.

.EXAMPLE
pwsh ./Publish-PwshCopilot.ps1 -BumpPatch

.EXAMPLE
$env:NUGET_API_KEY = '...' ; pwsh ./Publish-PwshCopilot.ps1

.NOTES
Ensure you committed changes before publishing. After success, create a git tag (v<version>) if desired.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string] $ApiKey,
    [switch] $BumpPatch,
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot 'PwshCopilot.psd1'
if (-not (Test-Path $manifestPath)) { throw "Manifest not found at $manifestPath" }

Write-Host "Loading manifest: $manifestPath" -ForegroundColor Cyan
$manifest = Test-ModuleManifest -Path $manifestPath
$currentVersion = [version]$manifest.ModuleVersion

if ($BumpPatch) {
    $newVersion = [version]::new($currentVersion.Major, $currentVersion.Minor, $currentVersion.Build + 1)
    Write-Host "Bumping version $currentVersion -> $newVersion" -ForegroundColor Yellow
    (Get-Content $manifestPath) -replace "ModuleVersion\s*=\s*'${currentVersion}'","ModuleVersion     = '$newVersion'" | Set-Content $manifestPath
    $manifest = Test-ModuleManifest -Path $manifestPath
    $currentVersion = [version]$manifest.ModuleVersion
}

Write-Host "Preparing staging folder for version $currentVersion" -ForegroundColor Cyan
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) 'PwshCopilot_Stage'
if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force }
$moduleVersionFolder = Join-Path $stagingRoot (Join-Path 'PwshCopilot' $currentVersion.ToString())
New-Item -ItemType Directory -Path $moduleVersionFolder -Force | Out-Null

# Files to copy
$items = @('PwshCopilot.psd1','PwshCopilot.psm1','README.md','Private')
foreach ($i in $items) {
    $src = Join-Path $PSScriptRoot $i
    if (Test-Path $src) {
        Write-Host "Copying $i" -ForegroundColor DarkGray
        Copy-Item $src -Destination $moduleVersionFolder -Recurse -Force
    }
}

# Remove gallery metadata file if present (regenerated automatically after publish)
$psGetInfo = Join-Path $moduleVersionFolder 'PSGetModuleInfo.xml'
if (Test-Path $psGetInfo) { Remove-Item $psGetInfo -Force }

# Acquire API key securely
if (-not $ApiKey) { $ApiKey = $env:NUGET_API_KEY }
if (-not $ApiKey) {
    $sec = Read-Host 'Enter NuGet API Key' -AsSecureString
    $ApiKey = (New-Object System.Net.NetworkCredential('', $sec)).Password
}
if (-not $ApiKey) { throw 'NuGet API key not provided.' }

Write-Host "Staged path: $moduleVersionFolder" -ForegroundColor Green

if ($PSCmdlet.ShouldProcess("PwshCopilot $currentVersion","Publish to PowerShell Gallery")) {
    Publish-Module -Path $moduleVersionFolder -NuGetApiKey $ApiKey -Verbose
    Write-Host "Publish attempt complete. Verify with: Find-Module PwshCopilot -AllVersions | Sort-Object Version" -ForegroundColor Green
}
