# Dependencies

Everything to set up before the hackathon. Fabric Apps and Rayfin are in **public preview**, so do a dry run in your event tenant first.

## 1. Local tools

| Tool | Version | Why | Verify |
|---|---|---|---|
| Node.js and npm | Node 20 or later | Rayfin CLI (`npx rayfin`), app build and tests. **Assumed already installed.** | `node -v`, `npm -v` |
| Git | current | Clone this repo | `git --version` |
| Azure CLI | current | Entra tokens for the Fabric, Power BI, OneLake and SQL endpoints | `az version` |
| Python | 3.10 or later | The agent uses it for small tasks such as reading the Excel files and calling REST APIs | `python --version` |
| go-sqlcmd | current | Optional: validation queries against the lakehouse SQL analytics endpoint | `sqlcmd --version` |
| Azure Functions Core Tools | v4 | **Scenarios 1b and 2:** needed by `npx rayfin dev functions apply` to generate function types | `func --version` |
| Playwright (Chromium) | per project | Optional: browser checks of the deployed app | `npx playwright --version` |

The Rayfin CLI and templates are fetched by `npx` and `npm create`; nothing to install globally. Your npm must be able to reach the public npm registry.

## 2. Coding agent and skills

Use **GitHub Copilot CLI** or **Claude Code** (or another agent that reads `AGENTS.md`).

### Skills for Fabric (required)

Install both plug-ins. `fabric-skills` covers lakehouse, notebooks, SQL endpoint, OneLake and REST. `powerbi-authoring` covers semantic-model authoring (TMDL, Direct Lake, DAX).

Run inside the agent:

```text
/plugin marketplace add microsoft/skills-for-fabric
/plugin install fabric-skills@fabric-collection
/plugin install powerbi-authoring@fabric-collection
/quit
```

Restart the agent and check with `/skills`. For agents without a plug-in system, clone https://github.com/microsoft/skills-for-fabric next to this repo. Install guide: https://learn.microsoft.com/en-us/fabric/fundamentals/skills-for-fabric-install

### Rayfin skills

Every scaffolded Rayfin project installs `AGENTS.md`, `.mcp.json` and `.agents/skills/` (Rayfin, connectors, functions, DAX, visuals). The agent must read them after scaffolding. Optional Rayfin plug-ins for common agents: https://github.com/microsoft/rayfin

## 3. Tenant and workspace

| Area | Requirement | Scenario 1 | Scenario 2 |
|---|---|---|---|
| Tenant setting | **Fabric Apps (preview)** enabled for the org or your hackathon security group. Allow a few minutes to propagate. | Yes | Yes |
| Tenant setting | **Semantic model Execute Queries REST API** enabled | Yes | No |
| Fabric capacity | An **active** capacity (F2 or larger, or trial). The app, functions and semantic model all run on it. | Yes | Yes |
| Workspace | One per team on that capacity. You need **Admin** or **Member**. | Yes | Yes |
| Region | Functions must be available in the capacity region. A West US capacity worked in validation. | No | Yes |
| Lakehouse | Create lakehouses **schema-enabled** (tables in `dbo`). | Yes | No |

A tenant setting is confirmed working when the first dependent call succeeds (creating the App item, or running a DAX query through the API).

## 4. Sign-in

```bash
az login --tenant <TENANT_ID>
az account get-access-token --resource https://api.fabric.microsoft.com    # must succeed
npx rayfin login --tenant <TENANT_ID>                                      # opens a browser; you complete it
npx rayfin login status
```

Rayfin sessions expire after a few hours. If a deploy returns 401 or 403, sign in again.

## 5. Rayfin version

All `@microsoft/rayfin-*` packages share one version number, and the scenarios were validated with **1.36.x**. After scaffolding, run `npx rayfin --version` and keep every `@microsoft/rayfin-*` package on that same version.

## 6. Scenario 1b additions

Complete Scenario 1 first. Scenario 1b reuses its Fabric workspace, app, connector and semantic model; it does not reload the workbook or create another app.

### Install Foundry Dev Pack before the session

