# Edge Doc Template

Use this structure for each edge file. Keep existing `## General Information` and Mermaid diagrams unless they are wrong.
Load the matching platform profile before filling in API headers, UI labels, event names, and reference choices.

```markdown
## Abuse Info

An attacker who controls the source <node type> can <specific action> against the destination <node type>. This matters because <specific impact>.

If the source is a group/team, compromise any member first when the platform inherits permissions through membership. If the source is an application, service integration, API client, token, workflow, MDM object, or IdP, authenticate with the configured client auth method. If this edge is not directly abusable, say so and explain the required adjacent control.

Cleanup and abuse should name the source and destination objects, not just "affected objects."

API examples should follow the current platform profile:

1. Set variables in a fenced `bash` block.
2. Perform the action with `curl`, platform CLI, PowerShell, or source-system tooling.
3. State the expected success signal.
4. Verify the result with a second command.
5. Use the platform's standard auth headers and API version headers.

Cleanup using Admin Console:

1. ...

Cleanup using API:

1. Set variables.

    ```bash
    export PLATFORM_URL="https://example.invalid"
    export PLATFORM_TOKEN="REDACTED"
    ```

2. Perform the API action.

    ```bash
    curl -i -sS \
      -H "Authorization: Bearer $PLATFORM_TOKEN" \
      -H "Accept: application/json" \
      "$PLATFORM_URL/..."
    ```

3. Verify the result.

Verification:

1. ...

## Cleanup after Abuse

Cleanup <edge-specific cleanup summary in one sentence>.

Cleanup using Admin Console:

1. Reverse the concrete action.
2. Restore legitimate users, teams, groups, assignments, settings, credentials, claims, policies, devices, workflows, or source-system state.
3. Trigger or wait for provisioning, sync, check-in, workflow execution, or policy evaluation if relevant.
4. Verify the temporary access is gone.

Cleanup using API:

1. Use exact official endpoints when known.
2. Include reversal and verification requests, or a downstream check when the source system is authoritative.

## Opsec Considerations

Name the audit trail:
- Platform event types or audit actions when known.
- Platform audit logs such as GitHub enterprise/org audit logs, Jamf Pro audit/change-management logs, or Okta System Log.
- Source-system logs for AD, SaaS, IdP, CI/CD, MDM, cloud, or endpoints.
- Downstream logs for SSO, provisioning, group/role changes, workflow runs, MDM commands, and token use.

## References

- [Official vendor documentation page for the key API or behavior](https://example.invalid/)
- [Official event/log documentation when event names are used](https://example.invalid/)
```

Checklist before finishing:

- Source control meaning is explicit.
- Destination compromise or influence is explicit.
- UI/Admin Console steps are actionable.
- API steps include runnable code blocks and are verified against official docs.
- Cleanup is edge-specific and has verification.
- Opsec includes defender-relevant events.
- References are present, official-first, and formatted as markdown links.
