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
| Azure Functions Core Tools | v4 | **Scenario 2:** needed by `npx rayfin dev functions apply` to generate function types | `func --version` |
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

## 6. References

| Topic | Link |
|---|---|
| Skills for Fabric | https://learn.microsoft.com/en-us/fabric/fundamentals/skills-for-fabric-overview |
| Fabric Apps overview | https://learn.microsoft.com/en-us/fabric/apps/overview |
| Fabric Apps CLI reference | https://learn.microsoft.com/en-us/fabric/apps/cli-reference |
| Fabric Apps troubleshooting | https://learn.microsoft.com/en-us/fabric/apps/troubleshooting |
| Rayfin docs | https://rayfin.ai/docs |
| Rayfin repo and plug-ins | https://github.com/microsoft/rayfin |
| Fabric REST API | https://learn.microsoft.com/en-us/rest/api/fabric/articles/ |
