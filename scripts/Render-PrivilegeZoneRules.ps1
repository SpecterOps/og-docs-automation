<#
.SYNOPSIS
    Converts privilege zone rule files (*.json) into markdown (*.md) or MDX.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExtensionName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $InputDir = (Join-Path -Path $PSScriptRoot -ChildPath '../../../extension/privilege_zone_rules/'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../../privilege_zone_rules.md'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $RulesLinkPath = '../extension/privilege_zone_rules',

    [Parameter(Mandatory = $false)]
    [string] $StripTitlePrefix = '',

    [Parameter(Mandatory = $false)]
    [switch] $OfficialDocs
)

Set-StrictMode -Version Latest

[string] $markdown = ''
if ($OfficialDocs) {
    $markdown += @'
---
title: Privilege Zone Rules
description: "Default Privilege Zone rules for the {0} extension"
icon: "gem"
---

<img noZoom src="/assets/enterprise-AND-community-edition-pill-tag.svg" alt="Applies to BloodHound Enterprise and CE"/>

'@ -f $ExtensionName
} else {
    $markdown += @'
# Privilege Zone Rules

'@
}

$markdown += @'
The following Cypher rules define the default Privilege Zone for the {1} extension.
Each rule is defined in a JSON file located in the [PrivilegeZoneRules]({0}) directory of the {1} repository.

'@ -f $RulesLinkPath, $ExtensionName

Get-ChildItem -File -Path $InputDir -Filter '*.json' | Sort-Object -Property Name | ForEach-Object {
    # Parse the JSON content of the privilege zone rule file
    [psobject] $json = $null
    try {
        $json = Get-Content -Path $PSItem.FullName | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse privilege zone rule file '$($PSItem.FullName)': $($_.Exception.Message)"
        throw
    }

    if (-not $json.name) {
        Write-Warning "Rule file '$($PSItem.FullName)' is missing required 'name' property. Skipping."
        return
    }
    if (-not $json.cypher) {
        Write-Warning "Rule file '$($PSItem.FullName)' is missing required 'cypher' property. Skipping."
        return
    }

    # Remove optional title prefix for cleaner headings
    [string] $title = if ([string]::IsNullOrEmpty($StripTitlePrefix)) {
        $json.name
    } else {
        $json.name -replace [regex]::Escape($StripTitlePrefix)
    }

    # Sanitize line breaks in description and cypher
    [string] $description = $json.description -replace '\n',"`n"
    [string] $cypher = $json.cypher -replace '\n',"`n"

    [string] $fileName = $PSItem.Name

    # Append file-specific markdown
    $markdown += @'

## {0}

{1}

```cypher
{2}
```

This rule is defined in the [{3}]({4}/{3}) file.

'@ -f $title, $description, $cypher, $fileName, $RulesLinkPath
}

# Normalize line endings to CRLF for Git working tree
$markdown = $markdown -replace "`r?`n", "`r`n"

Set-Content -Path $OutputPath -Value $markdown -Encoding UTF8
Write-Host "Wrote $OutputPath" -ForegroundColor DarkGray
