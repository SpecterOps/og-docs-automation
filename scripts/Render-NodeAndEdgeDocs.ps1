<#
.SYNOPSIS
    Generates MDX documentation pages for nodes and edges.

.DESCRIPTION
    Reads node kinds and edge kinds from the BloodHound extension schema and
    creates one MDX file per kind under docs/official-docs/opengraph/extensions/<ExtensionName>/reference.

    Generated files contain frontmatter and the content from descriptions/nodes or descriptions/edges.

    The following transformations are applied to the description content:
    - H1 headers are removed (the MDX frontmatter title is used instead).
    - Refs to known node and edge kinds are converted into links using the DocsBasePath parameter.
    - Links to other markdown files have their .md extension stripped.
    - GitHub-flavored callouts (NOTE, IMPORTANT, WARNING, TIP, CAUTION) are converted to Mintlify components.
    - "@" characters inside mermaid code blocks are escaped as "\@" (if not already escaped) to prevent MDX parsing issues.
    - Node documentation includes an Edges section sourced from docs/graph/nodes/<NodeName>.md, including the mermaid
      diagram plus inbound and outbound tables, and a Properties section sourced from the same file.
    - Edge documentation includes an Edge Schema section before General Information, including traversability, the
      source/destination node table, and the mermaid diagram sourced from docs/graph/edges/<EdgeName>.md.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExtensionSchemaPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExtensionShortName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $NodeDescriptionsDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../../descriptions/nodes'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $EdgeDescriptionsDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../../descriptions/edges'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $GraphNodeDocsDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../graph/nodes'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $GraphEdgeDocsDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../graph/edges'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../official-docs/opengraph/extensions'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $IconBasePath = 'icons',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $DocsBasePath = '..',

    [Parameter(Mandatory = $false)]
    [bool] $OpenHoundStructure = $true
)

Set-StrictMode -Version Latest

[hashtable] $script:NodeKindLookup = @{}
[hashtable] $script:EdgeKindLookup = @{}

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

function Test-IsKnownKind {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $KindName
    )

    return ($script:NodeKindLookup.ContainsKey($KindName) -or $script:EdgeKindLookup.ContainsKey($KindName))
}

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
        [string] $Markdown
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
            if ($rawTarget -match '^(\S+)\s+(("[^"]*")|(''[^'']*''))$') {
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

function Get-KindLinkPath {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $KindName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $CurrentKindName
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentKindName) -and $KindName -eq $CurrentKindName) {
        return ''
    }

    if ($script:NodeKindLookup.ContainsKey($KindName)) {
        return ('{0}/nodes/{1}' -f $DocsBasePath, $KindName.ToLower())
    }

    if ($script:EdgeKindLookup.ContainsKey($KindName)) {
        return ('{0}/edges/{1}' -f $DocsBasePath, $KindName.ToLower())
    }

    return ''
}

function Protect-MarkdownPatterns {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ref] $Store,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Patterns
    )

    foreach ($pattern in $Patterns) {
        $Markdown = [regex]::Replace($Markdown, $pattern, {
                param([System.Text.RegularExpressions.Match] $match)

                [string] $token = "%%MDXPROTECT$($Store.Value.Count)%%"
                $Store.Value[$token] = $match.Value
                return $token
            })
    }

    return $Markdown
}

