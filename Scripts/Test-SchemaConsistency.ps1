<#
.SYNOPSIS
    Checks for inconsistencies in an OpenGraph extension's schema, documentation, and source.

.DESCRIPTION
    Reads the og-docs.json configuration file and compares node kinds and edge kinds across
    up to three sources:

      1. The extension schema JSON file (required — path from og-docs.json extensionPath)
      2. Node and Edge documentation files (paths from og-docs.json edgeDescriptionsDir,
         nodeDescriptionsDir)
      3. Collector source file (optional — pass -SourcePath; works with any language)

    Reports:
      - Duplicate entries within the schema
      - Kinds present in source but missing from the schema (when -SourcePath is given)
      - Kinds present in the schema but not emitted by source (when -SourcePath is given)
      - Kinds present in documentation but missing from the schema
      - Kinds present in the schema but missing from documentation
      - Naming convention issues (near-duplicate names differing only by underscore/casing)
      - Saved query references to extension nodes/edges not present in the schema
      - Mermaid diagram edges whose arrow style (solid/dashed) conflicts with is_traversable

.EXAMPLE
    pwsh -File Test-SchemaConsistency.ps1
    pwsh -File Test-SchemaConsistency.ps1 -SourcePath ../../githound.ps1
    pwsh -File Test-SchemaConsistency.ps1 -ConfigFile ../../Documentation/og-docs.json
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $ConfigFile = (Join-Path -Path $PSScriptRoot -ChildPath '../../Documentation/og-docs.json'),

    [Parameter(Mandatory = $false)]
    [string] $SourcePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Read config ───────────────────────────────────────────────────────────────
if (-not (Test-Path -Path $ConfigFile -PathType Leaf)) {
    Write-Error "Config file not found: $ConfigFile"
    $host.SetShouldExit(1)
    return
}

[psobject] $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
[string] $configDir = (Get-Item -Path $ConfigFile).Directory.FullName
[string] $repoRoot = (Get-Item -Path (Join-Path -Path $configDir -ChildPath '..')).FullName

if (-not $config.extensionPath) {
    Write-Error "Config file must specify 'extensionPath'."
    $host.SetShouldExit(1)
    return
}

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

[string] $SchemaPath   = Resolve-ConfigPath $config.extensionPath
[string] $NodeDescDir  = Get-ConfigPath 'nodeDescriptionsDir' 'Documentation/NodeDescriptions'
[string] $EdgeDescDir  = Get-ConfigPath 'edgeDescriptionsDir' 'Documentation/EdgeDescriptions'
[string] $QueriesDir   = Get-ConfigPath 'queriesDir'

# ── Parse schema JSON ─────────────────────────────────────────────────────────
$schema = Get-Content -Raw $SchemaPath | ConvertFrom-Json
[string] $extensionName = $schema.schema.name
[string] $namespace = if ($schema.schema.namespace) { $schema.schema.namespace } else { '' }

[string[]] $schemaNodeNames = @($schema.node_kinds | ForEach-Object { $_.name })
[string[]] $schemaEdgeNames = @($schema.relationship_kinds | ForEach-Object { $_.name })

# Deduplicated sets for comparisons (created early so source scanning can use them)
$schemaNodeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$schemaNodeNames)
$schemaEdgeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$schemaEdgeNames)

Write-Host "Extension: $extensionName | Schema: $SchemaPath" -ForegroundColor Cyan

# ── Optionally parse source file ──────────────────────────────────────────────
$sourceNodeKinds = [System.Collections.Generic.HashSet[string]]::new()
$sourceEdgeKinds = [System.Collections.Generic.HashSet[string]]::new()
[bool] $hasSource = $false

