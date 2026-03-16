<#
.SYNOPSIS
    Generates MDX documentation pages for nodes and edges.

.DESCRIPTION
    Reads node kinds and edge kinds from the BloodHound extension schema and
    creates one MDX file per kind under Documentation/OfficialDocs/opengraph/extensions/<ExtensionName>/reference.

    Generated files contain frontmatter and the content from Documentation/NodeDescriptions or Documentation/EdgeDescriptions.

    The following transformations are applied to the description content:
    - H1 headers are removed (the MDX frontmatter title is used instead).
    - Links to ../../NodeDescriptions/ are rewritten using the DocsBasePath parameter.
    - Links to other markdown files have their .md extension stripped.
    - GitHub-flavored callouts (NOTE, IMPORTANT, WARNING, TIP, CAUTION) are converted to Mintlify components.
    - Node documentation includes Inbound Edges and Outbound Edges sections (inserted between Overview and
      Properties), with tables generated from the Edge Schema sections of edge descriptions.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExtensionPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $NodeDescriptionsDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../Documentation/NodeDescriptions'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $EdgeDescriptionsDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../Documentation/EdgeDescriptions'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../Documentation/OfficialDocs/opengraph/extensions'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $IconBasePath = 'Icons',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $DocsBasePath = '..'
)

Set-StrictMode -Version Latest

[string] $nodeDescDirName = Split-Path -Leaf $NodeDescriptionsDir

function ConvertTo-YamlSingleQuoted {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

function Convert-ImagePaths {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ExtensionName
    )

    [regex] $imageRegex = [regex]'!\[([^\]]*)\]\(([^)]+)\)'

    return $imageRegex.Replace($Markdown, {
            param([System.Text.RegularExpressions.Match] $match)

            [string] $altText = $match.Groups[1].Value
            [string] $rawTarget = $match.Groups[2].Value.Trim()

            if ($rawTarget -match '^(?i:https?:|data:|/)') {
                return $match.Value
            }

            [string] $imagePath = $rawTarget
            [string] $titleSuffix = ''
            if ($rawTarget -match '^(\S+)\s+(("[^"]*")|(\''[^\'']*\''))$') {
                $imagePath = $matches[1]
                $titleSuffix = ' ' + $matches[2]
            }

            [string] $pathWithoutQuery = ($imagePath -split '[?#]', 2)[0]
            [string] $fileName = [System.IO.Path]::GetFileName($pathWithoutQuery)

            if ([string]::IsNullOrWhiteSpace($fileName)) {
                return $match.Value
            }

            return '![{0}]({1}/{2}{3})' -f $altText, $IconBasePath, $fileName.ToLower(), $titleSuffix
        })
}

function Convert-MarkdownLinks {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $NodeDescDirName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $SiblingBasePath
    )

    [regex] $linkRegex = [regex]'(?<!!)\[([^\]]+)\]\(([^)]+)\)'

    return $linkRegex.Replace($Markdown, {
            param([System.Text.RegularExpressions.Match] $match)

            [string] $linkText = $match.Groups[1].Value
            [string] $rawTarget = $match.Groups[2].Value.Trim()

            if ($rawTarget -match '^(?i:https?:|mailto:|data:|/)') {
                return $match.Value
            }

            [string] $linkPath = $rawTarget
            [string] $titleSuffix = ''
            if ($rawTarget -match '^(\S+)\s+(("[^"]*")|(\''[^\'']*\''))$') {
                $linkPath = $matches[1]
                $titleSuffix = ' ' + $matches[2]
            }

            [string] $pathWithoutQuery = ($linkPath -split '[?#]', 2)[0]
            if ($pathWithoutQuery -notmatch '\.md$') {
                return $match.Value
            }

            [string] $rewrittenPath = $linkPath -replace '\.md(?=($|[?#]))', ''
            $rewrittenPath = $rewrittenPath -replace ('^\.\.\/' + [regex]::Escape($NodeDescDirName) + '/'), ($DocsBasePath + '/nodes/')
            # Bare filename links (no directory separator) are sibling references
            if ($rewrittenPath -notmatch '[/\\]') {
                $rewrittenPath = $SiblingBasePath + '/' + $rewrittenPath
            }
            return '[{0}]({1}{2})' -f $linkText, $rewrittenPath.ToLower(), $titleSuffix
        })
}

