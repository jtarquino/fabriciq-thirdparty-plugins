#Requires -Version 5.1
<#
.SYNOPSIS
    Packages the Microsoft Fabric IQ plugin as a ZIP for the OpenAI plugin directory (ChatGPT and Codex).

.DESCRIPTION
    Packages only the files the Agent Plugins format needs (plugin.json, mcp.json, skills/, assets/,
    README.md, LICENSE) from plugins/fabriciq into dist/fabriciq-chatgpt.zip, with plugin.json at
    the ZIP root. Claude-only files (.claude-plugin/, .mcp.json) are left out.

.PARAMETER AllowPlaceholders
    Builds even if mcp.json still has the TODO client ID or plugin.json still has the REVIEW_*
    test-case placeholders. Use for local tests only. Alias: -AllowTodoClientId.
#>
[CmdletBinding()]
param(
    [Alias('AllowTodoClientId')]
    [switch]$AllowPlaceholders
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginDir = (Resolve-Path (Join-Path (Join-Path $repoRoot 'plugins') 'fabriciq')).Path
$distDir = Join-Path $repoRoot 'dist'
$zipPath = Join-Path $distDir 'fabriciq-chatgpt.zip'

$include = @('plugin.json', 'mcp.json', 'skills', 'assets', 'README.md', 'LICENSE')

foreach ($item in $include) {
    if (-not (Test-Path (Join-Path $pluginDir $item))) {
        throw "Missing required item: plugins/fabriciq/$item"
    }
}

foreach ($json in @('plugin.json', 'mcp.json')) {
    try {
        Get-Content (Join-Path $pluginDir $json) -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "plugins/fabriciq/$json is not valid JSON: $($_.Exception.Message)"
    }
}

$problems = @()
$mcp = Get-Content (Join-Path $pluginDir 'mcp.json') -Raw
$mcpServers = ($mcp | ConvertFrom-Json).mcpServers
$servers = @(if ($mcpServers) { $mcpServers.PSObject.Properties.Value })
# Every server needs a non-blank client ID; check each one rather than a filtered pipeline result.
$missingClientIds = @($servers | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.extensions.'com.openai'.auth.client.clientId)
    })
if ($mcp -match 'TODO-' -or $servers.Count -eq 0 -or $missingClientIds.Count -gt 0) {
    $problems += 'mcp.json has a missing, empty or TODO client ID'
}
if ((Get-Content (Join-Path $pluginDir 'plugin.json') -Raw) -match 'REVIEW_[A-Z_]+_ID') {
    $problems += 'plugin.json still has REVIEW_* test-case placeholders'
}
if ($problems) {
    $message = ($problems -join '; ') + '.'
    if ($AllowPlaceholders) {
        Write-Warning "$message Do not submit this package."
    }
    else {
        throw "$message Fix them, or pass -AllowPlaceholders for a local test build."
    }
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$files = foreach ($item in $include) {
    $path = Join-Path $pluginDir $item
    if (Test-Path $path -PathType Container) {
        Get-ChildItem $path -Recurse -File |
            Where-Object { $_.Name -notin @('.DS_Store', 'Thumbs.db', 'desktop.ini') }
    }
    else {
        Get-Item $path
    }
}

# Write entries with forward slashes; Compress-Archive on Windows PowerShell 5.1 uses backslashes.
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $entryName = $file.FullName.Substring($pluginDir.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Created $zipPath"