if ($SourcePath) {
    if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
        Write-Warning "Source file not found: $SourcePath (skipping source checks)"
    } else {
        $SourcePath = (Resolve-Path $SourcePath).Path
        $sourceContent = Get-Content -Raw $SourcePath

        # Language-agnostic extraction: find all quoted or bare strings matching the
        # namespace prefix (e.g. "GH_SomeKind", 'GH_SomeKind', or bare GH_SomeKind).
        # This works for PowerShell, Python, Go, JavaScript, and other languages.
        if (-not $namespace) {
            Write-Warning 'Schema has no namespace — cannot detect kinds in source without a prefix. Skipping source checks.'
        } else {
            $hasSource = $true
            [string] $escapedPrefix = [regex]::Escape("${namespace}_")
            # Match quoted strings: "GH_Foo" or 'GH_Foo', and bare identifiers: GH_Foo
            $kindMatches = [regex]::Matches($sourceContent, "(?:['""])($escapedPrefix\w+)(?:['""])|\b($escapedPrefix\w+)\b")
            foreach ($m in $kindMatches) {
                [string] $kind = if ($m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                if ($schemaNodeSet.Contains($kind) -or $sourceNodeKinds.Contains($kind)) {
                    $null = $sourceNodeKinds.Add($kind)
                } elseif ($schemaEdgeSet.Contains($kind) -or $sourceEdgeKinds.Contains($kind)) {
                    $null = $sourceEdgeKinds.Add($kind)
                } else {
                    # Unknown — add to both candidate sets; comparison will sort it out
                    $null = $sourceNodeKinds.Add($kind)
                    $null = $sourceEdgeKinds.Add($kind)
                }
            }
        }
    }
}

# ── Parse documentation ───────────────────────────────────────────────────────
$docEdgeKinds = [System.Collections.Generic.HashSet[string]]::new()
$docNodeKinds = [System.Collections.Generic.HashSet[string]]::new()

# Parse edge description files
if (Test-Path $EdgeDescDir) {
    Get-ChildItem -Path $EdgeDescDir -Filter '*.md' | ForEach-Object {
        $null = $docEdgeKinds.Add($_.BaseName)
    }
}

# Parse node description files
if (Test-Path $NodeDescDir) {
    Get-ChildItem -Path $NodeDescDir -Filter '*.md' | ForEach-Object {
        $null = $docNodeKinds.Add($_.BaseName)
    }
}

# ── Reporting ──────────────────────────────────────────────────────────────────
$issueCount = 0

function Write-Issue {
    param([string]$Category, [string]$Message)
    $script:issueCount++
    Write-Host "  [$Category] $Message" -ForegroundColor Yellow
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n═══ $Title ═══" -ForegroundColor Cyan
}

# ── 1. Duplicates in schema ──────────────────────────────────────────────────
Write-Section 'Duplicates in schema'

$nodeNameCounts = $schemaNodeNames | Group-Object | Where-Object { $_.Count -gt 1 }
$edgeNameCounts = $schemaEdgeNames | Group-Object | Where-Object { $_.Count -gt 1 }

if ($nodeNameCounts) {
    foreach ($dup in $nodeNameCounts) {
        Write-Issue 'DUPLICATE NODE' "$($dup.Name) appears $($dup.Count) times"
    }
} else {
    Write-Host '  No duplicate node kinds found.' -ForegroundColor Green
}

if ($edgeNameCounts) {
    foreach ($dup in $edgeNameCounts) {
        Write-Issue 'DUPLICATE EDGE' "$($dup.Name) appears $($dup.Count) times"
    }
} else {
    Write-Host '  No duplicate edge kinds found.' -ForegroundColor Green
}