**Required for Scenario 1b:** install [Foundry Dev Pack](https://devblogs.microsoft.com/foundry/foundry-devpack-announcement/) on each participant's machine before starting the scenario. It sets up the Foundry CLI tools and coding-agent skill, plus editor integrations when the corresponding host apps are present.

Windows (PowerShell):

```powershell
winget install Microsoft.FoundryDevPack
```

macOS:

```bash
brew install --cask microsoft/foundry/devpack && foundry-devpack install
```

Linux:

```bash
curl -fsSL https://aka.ms/foundry-devpack-install.sh | bash
```

Open a new terminal and restart your coding agent after installation. Verify `az version`, `azd version` and `azd ext list`; the extensions list must include `microsoft.foundry`. Confirm that the `microsoft-foundry` skill is available in your coding agent. On managed devices, complete any required installation approvals before the hackathon.

Dev Pack does not install VS Code or GitHub Copilot App, grant Azure permissions, provision a Foundry project/model, or replace the separate Azure Functions Core Tools prerequisite above. See the [official setup guide](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/install-cli-sdk).

### Cloud access and runtime prerequisites

- Functions must be available in the existing capacity region. Foundry inference runs in Azure and is billed separately from Fabric capacity.
- Supply an Azure subscription, resource group and a Microsoft Foundry project with a supported model deployment and available quota. If the project or model does not exist, agree on region and cost before the agent provisions it.
- The builder needs permission to create/version a Foundry agent. For the original maker-identity variant, the deployed Fabric app identity needs permission to invoke the chosen agent API. For Option 2, each participating user needs that access. Someone with role-assignment rights must grant access if the builder cannot.
- The Fabric Functions runtime must be able to reach the Foundry endpoint. A developer's local connectivity does not prove runtime connectivity, especially for private endpoints.
- Use the installed `microsoft-foundry` skill (or equivalent current official Foundry guidance) alongside the generated Rayfin functions skill. Read the project's `functions/connections/add-foundry.md` guide before implementing the bridge.
- For the maker-identity variant, verify that the deployed `AudienceType.AzureAI` token is accepted by the selected Foundry API. Option 2 instead forwards the user's separate MSAL Foundry token; it must not fall back to the app-owner token. Neither an audience declaration nor OAuth consent grants resource access.

### Option 2 organizer prerequisites

These additions apply to the **per-user MSAL variant**, not the original maker-identity starter prompt.

**Before the event:**

- Create **one organizer-managed, single-tenant SPA registration for the event**, shared by groups using the same tenant and delegated permission set. Configure delegated Foundry access (`https://ai.azure.com/user_impersonation`) and supply its public client ID and tenant ID. No client secret is needed; participants do not create registrations.
- Arrange required consent before the session. Organizer-granted admin consent can simplify onboarding, but is mandatory only when the permission or tenant policy requires it. Each user still needs appropriate Foundry and Fabric resource permissions.
- For the [independent Fabric IQ variant](scenario-1b-foundry-copilot/README.md#option-2-starter-prompt), approve each group's agent/connection names and user-delegation setup for its existing semantic model. Confirm the connection's downstream permissions and consent separately from the SPA's Foundry permission; sharing a Foundry project must not cause groups to overwrite one another's agents or connections.
- Keep registration-edit permissions with the organizer. All approved callbacks are trusted endpoints for the same OAuth client; the shared registration is **not a group-security boundary**. Use separate registrations when groups need different permissions or independent consent/revocation, or separate tenant setups when they use different tenants.

#### Admin-run SPA setup (PowerShell)

Use [`scripts\Set-HackathonSpaRegistration.ps1`](scripts/Set-HackathonSpaRegistration.ps1)
with Azure CLI installed and an organizer account authorized to manage Entra applications
(for example, an activated **Cloud Application Administrator** role). Tenant-wide consent
also requires an appropriate consent-capable Entra role and tenant policy; a subscription
Owner role alone is not sufficient. No Microsoft Graph PowerShell module is needed.

This creates the **Entra app registration and service principal (Enterprise application)**,
not an Azure App Service hosting resource. The SPA remains hosted by Fabric. It uses
single-tenant authorization code with PKCE, configures only delegated Foundry
`user_impersonation`, and creates no secret or certificate. API and scope IDs are discovered
from the tenant's Foundry API service principal, not guessed. If that API is unavailable,
the script stops before creating the registration.

Before the event, replace the placeholders and run from the repository root:

```powershell
az login --tenant "<TENANT_ID>" --allow-no-subscriptions
.\scripts\Set-HackathonSpaRegistration.ps1 `
    -TenantId "<TENANT_ID>" `
    -DisplayName "<EVENT_SPA_NAME>" `
    -GrantAdminConsent
```

`-GrantAdminConsent` explicitly grants Foundry delegated access on behalf of all tenant
users; omit it when user consent is permitted and tenant-wide consent is not desired.
The script reads back the registration, service principal and any requested admin consent.
Save the returned **ClientId** and **TenantId** and distribute those public IDs only.
It does not grant Foundry roles, Fabric permissions or downstream Fabric IQ consent.
No callback is invented during initial creation.

After a group's app is deployed, an admin can use
[`scripts\Add-HackathonSpaCallback.ps1`](scripts/Add-HackathonSpaCallback.ps1)
to add its callback. Supply the **actual Fabric app hosting endpoint**, not the
Fabric portal item URL or REST API endpoint, and the saved SPA client ID:

```powershell
az login --tenant "<TENANT_ID>" --allow-no-subscriptions
.\scripts\Add-HackathonSpaCallback.ps1 `
    -TenantId "<TENANT_ID>" `
    -ClientId "<EVENT_SPA_CLIENT_ID>" `
    -FabricEndpoint "https://<ACTUAL_DEPLOYED_APP_HOST>/"
```

The callback script derives the HTTPS origin with a trailing `/`, even if the supplied
hosting endpoint includes a path. It appends that root as a **SPA redirect URI** and
verifies it by reading back Entra. Portal/API URLs, wildcards, credentials, queries
and fragments are rejected. It creates no new registration and grants no admin consent.

For batch updates, the setup script's `-ClientId` and `-RedirectUri` parameters
accept an array of approved hosting roots. Both scripts preserve existing SPA
callbacks and API permissions; repeated runs do not duplicate them. Run callback updates
serially to avoid concurrent read/modify/write conflicts. Duplicate display names are
rejected during creation: reuse the explicit `-ClientId`, including after a partially
completed run. No permissions are automatically rolled back on failure; inspect the
reported error and registration before rerunning.

**After each group's Scenario 1 app is deployed, before its first Foundry sign-in:**

- Use an organizer-controlled registration step to append the group's actual HTTPS hosting root as a **SPA redirect URI**, preserving the other groups' callbacks. For example, `https://<group-app-host>/` is a placeholder: use the real deployed origin, never a guessed URL or wildcard.
- Do **not** register the Fabric portal/developer-experience URL or the app's `/auth/relay.html` helper as OAuth redirect URIs. The app root must handle the authentication response before starting the dashboard or Fabric sign-in.
- Dry-run the chosen MSAL flow in the actual Fabric developer portal. The embedded popup-relay flow requires **Continue sign-in** in the first popup, followed by Microsoft sign-in in the second. For cancellation, close the old sign-in windows and wait for cleanup before reconnecting. Verify connection and a real agent response, not just popup closure.

Review callback additions and remove unused event callbacks after the hackathon. See
[Option 2 authentication and organizer setup](scenario-1b-foundry-copilot/AUTHENTICATION-OPTIONS.md#hackathon-prerequisite-organizer-managed-spa-registration)
for the identity boundaries.

See [Scenario 1b](scenario-1b-foundry-copilot/README.md) for the required inputs, data boundary and acceptance checks.

## 7. References

| Topic | Link |
|---|---|
| Skills for Fabric | https://learn.microsoft.com/en-us/fabric/fundamentals/skills-for-fabric-overview |
| Fabric Apps overview | https://learn.microsoft.com/en-us/fabric/apps/overview |
| Fabric Apps CLI reference | https://learn.microsoft.com/en-us/fabric/apps/cli-reference |
| Fabric Apps troubleshooting | https://learn.microsoft.com/en-us/fabric/apps/troubleshooting |
| Rayfin docs | https://rayfin.ai/docs |
| Rayfin repo and plug-ins | https://github.com/microsoft/rayfin |
| Foundry Agent Service | https://learn.microsoft.com/en-us/azure/foundry/agents/overview |
| Foundry agent endpoint authorization | https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-endpoint-authorization |
| Fabric REST API | https://learn.microsoft.com/en-us/rest/api/fabric/articles/ |