function Convert-KindReferences {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $CurrentKindName
    )

    if (($script:NodeKindLookup.Count + $script:EdgeKindLookup.Count) -eq 0) {
        return $Markdown
    }

    [string[]] $allKinds = @($script:NodeKindLookup.Keys + $script:EdgeKindLookup.Keys | Sort-Object Length -Descending -Unique)
    [string] $kindPattern = ($allKinds | ForEach-Object { [regex]::Escape($_) }) -join '|'

    $Markdown = [regex]::Replace($Markdown, '(?<!`)`(?<code>[^`\r\n]+)`(?!`)', {
            param([System.Text.RegularExpressions.Match] $match)

            [string] $kindName = $match.Groups['code'].Value
            if (-not (Test-IsKnownKind -KindName $kindName)) {
                return $match.Value
            }

            [string] $path = Get-KindLinkPath -KindName $kindName -CurrentKindName $CurrentKindName
            if ([string]::IsNullOrWhiteSpace($path)) {
                return $match.Value
            }

            return '[{0}]({1})' -f $kindName, $path.ToLower()
        })

    [hashtable] $protected = @{}
    $Markdown = Protect-MarkdownPatterns -Markdown $Markdown -Store ([ref] $protected) -Patterns @(
        '(?s)```.*?```',
        '!\[[^\]]*\]\([^)]+\)',
        '(?<!!)\[[^\]]+\]\([^)]+\)',
        '(?<!`)`[^`]+`(?!`)'
    )

    [string] $bareKindPattern = '(?<![A-Za-z0-9_/\[])' + '(?<kind>' + $kindPattern + ')' + '(?![A-Za-z0-9_])'
    $Markdown = [regex]::Replace($Markdown, $bareKindPattern, {
            param([System.Text.RegularExpressions.Match] $match)

            [string] $kindName = $match.Groups['kind'].Value
            [string] $path = Get-KindLinkPath -KindName $kindName -CurrentKindName $CurrentKindName
            if ([string]::IsNullOrWhiteSpace($path)) {
                return $match.Value
            }

            return '[{0}]({1})' -f $kindName, $path.ToLower()
        })

    foreach ($token in $protected.Keys) {
        $Markdown = $Markdown.Replace($token, [string] $protected[$token])
    }

    return $Markdown
}

function Convert-MarkdownLinks {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $SiblingBasePath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $CurrentKindName
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
            if ($rawTarget -match '^(\S+)\s+(("[^"]*")|(''[^'']*''))$') {
                $linkPath = $matches[1]
                $titleSuffix = ' ' + $matches[2]
            }

            [string] $pathWithoutQuery = ($linkPath -split '[?#]', 2)[0]
            if ($pathWithoutQuery -notmatch '\.md$') {
                return $match.Value
            }

            [string] $baseName = [System.IO.Path]::GetFileNameWithoutExtension($pathWithoutQuery)
            [string] $rewrittenPath = Get-KindLinkPath -KindName $baseName -CurrentKindName $CurrentKindName

            if ([string]::IsNullOrWhiteSpace($rewrittenPath)) {
                if (-not [string]::IsNullOrWhiteSpace($CurrentKindName) -and $baseName -eq $CurrentKindName) {
                    return $linkText
                }

                $rewrittenPath = $linkPath -replace '\.md(?=($|[?#]))', ''
                if ($rewrittenPath -notmatch '[/\\]') {
                    $rewrittenPath = $SiblingBasePath + '/' + $rewrittenPath
                }
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

function Remove-H1Headers {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown
    )

    return ($Markdown -replace '(?m)^# .+\r?\n\r?\n', '').Trim()
}

function Get-MarkdownSection {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Heading
    )

    [string] $pattern = '(?ms)^## ' + [regex]::Escape($Heading) + '\s*\r?\n(?<body>.*?)(?=^## |\z)'
    [System.Text.RegularExpressions.Match] $match = [regex]::Match($Markdown, $pattern)

    if (-not $match.Success) {
        return ''
    }

    return $match.Groups['body'].Value.Trim()
}

function Get-MarkdownSubsection {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Heading
    )

    [string] $pattern = '(?ms)^### ' + [regex]::Escape($Heading) + '\s*\r?\n(?<body>.*?)(?=^### |\z)'
    [System.Text.RegularExpressions.Match] $match = [regex]::Match($Markdown, $pattern)

    if (-not $match.Success) {
        return ''
    }

    return $match.Groups['body'].Value.Trim()
}

function Get-FirstMarkdownTable {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown
    )

    [System.Text.RegularExpressions.Match] $match = [regex]::Match($Markdown, '(?ms)^\|.*\r?\n^\|[-:| ]+\|.*(?:\r?\n^\|.*)+')
    if (-not $match.Success) {
        return ''
    }

    return $match.Value.Trim()
}

