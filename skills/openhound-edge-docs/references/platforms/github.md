# GitHub Platform Profile

Use this profile for `GH_` edge docs and OpenHound GitHub repositories.

## Quality Bar

GitHub edge docs must distinguish raw permissions from effective abuse. Many `GH_` edges are non-traversable role-permission or metadata edges that only become abusable when combined with role assignment, branch protection, workflow, secret, token, or SSO edges.

API examples should:

- Start with `GITHUB_TOKEN`, `GITHUB_API`, `OWNER`, `REPO`, org/team/user IDs, branch names, and controlled values.
- Use `Authorization: Bearer $GITHUB_TOKEN`.
- Use `Accept: application/vnd.github+json`.
- Use `X-GitHub-Api-Version: 2022-11-28` unless official docs require a different version.
- Include expected success signals such as `204 No Content`, returned JSON fields, changed branch protection, new membership state, workflow run ID, or absent secret/permission.

## Preferred Sources

1. GitHub REST API docs on `docs.github.com/rest`.
2. GitHub GraphQL API docs on `docs.github.com/graphql`.
3. GitHub Enterprise Cloud admin and security docs on `docs.github.com`.
4. GitHub audit log and Actions/security docs on `docs.github.com`.
5. BloodHound GitHub overview, schema, computed edges, and mitigating-controls docs for graph semantics and tested attack-path logic.

## Common Headers

```bash
export GITHUB_API="https://api.github.com"
export GITHUB_TOKEN="REDACTED"
export OWNER="contoso"
export REPO="app"

curl -sS \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$GITHUB_API/repos/$OWNER/$REPO"
```

## Edge-Specific Guidance

- Role and permission edges such as `GH_AdminTo`, `GH_WriteRepoContents`, `GH_AddCollaborator`, `GH_CreateRepository`, or `GH_ManageWebhooks`: explain which org/repo role grants the permission, what principal holds the role through `GH_HasRole`, and the exact REST/GraphQL action.
- Team edges such as `GH_AddMember` and `GH_MemberOf`: explain team maintainer/parent-team inheritance and verify with team membership APIs.
- Branch protection edges such as `GH_CanWriteBranch`, `GH_CanCreateBranch`, `GH_CanEditProtection`, `GH_BypassBranchProtection`, `GH_ProtectedBy`, and allowance edges: explain the two-gate model, `enforce_admins`, push restrictions, pull-request requirements, bypass allowances, and whether the edge is computed.
- Actions and workflow edges such as `GH_CanPwnRequest`, `GH_CallsWorkflow`, `GH_DeploysTo`, `GH_UsesSecret`, and `GH_UsesVariable`: explain how a commit, pull request, workflow dispatch, reusable workflow call, or environment deployment exposes code execution or secrets.
- Secret and token edges such as `GH_HasSecret`, `GH_CanReadSecretScanningAlert`, `GH_ValidToken`, and `GH_HasPersonalAccessToken`: distinguish "can reference/read metadata" from raw secret possession. Include token revocation/rotation cleanup.
- Identity edges such as `GH_SyncedTo`, `GH_MapsToUser`, `GH_HasSamlIdentityProvider`, and `GH_CanAssumeIdentity`: explain SAML/SCIM mapping, account linking, OIDC subject/audience trust, and downstream cloud role assumptions.

## Cleanup Themes

- Remove temporary team membership, collaborator access, deploy keys, webhooks, variables, secrets, branch protection changes, workflow files, environment reviewers, and app installations.
- Revert commits and delete branches created for the path when appropriate.
- Restore original branch protection and environment protection JSON.
- Rotate GitHub Actions secrets and downstream cloud credentials exposed to workflows.
- Revoke PATs, GitHub App installation tokens where possible, and downstream sessions/tokens.
- Verify with GitHub REST/GraphQL APIs and audit log entries.

## Opsec Sources

Use GitHub enterprise/org audit logs, repository events, branch protection history, workflow run logs, deployment logs, environment approval logs, secret scanning/Dependabot/code scanning audit trails, SAML/SCIM logs, and downstream cloud audit logs.

## Common References

- [GitHub REST API](https://docs.github.com/en/rest)
- [GitHub GraphQL API](https://docs.github.com/en/graphql)
- [GitHub REST API: Teams](https://docs.github.com/en/rest/teams)
- [GitHub REST API: Collaborators](https://docs.github.com/en/rest/collaborators)
- [GitHub REST API: Branches](https://docs.github.com/en/rest/branches)
- [GitHub REST API: Actions secrets](https://docs.github.com/en/rest/actions/secrets)
- [GitHub REST API: Actions workflows](https://docs.github.com/en/rest/actions/workflows)
- [GitHub audit log](https://docs.github.com/en/enterprise-cloud@latest/admin/monitoring-activity-in-your-enterprise/reviewing-audit-logs-for-your-enterprise)
- [BloodHound GitHub schema](https://bloodhound.specterops.io/opengraph/extensions/github/schema)
- [BloodHound GitHub computed edges](https://bloodhound.specterops.io/opengraph/extensions/github/computed-edges)