# ── 2. Source vs schema (optional) ───────────────────────────────────────────
if ($hasSource) {
    [string] $sourceFileName = Split-Path -Leaf $SourcePath
    Write-Section "Source ($sourceFileName) vs schema"

    Write-Host "`n  --- Node Kinds ---" -ForegroundColor White
    $sourceOnlyNodes = $sourceNodeKinds | Where-Object { -not $schemaNodeSet.Contains($_) } | Sort-Object
    $schemaOnlyNodes = $schemaNodeSet | Where-Object { -not $sourceNodeKinds.Contains($_) } | Sort-Object

    if ($sourceOnlyNodes) {
        Write-Host '  In source but NOT in schema:' -ForegroundColor Yellow
        foreach ($n in $sourceOnlyNodes) { Write-Issue 'MISSING IN SCHEMA' $n }
    } else {
        Write-Host '  All source node kinds are in schema.' -ForegroundColor Green
    }

    if ($schemaOnlyNodes) {
        Write-Host '  In schema but NOT in source:' -ForegroundColor Yellow
        foreach ($n in $schemaOnlyNodes) { Write-Issue 'EXTRA IN SCHEMA' $n }
    } else {
        Write-Host '  All schema node kinds are in source.' -ForegroundColor Green
    }

    Write-Host "`n  --- Edge Kinds ---" -ForegroundColor White
    $sourceOnlyEdges = $sourceEdgeKinds | Where-Object { -not $schemaEdgeSet.Contains($_) } | Sort-Object
    $schemaOnlyEdges = $schemaEdgeSet | Where-Object { -not $sourceEdgeKinds.Contains($_) } | Sort-Object

    if ($sourceOnlyEdges) {
        Write-Host '  In source but NOT in schema:' -ForegroundColor Yellow
        foreach ($e in $sourceOnlyEdges) { Write-Issue 'MISSING IN SCHEMA' $e }
    } else {
        Write-Host '  All source edge kinds are in schema.' -ForegroundColor Green
    }

    if ($schemaOnlyEdges) {
        Write-Host '  In schema but NOT in source:' -ForegroundColor Yellow
        foreach ($e in $schemaOnlyEdges) { Write-Issue 'EXTRA IN SCHEMA' $e }
    } else {
        Write-Host '  All schema edge kinds are in source.' -ForegroundColor Green
    }
}

# ── 3. Documentation vs schema ───────────────────────────────────────────────
Write-Section 'Documentation vs schema'

# Filter doc edge kinds to exclude node kinds that may appear in table columns
$nodeKindsForFilter = [System.Collections.Generic.HashSet[string]]::new($schemaNodeSet)
if ($hasSource) { foreach ($n in $sourceNodeKinds) { $null = $nodeKindsForFilter.Add($n) } }
$docEdgeOnly = $docEdgeKinds | Where-Object { -not $nodeKindsForFilter.Contains($_) }

Write-Host "`n  --- Edge Kinds ---" -ForegroundColor White
$docOnlyEdges = $docEdgeOnly | Where-Object { -not $schemaEdgeSet.Contains($_) } | Sort-Object
$schemaNotInDoc = $schemaEdgeSet | Where-Object { -not $docEdgeKinds.Contains($_) } | Sort-Object

if ($docOnlyEdges) {
    Write-Host '  In documentation but NOT in schema:' -ForegroundColor Yellow
    foreach ($e in $docOnlyEdges) { Write-Issue 'DOC ONLY' $e }
} else {
    Write-Host '  All documented edge kinds are in schema.' -ForegroundColor Green
}

if ($schemaNotInDoc) {
    Write-Host '  In schema but NOT in documentation:' -ForegroundColor Yellow
    foreach ($e in $schemaNotInDoc) { Write-Issue 'UNDOCUMENTED' $e }
} else {
    Write-Host '  All schema edge kinds are documented.' -ForegroundColor Green
}

Write-Host "`n  --- Node Kinds ---" -ForegroundColor White
$docNodeOnly = $docNodeKinds | Where-Object { -not $schemaNodeSet.Contains($_) } | Sort-Object
$schemaNodeNotInDoc = $schemaNodeSet | Where-Object { -not $docNodeKinds.Contains($_) } | Sort-Object

if ($docNodeOnly) {
    Write-Host '  In documentation but NOT in schema:' -ForegroundColor Yellow
    foreach ($n in $docNodeOnly) { Write-Issue 'DOC ONLY' $n }
} else {
    Write-Host '  All documented node kinds are in schema.' -ForegroundColor Green
}

if ($schemaNodeNotInDoc) {
    Write-Host '  In schema but NOT in documentation:' -ForegroundColor Yellow
    foreach ($n in $schemaNodeNotInDoc) { Write-Issue 'UNDOCUMENTED' $n }
} else {
    Write-Host '  All schema node kinds are documented.' -ForegroundColor Green
}