function Get-FirstMermaidBlock {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown
    )

    [System.Text.RegularExpressions.Match] $match = [regex]::Match($Markdown, '(?s)```mermaid\r?\n.*?```')
    if (-not $match.Success) {
        return ''
    }

    return $match.Value.Trim()
}

function Join-MarkdownSections {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Sections
    )

    [string[]] $nonEmptySections = @(
        $Sections |
        ForEach-Object {
            if ($null -eq $_) {
                return
            }

            [string] $_
        } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    return (($nonEmptySections -join "`n`n").Trim())
}

function Get-NodeGraphSections {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $NodeName
    )

    [string] $filePath = Join-Path -Path $GraphNodeDocsDir -ChildPath "$NodeName.md"
    if (-not (Test-Path -Path $filePath -PathType Leaf)) {
        Write-Warning "Node graph doc not found for '$NodeName': $filePath"
        return [PSCustomObject]@{
            Edges      = ''
            Properties = ''
        }
    }

    [string] $content = Get-Content -Path $filePath -Raw
    [string] $edgeSection = Get-MarkdownSection -Markdown $content -Heading 'Edges'
    [string] $propertiesSection = Get-MarkdownSection -Markdown $content -Heading 'Node properties'

    [string] $mermaid = Get-FirstMermaidBlock -Markdown $edgeSection
    [string] $incoming = Get-MarkdownSubsection -Markdown $edgeSection -Heading 'Incoming'
    [string] $outgoing = Get-MarkdownSubsection -Markdown $edgeSection -Heading 'Outgoing'

    [string] $incomingMarkdown = ''
    if (-not [string]::IsNullOrWhiteSpace($incoming)) {
        $incomingMarkdown = "### Inbound Edges`n`n$incoming"
    }

    [string] $outgoingMarkdown = ''
    if (-not [string]::IsNullOrWhiteSpace($outgoing)) {
        $outgoingMarkdown = "### Outbound Edges`n`n$outgoing"
    }

    [string] $edgeNoteMarkdown = "<Note>`nThe tables below list edges defined by the $ExtensionShortName extension only. Additional edges to or from this node may be created by other extensions.`n</Note>"

    [string] $edgesMarkdown = Join-MarkdownSections -Sections @(
        '## Edges',
        $edgeNoteMarkdown,
        $mermaid,
        $incomingMarkdown,
        $outgoingMarkdown
    )

    [string] $propertiesMarkdown = ''
    if (-not [string]::IsNullOrWhiteSpace($propertiesSection)) {
        $propertiesMarkdown = "## Properties`n`n$propertiesSection"
    }

    return [PSCustomObject]@{
        Edges      = $edgesMarkdown
        Properties = $propertiesMarkdown
    }
}

function Get-EdgeSchemaSection {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $EdgeName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Traversable
    )

    [string] $filePath = Join-Path -Path $GraphEdgeDocsDir -ChildPath "$EdgeName.md"
    if (-not (Test-Path -Path $filePath -PathType Leaf)) {
        Write-Warning "Edge graph doc not found for '$EdgeName': $filePath"
        return "## Edge Schema`n`nTraversable: $Traversable"
    }

    [string] $content = Get-Content -Path $filePath -Raw
    [string] $sourceDestSection = Get-MarkdownSection -Markdown $content -Heading 'Source and destination nodes'
    [string] $table = Get-FirstMarkdownTable -Markdown $sourceDestSection
    [string] $mermaid = Get-FirstMermaidBlock -Markdown $content

    return Join-MarkdownSections -Sections @(
        '## Edge Schema',
        "Traversable: $Traversable",
        $table,
        $mermaid
    )
}

function Get-BasicEdgeSchemaSection {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Traversable
    )

    return "## Edge Schema`n`n- Traversable: $Traversable"
}

