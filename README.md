# OG Docs Automation

A set of PowerShell scripts that generate documentation for BloodHound OpenGraph extensions. Designed to be included as a Git submodule in each extension repository.

## Quick start

1. Add this repo as a submodule:

   ```bash
   git submodule add git@github.com:SpecterOps/og-docs-automation.git OGDocsAutomation
   ```

2. Copy the example config to your `Documentation/` folder and edit it:

   ```bash
   cp OGDocsAutomation/og-docs.example.json Documentation/og-docs.json
   ```

3. Generate docs:

   ```bash
   # Local markdown docs (default)
   pwsh OGDocsAutomation/Scripts/Render-Docs.ps1

   # Official MDX docs for the BloodHound documentation site
   pwsh OGDocsAutomation/Scripts/Render-Docs.ps1 -Mode Official
   ```

## How it works

`Render-Docs.ps1` reads `Documentation/og-docs.json` and orchestrates the individual render scripts. All paths in the config are resolved relative to the repository root (the parent of the `Documentation/` directory containing the config file).

### Local mode

Generates plain markdown files in `Documentation/`:

| Output | Script |
|--------|--------|
| `Documentation/Icons/*.png` | Render-CustomNodeIcons |
| `Documentation/Queries.md` | Render-CustomQueries |
| `Documentation/PrivilegeZoneRules.md` | Render-PrivilegeZoneRules |
| `Documentation/Schema.md` | Render-Schema |

### Official mode

Generates MDX files with frontmatter, Mintlify components, and a `docs.json` navigation file under `Documentation/OfficialDocs/`:

| Output | Script |
|--------|--------|
| Icon PNGs | Render-CustomNodeIcons |
| Static image copy | *(built into Render-Docs)* |
| `queries.mdx` | Render-CustomQueries |
| `privilege-zone-rules.mdx` | Render-PrivilegeZoneRules |
| Per-node and per-edge `.mdx` files | Render-NodeAndEdgeDocs |
| `schema.mdx` | Render-Schema |
| `docs.json` | Render-OfficialDocsJson |

## Configuration reference

The `og-docs.json` file configures all paths and settings. Only `extensionPath` is required; everything else has sensible defaults.

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `extensionPath` | string | Yes | — | Path to the extension schema JSON file (e.g. `schema.json`). |
| `gitHubBaseUrl` | string | No | `https://github.com/SpecterOps/{ExtensionName}` | Base URL of the GitHub repository. Used to generate source links in official docs. |
| `stripTitlePrefix` | string | No | `""` | Prefix stripped from query and rule names in headings (e.g. `"MyExt: "`). |
| `queriesDir` | string | No | `Src/Queries` | Directory containing custom Cypher query JSON files. |
| `zoneRulesDir` | string | No | `Src/PrivilegeZoneRules` | Directory containing privilege zone rule JSON files. |
| `nodeDescriptionsDir` | string | No | `Documentation/NodeDescriptions` | Directory containing per-node `.md` description files. Used by Render-NodeAndEdgeDocs in official mode. |
| `edgeDescriptionsDir` | string | No | `Documentation/EdgeDescriptions` | Directory containing per-edge `.md` description files. Used by Render-NodeAndEdgeDocs in official mode. |
| `imagesDir` | string | No | `Documentation/Images` | Directory containing static image assets. Copied to official docs output with lowercased filenames. |
| `iconSize` | integer | No | `32` | Width and height in pixels for generated node icon PNGs (16–512). |
| `iconScale` | number | No | `0.55` | Scale of the Font Awesome icon within the circle (0.1–1.0). |

## Render-Docs.ps1 parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ConfigFile` | `../../Documentation/og-docs.json` (relative to script) | Path to the configuration file. |
| `-Mode` | `Local` | `Local` for plain markdown, `Official` for MDX with navigation JSON. |

## Individual scripts

Each script can also be invoked directly with explicit parameters for one-off use or debugging. See the parameter blocks at the top of each `.ps1` file for details.

| Script | Purpose |
|--------|---------|
| `Render-CustomNodeIcons.ps1` | Generates PNG icons from Font Awesome for each node kind. Requires PowerShell 7+. |
| `Render-CustomQueries.ps1` | Converts query JSON files to markdown/MDX. |
| `Render-PrivilegeZoneRules.ps1` | Converts privilege zone rule JSON files to markdown/MDX. |
| `Render-Schema.ps1` | Generates a schema overview with node and edge tables. |
| `Render-NodeAndEdgeDocs.ps1` | Generates individual MDX pages per node and edge kind (official mode only). |
| `Render-OfficialDocsJson.ps1` | Generates `docs.json` navigation metadata (official mode only). |

## Requirements

- PowerShell 5.1+ (PowerShell 7+ required for icon rendering)
- Internet access on first run (icon rendering downloads NuGet packages and Font Awesome SVGs)

## Troubleshooting

### SkiaSharp fails on Linux

If icon rendering fails with `The type initializer for 'SkiaSharp.SKImageInfo' threw an exception`, install the required system libraries:

**Debian / Ubuntu:**

```bash
sudo apt-get install -y libfontconfig1
```

**RHEL / Fedora:**

```bash
sudo dnf install -y fontconfig
```

**Alpine:**

```bash
apk add fontconfig
```

The `SkiaSharp.NativeAssets.Linux.NoDependencies` NuGet package bundles most native dependencies statically, but still requires `libfontconfig` from the system.