# ── 4. Naming convention check ────────────────────────────────────────────────
Write-Section 'Naming convention check'

$allKnownEdges = [System.Collections.Generic.HashSet[string]]::new()
foreach ($e in $sourceEdgeKinds) { $null = $allKnownEdges.Add($e) }
foreach ($e in $schemaEdgeSet) { $null = $allKnownEdges.Add($e) }
foreach ($e in $docEdgeKinds) { $null = $allKnownEdges.Add($e) }

$normalizedEdges = @{}
foreach ($e in $allKnownEdges) {
    $normalized = $e.ToLower() -replace '_', ''
    if (-not $normalizedEdges.ContainsKey($normalized)) {
        $normalizedEdges[$normalized] = [System.Collections.Generic.List[string]]::new()
    }
    $normalizedEdges[$normalized].Add($e)
}

$allNamingIssues = @()
$allNamingIssues += @($normalizedEdges.Values | Where-Object { $_.Count -gt 1 })

$allKnownNodes = [System.Collections.Generic.HashSet[string]]::new()
foreach ($n in $sourceNodeKinds) { $null = $allKnownNodes.Add($n) }
foreach ($n in $schemaNodeSet) { $null = $allKnownNodes.Add($n) }
foreach ($n in $docNodeKinds) { $null = $allKnownNodes.Add($n) }

$normalizedNodes = @{}
foreach ($n in $allKnownNodes) {
    $normalized = $n.ToLower() -replace '_', ''
    if (-not $normalizedNodes.ContainsKey($normalized)) {
        $normalizedNodes[$normalized] = [System.Collections.Generic.List[string]]::new()
    }
    $normalizedNodes[$normalized].Add($n)
}

$allNamingIssues += @($normalizedNodes.Values | Where-Object { $_.Count -gt 1 })

if ($allNamingIssues.Count -gt 0) {
    foreach ($group in $allNamingIssues) {
        $sorted = $group | Sort-Object
        Write-Issue 'NAMING' "Possible naming mismatch: $($sorted -join ' vs ')"
    }
} else {
    Write-Host '  No naming convention issues found.' -ForegroundColor Green
}

# ── 5. Saved queries vs schema ────────────────────────────────────────────────
if ($QueriesDir -and (Test-Path $QueriesDir)) {
    Write-Section 'Saved queries vs schema'

    # Build the prefix used to identify kinds belonging to this extension (e.g. "GH_")
    [string] $nsPrefix = if ($namespace) { "${namespace}_" } else { '' }

    [int] $issuesBefore = $issueCount
    foreach ($queryFile in Get-ChildItem -Path $QueriesDir -Filter '*.json') {
        $queryJson = Get-Content -Raw $queryFile.FullName | ConvertFrom-Json
        if (-not $queryJson.query) { continue }
        [string] $cypher = $queryJson.query
        [string] $queryName = if ($queryJson.name) { $queryJson.name } else { $queryFile.BaseName }
        $reportedInFile = [System.Collections.Generic.HashSet[string]]::new()

        # Extract node labels — :SomeKind followed by whitespace, {, or )
        $labelMatches = [regex]::Matches($cypher, ':(\w+)(?:\s*[{\)]|\s*\))')
        foreach ($m in $labelMatches) {
            [string] $label = $m.Groups[1].Value
            if ($nsPrefix -and $label.StartsWith($nsPrefix) -and -not $schemaNodeSet.Contains($label) -and $reportedInFile.Add("node:$label")) {
                Write-Issue 'QUERY NODE' "$label not in schema — used in '$queryName' ($($queryFile.Name))"
            }
        }

        # Extract relationship types — [:REL_TYPE] or [:REL1|REL2|REL3] or [:REL*1..]
        $relBlockMatches = [regex]::Matches($cypher, '\[:([^\]]+)\]')
        foreach ($m in $relBlockMatches) {
            [string] $relBlock = $m.Groups[1].Value
            # Strip variable-length quantifiers like *1..
            $relBlock = $relBlock -replace '\*[\d.]*$', ''
            # Split on | to handle multi-type relationships
            foreach ($rel in ($relBlock -split '\|')) {
                [string] $relName = $rel.Trim()
                if (-not $relName) { continue }
                if ($nsPrefix -and $relName.StartsWith($nsPrefix) -and -not $schemaEdgeSet.Contains($relName) -and $reportedInFile.Add("edge:$relName")) {
                    Write-Issue 'QUERY EDGE' "$relName not in schema — used in '$queryName' ($($queryFile.Name))"
                }
            }
        }
    }

    if ($issueCount -eq $issuesBefore) {
        Write-Host '  All query node/edge references found in schema.' -ForegroundColor Green
    }
}

