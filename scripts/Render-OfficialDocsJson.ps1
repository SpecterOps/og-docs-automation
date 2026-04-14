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
    [string] $ExtensionName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $DocsDir
)

Set-StrictMode -Version Latest

function Get-ExtensionSlug {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ExtensionName
    )

    [string] $slug = $ExtensionName.ToLower()
    if ($slug -match '^so[a-z0-9]') {
        return $slug.Substring(2)
    }

    return $slug
}

[string] $extensionSlug = Get-ExtensionSlug -ExtensionName $ExtensionName

if (-not (Test-Path -Path $DocsDir -PathType Container)) {
    throw "Extension directory not found: $DocsDir"
}

[string] $outputPath = (Join-Path -Path $DocsDir -ChildPath 'docs.json')
[string] $referenceDir = Join-Path -Path $DocsDir -ChildPath 'reference'
[string] $nodesDir = Join-Path -Path $referenceDir -ChildPath 'nodes'
[string] $edgesDir = Join-Path -Path $referenceDir -ChildPath 'edges'

# MDX files directly in the extension root (e.g. schema.mdx)
[string[]] $rootPages = @(Get-ChildItem -Path $DocsDir -Filter '*.mdx' -File |
        Sort-Object -Property BaseName |
        ForEach-Object { "opengraph/extensions/$extensionSlug/$($_.BaseName)" })

# MDX files directly in reference/ but not in nodes/ or edges/ (e.g. queries.mdx, privilege-zone-rules.mdx)
[string[]] $referencePages = @()
if (Test-Path -Path $referenceDir -PathType Container) {
    $referencePages = @(Get-ChildItem -Path $referenceDir -Filter '*.mdx' -File |
            Sort-Object -Property BaseName |
            ForEach-Object { "opengraph/extensions/$extensionSlug/reference/$($_.BaseName)" })
}

# MDX files in reference/nodes/
[string[]] $nodePages = @()
if (Test-Path -Path $nodesDir -PathType Container) {
    $nodePages = @(Get-ChildItem -Path $nodesDir -Filter '*.mdx' -File |
            Sort-Object -Property BaseName |
            ForEach-Object { "opengraph/extensions/$extensionSlug/reference/nodes/$($_.BaseName)" })
}

# MDX files in reference/edges/
[string[]] $edgePages = @()
if (Test-Path -Path $edgesDir -PathType Container) {
    $edgePages = @(Get-ChildItem -Path $edgesDir -Filter '*.mdx' -File |
            Sort-Object -Property BaseName |
            ForEach-Object { "opengraph/extensions/$extensionSlug/reference/edges/$($_.BaseName)" })
}

$docs = [ordered]@{
    group = $ExtensionName
    pages = @(
        $rootPages +
        @(
            [ordered]@{
                group = 'Reference'
                pages = @(
                    $referencePages +
                    @(
                        [ordered]@{
                            group = 'Nodes'
                            pages = $nodePages
                        },
                        [ordered]@{
                            group = 'Edges'
                            pages = $edgePages
                        }
                    )
                )
            }
        )
    )
}

[string] $json = $docs | ConvertTo-Json -Depth 8
$json = $json -replace "`r?`n", "`r`n"

Set-Content -Path $outputPath -Value $json -Encoding UTF8
Write-Host "Wrote $outputPath" -ForegroundColor DarkGray
