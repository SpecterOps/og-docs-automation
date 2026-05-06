# Okta Reference Sources

The canonical Okta platform profile is now `references/platforms/okta.md`. Keep this file for compatibility with older prompts and local notes; do not add new Okta guidance here unless it is also added to the platform profile.

Use official Okta sources for current API, Admin Console, and event names.

Preferred source order:

1. Okta Management API OpenAPI docs on `developer.okta.com/docs/api/openapi/okta-management/management/`
2. Okta guides on `developer.okta.com/docs/`
3. Okta help docs on `help.okta.com`
4. Downstream vendor docs for non-Okta systems such as AD, GitHub, Jamf, Snowflake, or an IdP.
5. BloodHound Okta overview research references and tools for technique context and abuse ideas.

Search patterns:

```text
site:developer.okta.com/docs/api/openapi/okta-management/management/tag/Group/ assign user to group
site:developer.okta.com/docs/api/openapi/okta-management/management/tag/ApplicationUsers/ unassign application user
site:developer.okta.com/docs/api/openapi/okta-management/management/tag/UserFactor/ delete factor
site:developer.okta.com/docs/api/openapi/okta-management/management/tag/UserSessions/ clear user sessions
site:developer.okta.com/docs/api/openapi/okta-management/management/tag/RoleAssignmentAUser/ role assignment
site:developer.okta.com/docs/reference/api/event-types/ <event type>
```

Common API patterns to verify before citing:

- Group membership:
  - `PUT /api/v1/groups/{groupId}/users/{userId}`
  - `DELETE /api/v1/groups/{groupId}/users/{userId}`
  - `GET /api/v1/groups/{groupId}/users`
- Application assignments:
  - `DELETE /api/v1/apps/{appId}/users/{userId}`
  - `DELETE /api/v1/apps/{appId}/groups/{groupId}`
- User cleanup:
  - `GET /api/v1/users/{userId}/factors`
  - `DELETE /api/v1/users/{userId}/factors/{factorId}`
  - `DELETE /api/v1/users/{userId}/sessions?oauthTokens=true`
  - `POST /api/v1/users/{userId}/lifecycle/reset_password?sendEmail=true&revokeSessions=true`
- OAuth client or service app cleanup:
  - Verify the specific app credential/key endpoint before writing exact paths.
  - Verify client role assignment endpoints before writing exact paths.

Reference quality rules:

- Add a `## References` section to every edge doc.
- Prefer references that directly support the abuse or cleanup steps.
- Do not cite generic docs if a specific API operation page exists.
- If an event type is named, cite Okta event type docs or another official source.
- For hybrid/SaaS edges, include both Okta docs and the downstream system's official docs when possible.
- When appropriate, add relevant BloodHound Okta overview research references or tools below. Use these as additional sources for abuse information and operator tooling, not as replacements for official API documentation.

## BloodHound Okta Overview Research References

Use these when they directly support an edge's abuse path, cleanup, opsec, or detection discussion:

- Michael Grafnetter (SpecterOps): Discovering Unexpected Okta Attack Paths with BloodHound
- Adam Chester (SpecterOps): Okta for Red Teamers
- Adam Chester (SpecterOps): Identity Providers for RedTeamers
- Eli Guy (XM Cyber): Attack Techniques in Okta - Part 1 - A (Really) Deep Dive into Okta Key Terms
- Eli Guy (XM Cyber): Attack Techniques in Okta - Part 2 - Okta RBAC Attacks
- Eli Guy (XM Cyber): Attack Techniques in Okta - Part 3 - From Okta to AWS Environments
- AppOmni: Okta PassBleed Risks - A Technical Overview
- Luke Jennings (PushSecurity): Abusing Okta's SWA authentication
- David French (Elastic): Testing your Okta visibility and detection with Dorothy and Elastic Security

## BloodHound Okta Overview Research Tools

Use these to inform abuse steps, validation, and realistic operator workflows when relevant to the edge:

- Okta Post-Exploitation Toolkit
- Okta Terrify
- Dorothy
- SaaS Attacks
- Okta SCIM Attack Tool

When adding these to an edge doc's `## References`, use the exact page URL from the BloodHound Okta overview or the tool's repository URL after verifying it still resolves. Do not add every item to every edge; select the smallest relevant set.