function Convert-TraversableToEmoji {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Traversable
    )

    if ($Traversable -eq 'true') {
        return '✅'
    }

    if ($Traversable -eq 'false') {
        return '❌'
    }

    return $Traversable
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

    foreach ($file in Get-ChildItem -Path $EdgeDescriptionsDir -Filter '*.md' -File) {
        [string] $content = Get-Content -Path $file.FullName -Raw
        [string] $edgeName = $file.BaseName
        [psobject[]] $sources = @()
        [psobject[]] $destinations = @()

        if ($content -match '(?m)^- Source:\s*(.+)$') {
            [string] $rawSourceLine = $matches[1]
            $sources = @($linkRegex.Matches($rawSourceLine) | ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.Groups[1].Value
                        Url  = $_.Groups[2].Value
                    }
                })
        }
        else {
            Write-Warning "Edge '$edgeName' ($($file.Name)): missing '- Source:' line."
        }

        if ($content -match '(?m)^- Destination:\s*(.+)$') {
            [string] $rawDestinationLine = $matches[1]
            $destinations = @($linkRegex.Matches($rawDestinationLine) | ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.Groups[1].Value
                        Url  = $_.Groups[2].Value
                    }
                })
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

    [string] $result = "### $Heading`n`n"
    if ($Rows.Count -gt 0) {
        $result += "| Edge Type | $PeerColumnName | Traversable |`n"
        $result += "| --------- | $('-' * $PeerColumnName.Length) | ----------- |`n"
        $result += ($Rows -join "`n")
    }
    else {
        $result += $EmptyMessage
    }

    return $result
}

function New-NodeEdgeSectionMarkdown {
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
        [psobject] $relKind = $RelationshipKindMap[$edgeName]
        [string] $traversable = if ($relKind -and [bool] $relKind.is_traversable) { 'true' } else { 'false' }
        [string] $traversableDisplay = Convert-TraversableToEmoji -Traversable $traversable

        if ($NodeName -in $schema.Destinations.Name) {
            [string] $sourceLinks = ($schema.Sources | ForEach-Object {
                    [string] $nodeLinkPath = Get-KindLinkPath -KindName $_.Name
                    if ([string]::IsNullOrWhiteSpace($nodeLinkPath)) {
                        $_.Name
                    }
                    else {
                        '[{0}]({1})' -f $_.Name, $nodeLinkPath.ToLower()
                    }
                }) -join ', '
            $inboundRows.Add("| $edgeLink | $sourceLinks | $traversableDisplay |")
        }

        if ($NodeName -in $schema.Sources.Name) {
            [string] $destinationLinks = ($schema.Destinations | ForEach-Object {
                    [string] $nodeLinkPath = Get-KindLinkPath -KindName $_.Name
                    if ([string]::IsNullOrWhiteSpace($nodeLinkPath)) {
                        $_.Name
                    }
                    else {
                        '[{0}]({1})' -f $_.Name, $nodeLinkPath.ToLower()
                    }
                }) -join ', '
            $outboundRows.Add("| $edgeLink | $destinationLinks | $traversableDisplay |")
        }
    }

    return Join-MarkdownSections -Sections @(
        '## Edges',
        "<Note>`nThe tables below list edges defined by the $ExtensionShortName extension only. Additional edges to or from this node may be created by other extensions.`n</Note>",
        (Format-EdgeTable -Heading 'Inbound Edges' -PeerColumnName 'Source Node Types' -Rows $inboundRows -EmptyMessage "No inbound edges are defined by the $ExtensionShortName extension for this node."),
        (Format-EdgeTable -Heading 'Outbound Edges' -PeerColumnName 'Destination Node Types' -Rows $outboundRows -EmptyMessage "No outbound edges are defined by the $ExtensionShortName extension for this node.")
    )
}

function Add-NodeEdgeSections {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $EdgeSectionMarkdown
    )

    if ([string]::IsNullOrWhiteSpace($EdgeSectionMarkdown)) {
        return $Markdown
    }

    if ($Markdown -match '(?m)^## Properties\s*$') {
        return [regex]::Replace(
            $Markdown,
            '(?m)^## Properties\s*$',
            ($EdgeSectionMarkdown + "`r`n`r`n## Properties"),
            1
        )
    }

    return Join-MarkdownSections -Sections @(
        $Markdown,
        $EdgeSectionMarkdown
    )
}

