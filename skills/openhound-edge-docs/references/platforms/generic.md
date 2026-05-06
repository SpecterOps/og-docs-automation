# Generic Platform Profile

Use this profile when the OpenGraph extension is not Okta, GitHub, or Jamf, or when no platform-specific profile exists yet.

## Source Selection

Prefer sources in this order:

1. Official platform API/reference documentation.
2. Official platform admin-console or product help documentation.
3. Downstream vendor documentation for crossed systems such as IdPs, directories, cloud providers, CI/CD systems, MDMs, or SaaS apps.
4. BloodHound/OpenHound extension docs and generated schema pages.
5. Security research and tools that explain realistic abuse paths.

## API Examples

Use platform-native authentication and headers. For HTTP APIs, default to this shape and replace headers with the platform's official requirements:

```bash
export PLATFORM_URL="https://platform.example"
export PLATFORM_TOKEN="REDACTED"
export TARGET_ID="..."

curl -sS \
  -H "Authorization: Bearer $PLATFORM_TOKEN" \
  -H "Accept: application/json" \
  "$PLATFORM_URL/api/path/$TARGET_ID"
```

## Required Platform Notes

- Identify how permissions are inherited: users, groups, teams, roles, apps, API clients, tokens, workflows, or device scopes.
- Identify what re-evaluates the edge: sign-in, sync, import, workflow execution, device check-in, inventory update, policy evaluation, or API call.
- For non-direct edges, explain the adjacent control needed before the relationship matters.
- Cleanup must reverse both graph-visible platform state and downstream side effects.
