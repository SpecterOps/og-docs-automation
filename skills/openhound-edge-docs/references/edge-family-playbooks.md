# Edge Family Playbooks

## Admin And Role Edges

Examples: `Okta_SuperAdmin`, `Okta_OrgAdmin`, `Okta_AppAdmin`, `Okta_AddMember`, `GH_AddMember`, `GH_AdminTo`, `GH_CreateRepository`, `GH_WriteOrganizationActionsSecrets`, `jamf_AdminToTenant`, `jamf_AdminToSite`, `jamf_CreatePolicies`.

Required details:
- How to authenticate as the source: user, group/team member, service app, API client, installation, or token.
- Which destination object is managed.
- Console/UI path to the relevant object.
- API endpoint, CLI, or official API family.
- Verification: membership gone/present, assignment gone/present, token works/does not work, sessions revoked.
- Cleanup: undo exact admin action, restore legitimate state, revoke sessions/tokens, rotate exposed credentials.
- Opsec: role assignment changes, user/team/group membership, app assignment, repo/admin setting changes, MDM policy changes, lifecycle, session, and token events.

## Credential And Key Edges

Examples: `Okta_ApiTokenFor`, `Okta_SecretOf`, `Okta_KeyOf`, `Okta_ReadClientSecret`, `GH_HasPersonalAccessToken`, `GH_ValidToken`, `GH_HasSecret`, `GH_CanReadSecretScanningAlert`, `jamf_ApiClient` credential edges.

Required details:
- Distinguish graph knowledge from raw secret possession.
- Explain how the credential authenticates and what identity, installation, API client, or downstream principal it becomes.
- Include token minting/use path where appropriate.
- Cleanup: rotate/deactivate exposed secret/key/token, revoke minted tokens where possible, remove downstream changes.
- Opsec: token issuance, API calls, source IP/user agent anomalies, secret rotation/view events.

## Assignment, Provisioning, And Sync Edges

Examples: `Okta_AppAssignment`, `Okta_MemberOf`, `Okta_UserSync`, `Okta_MembershipSync`, `GH_HasRole`, `GH_MemberOf`, `GH_SyncedTo`, `GH_MapsToUser`, Jamf account/group/site scope edges.

Required details:
- Identify authoritative source and destination.
- Explain what must be changed in the source to affect the destination.
- Include trigger/wait for import, push, sync, SCIM provisioning, inventory update, or platform re-evaluation.
- Cleanup: restore source state, rerun/wait for sync, verify destination and downstream apps.
- Opsec: source-system changes, platform import/provisioning, group/team membership, profile, password, inventory, and downstream app logs.

## Federation And SWA Edges

Examples: `Okta_IdentityProviderFor`, `Okta_InboundSSO`, `Okta_OutboundSSO`, `Okta_SWA`, `Okta_KerberosSSO`, `GH_SyncedTo`, `GH_CanAssumeIdentity`, `jamf_SSO_Login`.

Required details:
- Specify whether trust is SAML, OIDC, SWA, Kerberos, SCIM, MDM SSO, cloud OIDC federation, or another mechanism.
- Explain subject/account linking and claim/group impact.
- Include how source control becomes destination session or role.
- Cleanup: restore claims, mappings, signing material, app assignments, credentials, sessions, JIT users, and downstream groups/roles.
- Opsec: IdP login, SSO app launch, claim/group changes, downstream federated login, Kerberos/DC logs, SWA password login logs.

## Scope, Container, And Metadata Edges

Examples: `Okta_Contains`, `Okta_RealmContains`, `Okta_HasRole`, `Okta_ScopedTo`, `GH_Contains`, `GH_Owns`, `GH_HasBranch`, `GH_HasEnvironment`, `GH_ProtectedBy`, `GH_HasWorkflow`, `jamf_Contains`, Jamf site or tenant scope edges.

Required details:
- Say clearly that the edge is not the direct exploit when true.
- Explain the adjacent control required and how source control affects the destination.
- Point to derived permission edges where appropriate.
- Cleanup: restore the concrete object or source-system change that was made.
- Opsec: configuration, workflow, role/scope, device, repository, site, access request, or source-system audit trail.

## Code, Workflow, And Automation Edges

Examples: `GH_WriteRepoContents`, `GH_CanWriteBranch`, `GH_CanCreateBranch`, `GH_CanEditProtection`, `GH_CanPwnRequest`, `GH_CallsWorkflow`, `GH_UsesSecret`, `GH_DeploysTo`, Jamf policy/script/computer extension creation or execution edges.

Required details:
- Explain the execution primitive: commit, branch push, workflow dispatch, reusable workflow call, deployment, MDM policy, script execution, or extension attribute.
- Identify gate conditions such as branch protection, workflow permissions, environment reviewers, secret scope, Jamf policy scope, computer check-in, or site scoping.
- Include the minimum code/config change needed and how to trigger execution.
- Cleanup: revert commits/branches/workflows, restore protections, remove policies/scripts/scopes, rotate exposed secrets, and verify no recurring automation remains.
- Opsec: Git commits, pull requests, workflow runs, deployment logs, audit logs, Jamf policy logs, MDM command logs, endpoint telemetry.

## Device, Endpoint, And MDM Edges

Examples: `Okta_DeviceOf`, `Okta_MobileAdmin`, Jamf computer management and policy edges.

Required details:
- Distinguish platform inventory/trust state from operating-system control.
- Explain how device or MDM control becomes local code execution, device trust, policy compliance, lock/wipe, configuration profile install, or data access.
- Include endpoint or MDM trigger requirements such as check-in, management framework health, user interaction, enrollment state, or supervision state.
- Cleanup: remove profiles/scripts/packages, restore device state, revoke sessions/tokens/certificates, and verify endpoint/Jamf/Okta inventory state.
- Opsec: platform audit logs, MDM command history, endpoint logs, EDR alerts, user-visible prompts or disruptions.

## Hybrid Agent Edges

Examples: `Okta_HostsAgent`, `Okta_AgentMemberOf`, `Okta_AgentPoolFor`.

Required details:
- Explain host compromise, agent registration/configuration, directory credentials, delegated auth/import/sync impact.
- Include AD/domain/source directory cleanup.
- Cleanup: remove tooling, restore service/config, rotate credentials, verify agent health and sync state.
- Opsec: endpoint logs, Windows logs, directory logs, Okta agent health, sync failures, delegated-auth anomalies.
