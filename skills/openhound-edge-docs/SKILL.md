---
name: openhound-edge-docs
description: Use when creating, reviewing, or improving OpenHound/BloodHound OpenGraph edge description markdown for Okta, GitHub, Jamf, or other OpenGraph extensions with Abuse Info, Cleanup after Abuse, Opsec Considerations, platform-specific references, UI/API steps, and validation checks.
metadata:
  short-description: High-quality OpenHound edge documentation
---

# OpenHound Edge Docs

Use this skill when editing `descriptions/edges/*.md` files for an OpenHound extension.

This skill is distributed with `og-docs-automation` under `skills/openhound-edge-docs`.
Install it into Codex with:

```bash
pwsh docs/og-docs-automation/scripts/Install-CodexSkill.ps1
```

## Workflow

1. Inspect the target edge docs, `extension/schema.json`, and the collector/model code that emits the edge.
2. Classify each edge into a family from `references/edge-family-playbooks.md`.
3. Use `references/edge-doc-template.md` as the required quality bar.
4. Detect the platform from schema metadata, node/edge prefixes, repository name, and collector code. Load exactly one matching platform profile when available:
   - Okta: `references/platforms/okta.md`
   - GitHub: `references/platforms/github.md`
   - Jamf: `references/platforms/jamf.md`
   - Unknown or new platform: `references/platforms/generic.md`
5. Verify current API, UI, and event/log details against official vendor docs before adding endpoint names, UI labels, event types, or command examples. Use platform profiles for source selection and conventions.
6. Add or update:
   - `## Abuse Info`
   - `## Cleanup after Abuse`
   - `## Opsec Considerations`
   - `## References`
7. Make content edge-specific. Avoid generic sentences that could be pasted into any edge.
8. Prefer exact UI/Admin Console steps and API/CLI steps. If an edge crosses into another platform, IdP, MDM, cloud, CI/CD, SaaS, endpoint, or directory, say which source-system API or console must be used and what to verify.
9. Do not invent endpoints, event names, console labels, permissions, or capabilities. If uncertain, use official-doc wording and state the dependency.
10. Match the quality bar for the current platform:
   - API sections must include runnable fenced code blocks where an API can perform or verify the action.
   - Start examples with exported variables for the platform base URL, token, IDs, and controlled values.
   - Include the action request, expected success signal, and at least one verification request.
   - Use the platform profile's authentication/header style.
   - Cleanup API steps must include concrete reversal and verification blocks.
   - If the action must happen in another source system and no platform API can do it, provide a source-system command/API placeholder plus platform API calls that verify, revoke, or clean up the platform side.
   - References must use markdown link syntax (`- [Title](URL)`) and prefer operation-specific official docs before research references.
11. Validate from the repo root:

   ```bash
   python3 docs/og-docs-automation/skills/openhound-edge-docs/scripts/audit_edge_docs.py descriptions/edges
   git diff --check
   pwsh docs/og-docs-automation/scripts/Test-SchemaConsistency.ps1
   ```

## Platform Detection

Use this order:

1. `extension/schema.json` metadata such as `namespace`, `source_kind`, `environment_kind`, or display/name fields.
2. Edge filename prefixes: `Okta_`, `GH_`, `jamf_`, or other extension-specific prefixes.
3. Collector package/module names and repository names.
4. Existing docs under `descriptions/nodes`, `descriptions/edges`, and `docs/graph`.

If several platforms are involved, load the source platform profile plus any downstream platform profile needed for API cleanup or verification.

## Quality Rules

- Every edge needs references. Use official vendor docs first.
- References should use short markdown link titles, operation-specific official docs first, then research/tool links only when they add edge-specific value.
- Non-direct edges still need a path: explain how control of the source can compromise, influence, or help compromise the destination.
- Cleanup must describe what is being cleaned up for that exact edge before the steps.
- Cleanup steps must include UI/Admin Console and API/CLI guidance when possible.
- API examples must include code blocks for setup, action, and verification when the target platform exposes an API.
- Opsec should name specific log sources and event types when known.
- Keep the docs useful for operators and defenders; avoid filler.

## Okta Compatibility

For Okta edge docs, keep using `Okta_AddMember.md` as the minimum quality bar: concrete abuse path, concrete cleanup path, runnable Okta API code blocks, verification, opsec, and markdown-link references. The full Okta-specific source and API guidance lives in `references/platforms/okta.md`.
