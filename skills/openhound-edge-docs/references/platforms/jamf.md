# Jamf Platform Profile

Use this profile for `jamf_` edge docs and OpenHound Jamf/JamfHound repositories.

## Quality Bar

Jamf edge docs must be explicit about whether control affects Jamf Pro configuration, API clients, SSO principals, MDM commands, policies, scripts, packages, computer extension attributes, sites, or managed computers. Many Jamf paths are only realized when a scoped policy runs on a managed computer or when a device checks in.

API examples should:

- Start with `JAMF_URL`, `JAMF_TOKEN`, Jamf object IDs, controlled account/group IDs, and target computer IDs.
- Use `Authorization: Bearer $JAMF_TOKEN`.
- Use `Accept: application/json` and `Content-Type: application/json` where required.
- Include expected success signals such as returned object IDs, changed scope, queued MDM command, policy execution, or removed object.

## Preferred Sources

1. Jamf Pro API docs on `developer.jamf.com/jamf-pro`.
2. Jamf Pro product/help docs on `learn.jamf.com` and `help.jamf.com`.
3. Jamf Classic API docs when a capability exists only in the Classic API.
4. Apple Platform Deployment and MDM docs for device-side effects.
5. BloodHound Jamf overview, schema, and edge docs for graph semantics.
6. Jamf security research and tooling for realistic abuse technique context.

## Common Authentication Pattern

Verify the current Jamf Pro auth flow before writing exact steps. A common bearer-token setup is:

```bash
export JAMF_URL="https://contoso.jamfcloud.com"
export JAMF_USER="api-user"
export JAMF_PASSWORD="REDACTED"

export JAMF_TOKEN="$(
  curl -sS -X POST \
    -u "$JAMF_USER:$JAMF_PASSWORD" \
    -H "Accept: application/json" \
    "$JAMF_URL/api/v1/auth/token" \
    | jq -r '.token'
)"
```

Then use:

```bash
curl -sS \
  -H "Authorization: Bearer $JAMF_TOKEN" \
  -H "Accept: application/json" \
  "$JAMF_URL/api/v1/..."
```

For API clients, use the officially documented Jamf Pro API client credential flow rather than username/password.

## Edge-Specific Guidance

- Admin/scope edges such as `jamf_AdminToTenant`, `jamf_AdminToSite`, and scoped account/group/API-client edges: explain which Jamf privilege set or site scope allows the action and how group membership or API client privileges are inherited.
- Policy/script/package/computer-extension edges such as `jamf_CreatePolicies`, `jamf_CreateScripts`, or `jamf_CreateComputerExtensions`: explain how control lets the attacker create code or configuration that later runs on computers.
- Computer/device edges: distinguish Jamf inventory visibility from MDM command capability and local code execution. Include trigger requirements such as recurring check-in, policy trigger, Self Service action, enrollment state, or MDM command execution.
- SSO edges such as `jamf_SSO_Login`: explain IdP claim mapping, Jamf account/group matching, privilege inheritance, and how source IdP control becomes a Jamf principal.
- Container/site edges such as `jamf_Contains`: treat them as scope metadata unless combined with a principal that has privileges over the source tenant/site.

## Cleanup Themes

- Remove temporary Jamf policies, scripts, packages, extension attributes, prestage changes, configuration profiles, device groups, and policy scopes.
- Restore original site assignment, account/group privileges, API client privileges, and SSO mappings.
- Stop recurring policy triggers and remove Self Service exposure.
- Rotate Jamf account/API client credentials and any local admin or management credentials exposed to policies.
- Verify target computers no longer have pending MDM commands, recurring policy scope, or installed malicious profiles/scripts/packages.

## Opsec Sources

Use Jamf Pro audit/change-management logs, policy logs, computer inventory history, MDM command history, account/API client activity, SSO/IdP logs, macOS unified logs, install logs, and EDR telemetry. User-visible prompts, device locks/wipes, profile installs, and recurring check-in failures are noisy.

## Research References And Tools

Use these selectively when they directly support Jamf abuse, cleanup, or opsec:

- SpecterOps: Leveraging Jamf For Red Teaming in Enterprise Environments
- GitHub: Come to the Dark Side, We Have Apples
- 1nf1n1ty: macOS Red Teaming | Abusing MDMs
- Eve Jamf Post Exploitation Toolkit
- Jamf-Attack-Toolkit

## Common References

- [Jamf Pro API](https://developer.jamf.com/jamf-pro)
- [Jamf Pro documentation](https://learn.jamf.com)
- [Jamf Pro API roles and clients](https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/API_Roles_and_Clients.html)
- [Jamf Pro policies](https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Policies.html)
- [Jamf Pro scripts](https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Scripts.html)
- [Jamf Pro computer groups](https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Computer_Groups.html)
- [Apple device management](https://support.apple.com/guide/deployment/welcome/web)
- [BloodHound Jamf overview](https://bloodhound.specterops.io/opengraph/extensions/jamf/overview)