function Convert-Callouts {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown
    )

    [regex] $calloutRegex = [regex]'(?m)^> \[!(NOTE|IMPORTANT|WARNING|TIP|CAUTION)\]\r?\n(?:^> .*(?:\r?\n|$))+'

    return $calloutRegex.Replace($Markdown, {
            param([System.Text.RegularExpressions.Match] $match)

            [string] $type = $match.Groups[1].Value
            [string] $tag = switch ($type) {
                'NOTE' { 'Info' }
                'IMPORTANT' { 'Note' }
                'WARNING' { 'Warning' }
                'TIP' { 'Tip' }
                'CAUTION' { 'Danger' }
            }

            [string[]] $contentLines = $match.Value -split '\r?\n' |
                Select-Object -Skip 1 |
                Where-Object { $_ -ne '' } |
                ForEach-Object { $_ -replace '^> ?', '' }

            [string] $body = ($contentLines -join "`n").TrimEnd()
            return "<$tag>`n$body`n</$tag>"
        })
}

function Get-EdgeSchemaMap {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $EdgeDescriptionsDir
    )

    [hashtable] $map = @{}
    [regex] $linkRegex = [regex]'\[([^\]]+)\]\(([^)]+)\)'

    foreach ($file in Get-ChildItem -Path $EdgeDescriptionsDir -Filter '*.md') {
        [string] $content = Get-Content -Path $file.FullName -Raw
        [string] $edgeName = $file.BaseName
        [psobject[]] $sources = @()
        [psobject[]] $destinations = @()
        [bool] $hasSourceLine = $content -match '(?m)^- Source:\s*(.+)$'

        if ($hasSourceLine) {
            [string] $rawSourceLine = $matches[1]
            $sources = @($linkRegex.Matches($rawSourceLine) | ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.Groups[1].Value
                        Url  = $_.Groups[2].Value
                    }
                })
            if ($sources.Count -eq 0) {
                Write-Warning "Edge '$edgeName' ($($file.Name)): '- Source:' line found but no valid markdown links could be parsed. Raw line: '$rawSourceLine'"
            }
        }
        else {
            Write-Warning "Edge '$edgeName' ($($file.Name)): missing '- Source:' line."
        }

        [bool] $hasDestLine = $content -match '(?m)^- Destination:\s*(.+)$'

        if ($hasDestLine) {
            [string] $rawDestLine = $matches[1]
            $destinations = @($linkRegex.Matches($rawDestLine) | ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.Groups[1].Value
                        Url  = $_.Groups[2].Value
                    }
                })
            if ($destinations.Count -eq 0) {
                Write-Warning "Edge '$edgeName' ($($file.Name)): '- Destination:' line found but no valid markdown links could be parsed. Raw line: '$rawDestLine'"
            }
        }
        else {
            Write-Warning "Edge '$edgeName' ($($file.Name)): missing '- Destination:' line."
        }

        $map[$edgeName] = [PSCustomObject]@{
            Sources      = $sources
            Destinations = $destinations
        }
    }

    return $map
}

function Format-EdgeTable {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Heading,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $PeerColumnName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Rows,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $EmptyMessage
    )

    [string] $result = "`n### $Heading`n`n"
    if ($Rows.Count -gt 0) {
        $result += "| Edge Type | $PeerColumnName | Traversable | Description |`n"
        $result += "| --------- | $('-' * $PeerColumnName.Length) | ----------- | ----------- |`n"
        $result += ($Rows -join "`n") + "`n"
    }
    else {
        $result += "$EmptyMessage`n"
    }

    return $result
}

