<#
.SYNOPSIS
    Generates docs.json navigation metadata for an extension's official docs.

.DESCRIPTION
    Scans MDX pages under docs/official-docs/opengraph/extensions/<ExtensionName>
    and writes a docs.json file with grouped navigation entries.

    The images/ directory and docs.json itself are ignored.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExtensionShortName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $DocsDir
)

Set-StrictMode -Version Latest

[string] $extensionSlug = $ExtensionShortName.ToLower()

if (-not (Test-Path -Path $DocsDir -PathType Container)) {
    throw "Extension directory not found: $DocsDir"
}

[string] $outputPath = (Join-Path -Path $DocsDir -ChildPath 'docs.json')
[string] $nodesDir = Join-Path -Path $DocsDir -ChildPath 'nodes'
[string] $edgesDir = Join-Path -Path $DocsDir -ChildPath 'edges'

# MDX files directly in the extension root (e.g. schema.mdx)
[string[]] $rootPages = @(Get-ChildItem -Path $DocsDir -Filter '*.mdx' -File |
        Sort-Object -Property BaseName |
        ForEach-Object { "opengraph/extensions/$extensionSlug/$($_.BaseName)" })

# MDX files in nodes/
[string[]] $nodePages = @()
if (Test-Path -Path $nodesDir -PathType Container) {
    $nodePages = @(Get-ChildItem -Path $nodesDir -Filter '*.mdx' -File |
            Sort-Object -Property BaseName |
            ForEach-Object { "opengraph/extensions/$extensionSlug/nodes/$($_.BaseName)" })
}

# MDX files in edges/
[string[]] $edgePages = @()
if (Test-Path -Path $edgesDir -PathType Container) {
    $edgePages = @(Get-ChildItem -Path $edgesDir -Filter '*.mdx' -File |
            Sort-Object -Property BaseName |
            ForEach-Object { "opengraph/extensions/$extensionSlug/edges/$($_.BaseName)" })
}

$docs = [ordered]@{
    group = $ExtensionShortName
    pages = @(
        $rootPages
        [ordered]@{
            group = 'Nodes'
            pages = $nodePages
        }
        [ordered]@{
            group = 'Edges'
            pages = $edgePages
        }
    )
}

[string] $json = $docs | ConvertTo-Json -Depth 8
$json = $json -replace "`r?`n", "`r`n"

Set-Content -Path $outputPath -Value $json -Encoding UTF8
Write-Host "Wrote $outputPath" -ForegroundColor DarkGray
