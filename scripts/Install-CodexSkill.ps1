param(
    [string]$SkillName = "openhound-edge-docs",
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }),
    [switch]$Copy
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AutomationRoot = Resolve-Path (Join-Path $ScriptDir "..")
$SkillSource = Join-Path $AutomationRoot "skills/$SkillName"
$SkillManifest = Join-Path $SkillSource "SKILL.md"

if (-not (Test-Path -LiteralPath $SkillManifest)) {
    throw "Skill '$SkillName' was not found at $SkillSource"
}

$SkillsDir = Join-Path $CodexHome "skills"
New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null

$SkillTarget = Join-Path $SkillsDir $SkillName
if (Test-Path -LiteralPath $SkillTarget) {
    $Item = Get-Item -LiteralPath $SkillTarget -Force
    if ($Item.LinkType -eq "SymbolicLink" -and $Item.Target -eq $SkillSource) {
        Write-Host "Skill '$SkillName' is already installed at $SkillTarget"
        return
    }

    $Backup = "$SkillTarget.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Move-Item -LiteralPath $SkillTarget -Destination $Backup
    Write-Host "Moved existing skill to $Backup"
}

if ($Copy) {
    Copy-Item -Recurse -Force -LiteralPath $SkillSource -Destination $SkillTarget
    Write-Host "Copied skill '$SkillName' to $SkillTarget"
    return
}

try {
    New-Item -ItemType SymbolicLink -Path $SkillTarget -Target $SkillSource | Out-Null
    Write-Host "Linked skill '$SkillName' to $SkillTarget"
} catch {
    Write-Warning "Could not create a symlink: $($_.Exception.Message)"
    Copy-Item -Recurse -Force -LiteralPath $SkillSource -Destination $SkillTarget
    Write-Host "Copied skill '$SkillName' to $SkillTarget instead"
}