function Add-TraversableToEdgeSchema {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Traversable
    )

    [string] $edgeSchemaHeading = '## Edge Schema'
    [string] $traversableEmoji = Convert-TraversableToEmoji -Traversable $Traversable
    [string] $traversableLine = "- Traversable: $traversableEmoji"

    if ($Markdown -match '(?m)^-?\s*Traversable:\s+(\S+)\s*$') {
        return $Markdown
    }

    if ($Markdown -match '(?m)^## Edge Schema\s*$') {
        if ($Markdown -match '(?ms)^## Edge Schema\s*\r?\n(?<schemaBody>.*?)(?:\r?\n## |\z)') {
            [string] $schemaBody = $matches['schemaBody']
            if ($schemaBody -match '(?m)^- Destination:\s+.+$') {
                return [regex]::Replace(
                    $Markdown,
                    '(?m)^(- Destination:\s+.+)$',
                    ('$1' + "`r`n" + $traversableLine),
                    1
                )
            }

            if ($schemaBody -match '(?m)^- Source:\s+.+$') {
                return [regex]::Replace(
                    $Markdown,
                    '(?m)^(- Source:\s+.+)$',
                    ('$1' + "`r`n" + $traversableLine),
                    1
                )
            }
        }

        return [regex]::Replace(
            $Markdown,
            '(?ms)^## Edge Schema\s*\r?\n(?:\r?\n)*',
            "$edgeSchemaHeading`r`n`r`n$traversableLine`r`n",
            1
        )
    }

    return Join-MarkdownSections -Sections @(
        (Get-BasicEdgeSchemaSection -Traversable $Traversable),
        $Markdown
    )
}

function Convert-BodyMarkdown {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Markdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $SiblingBasePath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $CurrentKindName
    )

    $Markdown = Remove-H1Headers -Markdown $Markdown
    $Markdown = Convert-ImagePaths -Markdown $Markdown
    $Markdown = Convert-KindReferences -Markdown $Markdown -CurrentKindName $CurrentKindName
    $Markdown = Convert-MarkdownLinks -Markdown $Markdown -SiblingBasePath $SiblingBasePath -CurrentKindName $CurrentKindName
    $Markdown = Convert-Callouts -Markdown $Markdown
    $Markdown = [regex]::Replace($Markdown, '(?s)```mermaid\r?\n.*?```', {
            param([System.Text.RegularExpressions.Match] $match)
            return $match.Value -replace '(?<!\\)@', '\@'
        })
    $Markdown = $Markdown.Replace('https://bloodhound.specterops.io/', '/')

    return $Markdown.Trim()
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
        [AllowEmptyString()]
        [string] $BodyMarkdown,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputFilePath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $IconPath
    )

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
        $BodyMarkdown.TrimEnd()
    )

    $mdx = $mdx -replace "`r?`n", "`r`n"

    Set-Content -Path $OutputFilePath -Value $mdx -Encoding UTF8
    Write-Host "Wrote $OutputFilePath" -ForegroundColor DarkGray
}

try {
    [psobject] $json = Get-Content -Path $ExtensionSchemaPath | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse extension file '$ExtensionSchemaPath': $($_.Exception.Message)"
    throw
}

[psobject[]] $nodeKinds = @($json.node_kinds | Sort-Object -Property name)
[psobject[]] $relationshipKinds = @($json.relationship_kinds | Sort-Object -Property name)
[string] $extensionName = [string] $json.schema.name

if ([string]::IsNullOrWhiteSpace($extensionName)) {
    throw "schema.name is missing in extension file: $ExtensionSchemaPath"
}

foreach ($nodeKind in $nodeKinds) {
    if (-not [string]::IsNullOrWhiteSpace([string] $nodeKind.name)) {
        $script:NodeKindLookup[[string] $nodeKind.name] = $true
    }
}

foreach ($relationshipKind in $relationshipKinds) {
    if (-not [string]::IsNullOrWhiteSpace([string] $relationshipKind.name)) {
        $script:EdgeKindLookup[[string] $relationshipKind.name] = $true
    }
}

[string] $extensionSlug = Get-ExtensionSlug -ExtensionName $extensionName
[string] $referenceRoot = Join-Path -Path (Join-Path -Path $OutputDir -ChildPath $extensionSlug) -ChildPath 'reference'
[string] $nodesOutputDir = Join-Path -Path $referenceRoot -ChildPath 'nodes'
[string] $edgesOutputDir = Join-Path -Path $referenceRoot -ChildPath 'edges'
[hashtable] $relationshipKindMap = @{}