function New-EdgeSectionMarkdown {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $NodeName,

        [Parameter(Mandatory = $true)]
        [hashtable] $EdgeSchemaMap,

        [Parameter(Mandatory = $true)]
        [hashtable] $RelationshipKindMap
    )

    [System.Collections.Generic.List[string]] $inboundRows = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $outboundRows = [System.Collections.Generic.List[string]]::new()

    foreach ($edgeName in ($EdgeSchemaMap.Keys | Sort-Object)) {
        [psobject] $schema = $EdgeSchemaMap[$edgeName]
        [string] $edgeLink = '[{0}]({1}/edges/{2})' -f $edgeName, $DocsBasePath, $edgeName.ToLower()

        try {
            [psobject] $relKind = $RelationshipKindMap[$edgeName]
            [string] $traversable = if ($relKind -and [bool] $relKind.is_traversable) { '✅' } else { '❌' }
            [string] $edgeDescription = if ($relKind) { [string] $relKind.description } else { '' }

            if ($NodeName -in $schema.Destinations.Name) {
                [string] $sourceLinks = ($schema.Sources | ForEach-Object {
                        '[{0}]({1})' -f $_.Name, $_.Url
                    }) -join ', '
                $inboundRows.Add("| $edgeLink | $sourceLinks | $traversable | $edgeDescription |")
            }

            if ($NodeName -in $schema.Sources.Name) {
                [string] $destLinks = ($schema.Destinations | ForEach-Object {
                        '[{0}]({1})' -f $_.Name, $_.Url
                    }) -join ', '
                $outboundRows.Add("| $edgeLink | $destLinks | $traversable | $edgeDescription |")
            }
        }
        catch {
            Write-Error "Error processing edge '$edgeName' for node '$NodeName'. Sources=$($schema.Sources | ConvertTo-Json -Compress -Depth 2), Destinations=$($schema.Destinations | ConvertTo-Json -Compress -Depth 2). ScriptStackTrace: $($_.ScriptStackTrace)"
            throw
        }
    }

    [string] $result = "## Edges`n`n"
    $result += "<Note>`n"
    $result += "The tables below list edges defined by the $extensionName extension only. Additional edges to or from this node may be created by other extensions.`n"
    $result += "</Note>`n"

    $result += Format-EdgeTable `
        -Heading 'Inbound Edges' `
        -PeerColumnName 'Source Node Types' `
        -Rows $inboundRows `
        -EmptyMessage "No inbound edges are defined by the $extensionName extension for this node."

    $result += Format-EdgeTable `
        -Heading 'Outbound Edges' `
        -PeerColumnName 'Destination Node Types' `
        -Rows $outboundRows `
        -EmptyMessage "No outbound edges are defined by the $extensionName extension for this node."

    return $result
}

function New-OfficialDoc {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Description,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $DescriptionFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ExtensionName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $NodeDescDirName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $IconPath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Traversable,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $EdgeSectionMarkdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $SiblingBasePath
    )

    if (-not (Test-Path -Path $DescriptionFilePath -PathType Leaf)) {
        Write-Warning "Skipping ${Name}: description file not found at $DescriptionFilePath"
        return
    }

    [string] $bodyMarkdown = Get-Content -Path $DescriptionFilePath -Raw
    $bodyMarkdown = $bodyMarkdown -replace '(?m)^# .+\r?\n\r?\n', ''

    if (-not [string]::IsNullOrWhiteSpace($EdgeSectionMarkdown)) {
        $bodyMarkdown = $bodyMarkdown -replace '(?m)^(## Properties)', ($EdgeSectionMarkdown + "`n" + '$1')
    }

    if (-not [string]::IsNullOrWhiteSpace($Traversable)) {
        $bodyMarkdown = $bodyMarkdown -replace '(?m)^- Destination:.*$', "`$0`n- Traversable: $Traversable"
    }

    $bodyMarkdown = Convert-ImagePaths -Markdown $bodyMarkdown -ExtensionName $ExtensionName
    $bodyMarkdown = Convert-MarkdownLinks -Markdown $bodyMarkdown -NodeDescDirName $NodeDescDirName -SiblingBasePath $SiblingBasePath
    $bodyMarkdown = Convert-Callouts -Markdown $bodyMarkdown

    [string] $iconLine = ''
    if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
        $iconLine = ('icon: {0}' -f (ConvertTo-YamlSingleQuoted -Value $IconPath)) + "`r`n"
    }

    [string] $mdx = @'
---
title: {0}
description: {1}
{2}---

<img noZoom src="/assets/enterprise-AND-community-edition-pill-tag.svg" alt="Applies to BloodHound Enterprise and CE"/>

