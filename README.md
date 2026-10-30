# Rayfin / Fabric Apps Hackathon Starter

Two core scenarios and a follow-on scenario for building governed Microsoft Fabric apps with a coding agent and **Rayfin**. Each scenario gives you a goal, a ready-to-paste prompt for your agent, and checks to verify your result.

All data is **synthetic**. Northwind Industrial Group is a fictional company.

| Scenario | You start with | You finish with |
|---|---|---|
| [1 - Spreadsheet to App](scenario-1-spreadsheet-to-app/README.md) | `Northwind_Spend_Extract_FY2026.xlsx` (18,438 AP invoice lines) | Excel in a OneLake lakehouse, a Direct Lake semantic model with 15 measures, and a deployed 4-page Rayfin Data App `spend-diagnostic` |
| [1b - Foundry Spend Copilot](scenario-1b-foundry-copilot/README.md) | The completed Scenario 1 app | The same app with a chat panel, a Rayfin Function bridge, and a Foundry agent that explains the current dashboard view |
| [2 - Planning App with Write-back](scenario-2-planning-writeback/README.md) | `Northwind_Savings_Plan_Seed.xlsx` (24 savings initiatives, 63 phasing rows) | A deployed 5-page Rayfin app `savings-planner` with governed entities, server-side functions and immutable plan versions |

## Repository contents

```
.
├── README.md                          this file
├── DEPENDENCIES.md                    what to install and enable before you start
├── AGENTS.md                          rules your coding agent should load first
├── data/
│   ├── Northwind_Spend_Extract_FY2026.xlsx   Scenario 1 source workbook
│   └── Northwind_Savings_Plan_Seed.xlsx      Scenario 2 source workbook
├── scenario-1-spreadsheet-to-app/README.md   goal, prompt, expected results
├── scenario-1b-foundry-copilot/README.md      follow-on agent and app chat panel
└── scenario-2-planning-writeback/README.md   goal, prompt, expected results
```

Each workbook has a `README` sheet with a data dictionary and known data-quality notes. Your agent should read it first.

## How to run

1. Complete [DEPENDENCIES.md](DEPENDENCIES.md) (tools, agent skills, tenant settings, Fabric capacity).
2. Clone this repository and open the folder in your coding agent (GitHub Copilot CLI, Claude Code or similar).
3. Open a scenario README, copy the prompt from the **Starter prompt** section, fill in the placeholders, and paste it into the agent.
4. Complete the sign-ins the agent asks for (`az login` and `npx rayfin login`). These are interactive, so the agent cannot do them for you.
5. Compare the result with the **Expected results** table in the scenario.

Scenario 1b starts where Scenario 1 ends and updates the existing app. Scenario 2 is independent of both; run it whenever you like.

## What you do versus what the agent does

The agent does the building: creating the workspace items, loading data, authoring the model, scaffolding and coding the app, deploying it, and checking numbers. You only need to:

- enable the tenant settings listed in DEPENDENCIES.md (needs a Fabric admin),
- complete `az login` and `npx rayfin login` when asked,
- open the deployed app in a browser and sign in to try it.

## Notes

- Fabric Apps and Rayfin are in public preview. These scenarios were validated with Rayfin 1.36.x.
- Deployed apps are created as App items in your workspace. Each team should use its own workspace.