foreach ($relationshipKind in $relationshipKinds) {
    if (-not [string]::IsNullOrWhiteSpace([string] $relationshipKind.name)) {
        $relationshipKindMap[[string] $relationshipKind.name] = $relationshipKind
    }
}

[hashtable] $edgeSchemaMap = @{}
if (-not $OpenHoundStructure) {
    $edgeSchemaMap = Get-EdgeSchemaMap -EdgeDescriptionsDir $EdgeDescriptionsDir
}

foreach ($directory in @($nodesOutputDir, $edgesOutputDir)) {
    if (-not (Test-Path -Path $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
}

foreach ($nodeKind in $nodeKinds) {
    [string] $name = [string] $nodeKind.name
    [string] $description = [string] $nodeKind.description

    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Warning 'Skipping node kind with empty name.'
        continue
    }

    [string] $descriptionFilePath = Join-Path -Path $NodeDescriptionsDir -ChildPath "$name.md"
    if (-not (Test-Path -Path $descriptionFilePath -PathType Leaf)) {
        Write-Warning "Skipping ${name}: description file not found at $descriptionFilePath"
        continue
    }

    try {
        [string] $bodyMarkdown = Get-Content -Path $descriptionFilePath -Raw
        if ($OpenHoundStructure) {
            [psobject] $graphSections = Get-NodeGraphSections -NodeName $name
            $bodyMarkdown = Join-MarkdownSections -Sections @(
                $bodyMarkdown,
                $graphSections.Edges,
                $graphSections.Properties
            )
        }
        else {
            $bodyMarkdown = Add-NodeEdgeSections -Markdown $bodyMarkdown -EdgeSectionMarkdown (New-NodeEdgeSectionMarkdown -NodeName $name -EdgeSchemaMap $edgeSchemaMap -RelationshipKindMap $relationshipKindMap)
        }
        $bodyMarkdown = Convert-BodyMarkdown -Markdown $bodyMarkdown -SiblingBasePath "$DocsBasePath/nodes" -CurrentKindName $name

        [string] $outputFilePath = Join-Path -Path $nodesOutputDir -ChildPath "$($name.ToLower()).mdx"
        [string] $iconPath = "$IconBasePath/$($name.ToLower()).png"

        New-OfficialDoc -Name $name -Description $description -BodyMarkdown $bodyMarkdown -OutputFilePath $outputFilePath -IconPath $iconPath
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

    [string] $descriptionFilePath = Join-Path -Path $EdgeDescriptionsDir -ChildPath "$name.md"
    if (-not (Test-Path -Path $descriptionFilePath -PathType Leaf)) {
        Write-Warning "Skipping ${name}: description file not found at $descriptionFilePath"
        continue
    }

    try {
        [string] $traversable = if ([bool] $relationshipKind.is_traversable) { 'true' } else { 'false' }
        [string] $bodyMarkdown = Get-Content -Path $descriptionFilePath -Raw
        if ($OpenHoundStructure) {
            $bodyMarkdown = Join-MarkdownSections -Sections @(
                (Get-EdgeSchemaSection -EdgeName $name -Traversable $traversable),
                $bodyMarkdown
            )
        }
        else {
            $bodyMarkdown = Add-TraversableToEdgeSchema -Markdown $bodyMarkdown -Traversable $traversable
        }
        $bodyMarkdown = Convert-BodyMarkdown -Markdown $bodyMarkdown -SiblingBasePath "$DocsBasePath/edges" -CurrentKindName $name

        [string] $outputFilePath = Join-Path -Path $edgesOutputDir -ChildPath "$($name.ToLower()).mdx"

        New-OfficialDoc -Name $name -Description $description -BodyMarkdown $bodyMarkdown -OutputFilePath $outputFilePath
    }
    catch {
        Write-Error "Error processing relationship kind '$name': $($_.Exception.Message)`nScriptStackTrace: $($_.ScriptStackTrace)"
        throw
    }
}