{3}
'@ -f (
        (ConvertTo-YamlSingleQuoted -Value $Name),
        (ConvertTo-YamlSingleQuoted -Value $Description),
        $iconLine,
        $bodyMarkdown.TrimEnd()
    )

    $mdx = $mdx -replace "`r?`n", "`r`n"

    Set-Content -Path $OutputFilePath -Value $mdx -Encoding UTF8 -Verbose
}

# Parse extension schema
[psobject] $json = $null
try {
    $json = Get-Content -Path $ExtensionPath | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse extension file '$ExtensionPath': $($_.Exception.Message)"
    throw
}
[psobject[]] $nodeKinds = @($json.node_kinds | Sort-Object -Property name)
[psobject[]] $relationshipKinds = @($json.relationship_kinds | Sort-Object -Property name)
[string] $extensionName = [string] $json.schema.name

if ([string]::IsNullOrWhiteSpace($extensionName)) {
    throw "schema.name is missing in extension file: $ExtensionPath"
}

[string] $referenceRoot = Join-Path -Path (Join-Path -Path $OutputDir -ChildPath $extensionName.ToLower()) -ChildPath 'reference'
[string] $nodesOutputDir = Join-Path -Path $referenceRoot -ChildPath 'nodes'
[string] $edgesOutputDir = Join-Path -Path $referenceRoot -ChildPath 'edges'

foreach ($directory in @($nodesOutputDir, $edgesOutputDir)) {
    if (-not (Test-Path -Path $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
}

# Parse edge schemas for node edge sections
[hashtable] $edgeSchemaMap = Get-EdgeSchemaMap -EdgeDescriptionsDir $EdgeDescriptionsDir

# Build a lookup table of relationship kinds by name for edge metadata
[hashtable] $relationshipKindMap = @{}
foreach ($relKind in $relationshipKinds) {
    $relationshipKindMap[[string] $relKind.name] = $relKind
}

foreach ($nodeKind in $nodeKinds) {
    [string] $name = [string] $nodeKind.name
    [string] $description = [string] $nodeKind.description

    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Warning 'Skipping node kind with empty name.'
        continue
    }

    try {
        [string] $descriptionFilePath = Join-Path -Path $NodeDescriptionsDir -ChildPath "$name.md"
        [string] $outputFilePath = Join-Path -Path $nodesOutputDir -ChildPath "$($name.ToLower()).mdx"
        [string] $iconPath = "$IconBasePath/$($name.ToLower()).png"
        [string] $edgeSectionMarkdown = New-EdgeSectionMarkdown -NodeName $name -EdgeSchemaMap $edgeSchemaMap -RelationshipKindMap $relationshipKindMap

        New-OfficialDoc -Name $name -Description $description -DescriptionFilePath $descriptionFilePath -OutputFilePath $outputFilePath -ExtensionName $extensionName -NodeDescDirName $nodeDescDirName -IconPath $iconPath -EdgeSectionMarkdown $edgeSectionMarkdown -SiblingBasePath "$DocsBasePath/nodes"
    }
    catch {
        Write-Error "Error processing node kind '$name': $($_.Exception.Message)`nScriptStackTrace: $($_.ScriptStackTrace)"
        throw
    }
}

foreach ($relationshipKind in $relationshipKinds) {
    [string] $name = [string] $relationshipKind.name
    [string] $description = [string] $relationshipKind.description

    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Warning 'Skipping relationship kind with empty name.'
        continue
    }

    try {
        [string] $descriptionFilePath = Join-Path -Path $EdgeDescriptionsDir -ChildPath "$name.md"
        [string] $outputFilePath = Join-Path -Path $edgesOutputDir -ChildPath "$($name.ToLower()).mdx"
        [string] $traversable = if ([bool] $relationshipKind.is_traversable) { '✅' } else { '❌' }

        New-OfficialDoc -Name $name -Description $description -DescriptionFilePath $descriptionFilePath -OutputFilePath $outputFilePath -ExtensionName $extensionName -NodeDescDirName $nodeDescDirName -Traversable $traversable -SiblingBasePath "$DocsBasePath/edges"
    }
    catch {
        Write-Error "Error processing relationship kind '$name': $($_.Exception.Message)`nScriptStackTrace: $($_.ScriptStackTrace)"
        throw
    }
}
