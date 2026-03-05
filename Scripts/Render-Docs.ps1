<#
.SYNOPSIS
    Generates extension documentation in either Official or Local mode.

.DESCRIPTION
    Reads an og-docs.json configuration file and orchestrates the docs build by
    running each render script in the correct order.

    Official mode: produces MDX files with navigation JSON for the BloodHound
    official documentation site.

    Local mode: produces plain markdown files in the repo's Documentation directory.
#>

#Requires -Version 5.1

[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $false)]
    [string] $ConfigFile = (Join-Path -Path $PSScriptRoot -ChildPath '../../Documentation/og-docs.json'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Official', 'Local')]
    [string] $Mode = 'Local'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Read and validate config
# ---------------------------------------------------------------------------

if (-not (Test-Path -Path $ConfigFile -PathType Leaf)) {
    throw "Config file not found: $ConfigFile"
}

[psobject] $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
[string] $configDir = (Get-Item -Path $ConfigFile).Directory.FullName
[string] $repoRoot = (Get-Item -Path (Join-Path -Path $configDir -ChildPath '..')).FullName

if (-not $config.extensionPath) {
    throw "Config file must specify 'extensionPath'."
}

# Resolve paths relative to the repository root
function Resolve-ConfigPath([string] $relativePath) {
    if ([System.IO.Path]::IsPathRooted($relativePath)) { return $relativePath }
    return (Join-Path -Path $repoRoot -ChildPath $relativePath)
}

function Get-ConfigValue([string] $key, $default = '') {
    if ($config.PSObject.Properties[$key] -and $null -ne $config.$key) { return $config.$key }
    return $default
}

function Get-ConfigPath([string] $key, [string] $default = '') {
    [string] $val = Get-ConfigValue $key $default
    if ($val) { return Resolve-ConfigPath $val }
    return ''
}

[string] $ExtensionPath    = Resolve-ConfigPath $config.extensionPath
[string] $GitHubBaseUrl    = Get-ConfigValue 'gitHubBaseUrl'
[string] $TitlePrefix      = Get-ConfigValue 'titlePrefix'
[string] $QueriesDir       = Get-ConfigPath  'queriesDir'
[string] $ZoneRulesDir     = Get-ConfigPath  'zoneRulesDir'
[string] $NodeDescDir      = Get-ConfigPath  'nodeDescriptionsDir' 'Documentation/NodeDescriptions'
[string] $EdgeDescDir      = Get-ConfigPath  'edgeDescriptionsDir' 'Documentation/EdgeDescriptions'
[string] $ImagesDir        = Get-ConfigPath  'imagesDir' 'Documentation/Images'
[int]    $IconSize         = Get-ConfigValue 'iconSize' 32
[double] $IconScale        = Get-ConfigValue 'iconScale' 0.55

# Parse extension JSON to derive the extension name
[psobject] $extensionJson = Get-Content -Path $ExtensionPath | ConvertFrom-Json
[string] $extensionName = $extensionJson.schema.name
[string] $extensionSlug = $extensionName.ToLower()

if ([string]::IsNullOrEmpty($GitHubBaseUrl)) {
    $GitHubBaseUrl = 'https://github.com/SpecterOps/{0}' -f $extensionName
}
$GitHubBaseUrl = $GitHubBaseUrl.TrimEnd('/')

Write-Host "== Mode: $Mode | Extension: $extensionName ==" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Official mode
# ---------------------------------------------------------------------------
if ($Mode -eq 'Official') {
    [string] $officialDocsDir = Join-Path -Path $repoRoot -ChildPath 'Documentation/OfficialDocs'
    [string] $imagesOutputDirRelPath = '/images/extensions/{0}/reference' -f $extensionSlug
    [string] $imagesOutputDirFullPath = Join-Path -Path $officialDocsDir -ChildPath $imagesOutputDirRelPath
    [string] $docsRefBasePath = '/opengraph/extensions/{0}/reference' -f $extensionSlug
    [string] $opengraphRefDir = Join-Path -Path $officialDocsDir -ChildPath ('opengraph/extensions/{0}/reference' -f $extensionSlug)

    # Step 0: Clean the output directory
    Write-Host '== Step 0: Cleaning output directory ==' -ForegroundColor Cyan
    if (Test-Path -Path $officialDocsDir -PathType Container) {
        Get-ChildItem -Path $officialDocsDir | Remove-Item -Recurse -Force -Verbose
    }
    New-Item -Path $imagesOutputDirFullPath -ItemType Directory -Force | Out-Null
    New-Item -Path $opengraphRefDir -ItemType Directory -Force | Out-Null

    # Step 1: Render custom node icons into the official docs images directory
    Write-Host '== Step 1: Rendering custom node icons ==' -ForegroundColor Cyan
    [string] $packageCachePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'BloodHound-IconRender'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-CustomNodeIcons.ps1') -ExtensionPath $ExtensionPath -OutputDir $imagesOutputDirFullPath -ImageSize $IconSize -IconScale $IconScale -PackageCachePath $packageCachePath

    # Step 2: Copy static images to the official docs images directory
    # Image filenames are lowercased to match the references generated by the render scripts.
    Write-Host '== Step 2: Copying static images ==' -ForegroundColor Cyan
    foreach ($file in Get-ChildItem -Path $ImagesDir -File) {
        [string] $lowerName = $file.Name.ToLower()
        if ($file.Name -cne $lowerName) {
            Write-Warning "Renaming image to lowercase: $($file.Name) -> $lowerName"
        }
        Copy-Item -Path $file.FullName -Destination (Join-Path -Path $imagesOutputDirFullPath -ChildPath $lowerName) -Force -Verbose
    }

    # Step 3: Render custom queries MDX
    Write-Host '== Step 3: Rendering custom queries ==' -ForegroundColor Cyan
    [string] $queriesOutputPath = Join-Path -Path $opengraphRefDir -ChildPath 'queries.mdx'
    [string] $queriesGitHubPath = '{0}/tree/main/Src/Queries' -f $GitHubBaseUrl
    [hashtable] $customQueriesParams = @{
        ExtensionName   = $extensionName
        OutputPath      = $queriesOutputPath
        QueriesLinkPath = $queriesGitHubPath
        TitlePrefix     = $TitlePrefix
        OfficialDocs    = $true
    }
    if ($QueriesDir) { $customQueriesParams['InputDir'] = $QueriesDir }
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-CustomQueries.ps1') @customQueriesParams

    # Step 4: Render privilege zone rules MDX
    Write-Host '== Step 4: Rendering privilege zone rules ==' -ForegroundColor Cyan
    [string] $privilegeZonePath = Join-Path -Path $opengraphRefDir -ChildPath 'privilege-zone-rules.mdx'
    [string] $rulesGitHubPath = '{0}/tree/main/Src/PrivilegeZoneRules' -f $GitHubBaseUrl
    [hashtable] $privilegeZoneParams = @{
        ExtensionName = $extensionName
        OutputPath    = $privilegeZonePath
        RulesLinkPath = $rulesGitHubPath
        TitlePrefix   = $TitlePrefix
        OfficialDocs  = $true
    }
    if ($ZoneRulesDir) { $privilegeZoneParams['InputDir'] = $ZoneRulesDir }
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-PrivilegeZoneRules.ps1') @privilegeZoneParams

    # Step 5: Render node and edge documentation MDX files
    Write-Host '== Step 5: Rendering node and edge docs ==' -ForegroundColor Cyan
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-NodeAndEdgeDocs.ps1') -ExtensionPath $ExtensionPath -NodeDescriptionsDir $NodeDescDir -EdgeDescriptionsDir $EdgeDescDir -IconBasePath $imagesOutputDirRelPath -DocsBasePath $docsRefBasePath

    # Step 6: Render schema MDX
    Write-Host '== Step 6: Rendering schema ==' -ForegroundColor Cyan
    [string] $schemaOutputPath = Join-Path -Path $opengraphRefDir -ChildPath 'schema.mdx'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-Schema.ps1') -ExtensionPath $ExtensionPath -OutputPath $schemaOutputPath -NodeLinkBasePath "$docsRefBasePath/nodes" -EdgeLinkBasePath "$docsRefBasePath/edges" -IconBasePath $imagesOutputDirRelPath -GitHubBaseUrl $GitHubBaseUrl -OfficialDocs

    # Step 7: Render official docs navigation JSON
    Write-Host '== Step 7: Rendering docs.json ==' -ForegroundColor Cyan
    [string] $extensionOfficialDocsDir = Join-Path -Path $officialDocsDir -ChildPath ('opengraph/extensions/{0}' -f $extensionSlug)
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-OfficialDocsJson.ps1') -ExtensionName $extensionName -DocsDir $extensionOfficialDocsDir
}

# ---------------------------------------------------------------------------
# Local mode
# ---------------------------------------------------------------------------
if ($Mode -eq 'Local') {
    [string] $docsDir = Join-Path -Path $repoRoot -ChildPath 'Documentation'

    # Step 1: Render custom node icons
    Write-Host '== Step 1: Rendering custom node icons ==' -ForegroundColor Cyan
    [string] $iconsOutputDir = Join-Path -Path $docsDir -ChildPath 'Icons'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-CustomNodeIcons.ps1') -ExtensionPath $ExtensionPath -OutputDir $iconsOutputDir -ImageSize $IconSize -IconScale $IconScale

    # Step 2: Render custom queries markdown
    Write-Host '== Step 2: Rendering custom queries ==' -ForegroundColor Cyan
    [string] $queriesLinkPath = '../' + (Get-ConfigValue 'queriesDir' 'Src/Queries')
    [hashtable] $customQueriesParams = @{
        ExtensionName   = $extensionName
        OutputPath      = (Join-Path -Path $docsDir -ChildPath 'Queries.md')
        QueriesLinkPath = $queriesLinkPath
        TitlePrefix     = $TitlePrefix
    }
    if ($QueriesDir) { $customQueriesParams['InputDir'] = $QueriesDir }
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-CustomQueries.ps1') @customQueriesParams

    # Step 3: Render privilege zone rules markdown
    Write-Host '== Step 3: Rendering privilege zone rules ==' -ForegroundColor Cyan
    [string] $zoneRulesLinkPath = '../' + (Get-ConfigValue 'zoneRulesDir' 'Src/PrivilegeZoneRules')
    [hashtable] $privilegeZoneParams = @{
        ExtensionName = $extensionName
        OutputPath    = (Join-Path -Path $docsDir -ChildPath 'PrivilegeZoneRules.md')
        RulesLinkPath = $zoneRulesLinkPath
        TitlePrefix   = $TitlePrefix
    }
    if ($ZoneRulesDir) { $privilegeZoneParams['InputDir'] = $ZoneRulesDir }
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-PrivilegeZoneRules.ps1') @privilegeZoneParams

    # Step 4: Render schema markdown
    Write-Host '== Step 4: Rendering schema ==' -ForegroundColor Cyan
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Render-Schema.ps1') -ExtensionPath $ExtensionPath -OutputPath (Join-Path -Path $docsDir -ChildPath 'Schema.md') -IconBasePath 'Icons' -GitHubBaseUrl $GitHubBaseUrl
}

Write-Host '== Done ==' -ForegroundColor Green