# ── 6. Mermaid diagram traversability ─────────────────────────────────────────
Write-Section 'Mermaid diagram traversability'

# Build a lookup: edge name → is_traversable (bool)
$edgeTraversable = @{}
foreach ($rel in $schema.relationship_kinds) {
    $edgeTraversable[$rel.name] = [bool]$rel.is_traversable
}

# Scan all markdown files in both edge and node description directories
[string[]] $mermaidDirs = @($EdgeDescDir, $NodeDescDir) | Where-Object { $_ -and (Test-Path $_) }
[int] $issuesBefore = $issueCount

foreach ($dir in $mermaidDirs) {
    foreach ($mdFile in Get-ChildItem -Path $dir -Filter '*.md') {
        [string[]] $lines = Get-Content -Path $mdFile.FullName
        [bool] $inMermaid = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            [string] $line = $lines[$i]

            if ($line -match '^\s*```mermaid') { $inMermaid = $true; continue }
            if ($line -match '^\s*```' -and $inMermaid) { $inMermaid = $false; continue }
            if (-not $inMermaid) { continue }

            # Match solid edges: -- EdgeName -->
            $solidMatches = [regex]::Matches($line, '--\s+(\w+)\s+-->')
            foreach ($m in $solidMatches) {
                [string] $edgeName = $m.Groups[1].Value
                if ($edgeTraversable.ContainsKey($edgeName) -and -not $edgeTraversable[$edgeName]) {
                    Write-Issue 'MERMAID' "$edgeName is non-traversable but drawn with solid arrow (-->) in $($mdFile.Name):$($i + 1)"
                }
            }

            # Match dashed edges: -. EdgeName .->
            $dashedMatches = [regex]::Matches($line, '-\.\s+(\w+)\s+\.->')
            foreach ($m in $dashedMatches) {
                [string] $edgeName = $m.Groups[1].Value
                if ($edgeTraversable.ContainsKey($edgeName) -and $edgeTraversable[$edgeName]) {
                    Write-Issue 'MERMAID' "$edgeName is traversable but drawn with dashed arrow (.->) in $($mdFile.Name):$($i + 1)"
                }
            }
        }
    }
}

if ($issueCount -eq $issuesBefore) {
    Write-Host '  All mermaid diagram edges match schema traversability.' -ForegroundColor Green
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Section 'Summary'
[string] $summaryLine = "Schema nodes: $($schemaNodeSet.Count) | Doc nodes: $($docNodeKinds.Count)"
if ($hasSource) { $summaryLine += " | Source nodes: $($sourceNodeKinds.Count)" }
Write-Host "  $summaryLine" -ForegroundColor White
[string] $summaryLine2 = "Schema edges: $($schemaEdgeSet.Count) | Doc edges: $($docEdgeKinds.Count)"
if ($hasSource) { $summaryLine2 += " | Source edges: $($sourceEdgeKinds.Count)" }
Write-Host "  $summaryLine2" -ForegroundColor White

if ($issueCount -eq 0) {
    Write-Host "`n  All checks passed — no inconsistencies found." -ForegroundColor Green
} else {
    Write-Host "`n  Found $issueCount issue(s)." -ForegroundColor Red
}

exit [Math]::Min($issueCount, 255)
