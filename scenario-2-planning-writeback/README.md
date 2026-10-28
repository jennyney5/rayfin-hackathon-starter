# Scenario 2 - Savings Initiative Planner (write-back and server-side functions)

Build and deploy a five-page Fabric app where category managers own savings initiatives, phase savings by quarter, and submit immutable plan versions. A server-side function validates and calculates every submission.

Before you start, read [../DEPENDENCIES.md](../DEPENDENCIES.md) and [../AGENTS.md](../AGENTS.md).

## Source data

[`../data/Northwind_Savings_Plan_Seed.xlsx`](../data/Northwind_Savings_Plan_Seed.xlsx). The `README` and `Assumptions` sheets define the planning rules.

| Sheet | Rows | Content |
|---|---|---|
| `Initiatives` | 24 | Code (NW-001 to NW-024), title, business unit, category, lever, owner, stage L0-L5, confidence, baseline spend, target savings %, one-time cost, start quarter |
| `Savings_Phasing` | 63 | Quarterly savings FY27-Q1 to FY28-Q4 for 21 initiatives × Base, Stretch and Conservative scenarios (L0 ideas have none) |
| `Benchmarks` | 22 | Savings range by category; `savings_high_pct` is the benchmark ceiling |
| `Category_Baseline` | 88 | FY2026 addressable spend by business unit and category |
| `Assumptions` | 9 | Discount rate, committed stages, owner-required stages, run-rate and scenario definitions |

Two records are deliberate test cases: **NW-017** is an L3 initiative with no owner, and **NW-021** targets 26% savings against a 20% benchmark ceiling.

## What you build

A Rayfin app `savings-planner` from the `blankapp` template, with auth (Fabric), data (`mssql`), static hosting and functions enabled.

### Five governed entities

Permissions live in the entity decorators, not in the UI.

| Entity | Read | Create | Update | Delete |
|---|---|---|---|---|
| Initiative | any signed-in user | any signed-in user, `createdBy = claims.sub` | owner (by email) or creator | nobody (use an archive flag) |
| SavingsPhasing | any signed-in user | creator (`createdBy = claims.sub`) | owner (by copied `ownerEmail`) or creator | nobody |
| InitiativeComment (Comment / Risk / Decision) | any signed-in user | author (`authorId = claims.sub`) | author | author |
| PlanVersion | any signed-in user | allowed | **nobody** | **nobody** |
| PlanVersionLine | any signed-in user | allowed | **nobody** | **nobody** |

`Initiative.initiativeCode` is unique. `SavingsPhasing` has a unique `phasingKey` so imports can upsert. Every `@text` and `@email` field has a `max`.

### Two server-side functions

| Function | Input | Output |
|---|---|---|
| `previewPlan` | `{ scenario }` | plan summary: findings, committed count, FY27 and FY28 savings, exit run-rate, one-time cost, NPV |
| `submitPlanVersion` | `{ scenario, versionLabel, notes, submittedBy, submittedByEmail }` | the same summary plus `status` (`submitted` or `rejected`) and `versionId` |

Rules (from the workbook's `Assumptions` sheet):

- **Committed** stages are L2-L5. Stages **L3-L5 require an owner**; a missing owner is an **error** (for example "NW-017 · L3+ initiative has no owner").
- **Exit run-rate** = FY28-Q4 savings × 4.
- **NPV** at 8% a year, end-of-quarter discounting (quarter *q* of 1-8 discounted by 1/(1.08)^(q/4)), over committed initiatives and **net of their one-time cost**.
- A **warning** (not an error) when an initiative's exit run-rate as a percentage of its baseline exceeds its benchmark ceiling (for example "NW-021 · Run-rate 26.0% of baseline exceeds benchmark ceiling 20%").
- `submitPlanVersion` is rejected, and saves nothing, if there is any error. Otherwise it writes an immutable `PlanVersion` and its `PlanVersionLine` snapshot.
- Calculation logic is a pure, unit-tested module. Totals are never computed in the browser.

### Five pages

1. **Import** - upload the workbook (user-supplied; nothing bundled in the app); progress bar; **idempotent** (skip existing initiative codes, still map IDs for phasing, upsert phasing by `phasingKey`).
2. **Initiative register** - paginated grid with filters; inline edit of stage, confidence, owner and target % with an optimistic update and rollback plus a friendly message on permission denial; new-initiative form.
3. **Initiative detail** - Base / Stretch / Conservative tabs with an editable quarterly grid, row total, exit run-rate, a "Copy Base to Stretch ×1.2" action, and a Comment / Risk / Decision thread.
4. **Plan summary** - scenario selector; **Validate** (`previewPlan`); **Submit to SteerCo** with label and notes (`submitPlanVersion`); errors in red and warnings in amber, linked to initiatives; KPI tiles that show function output only.
5. **Versions** - list of versions, compare two versions' totals and per-initiative deltas; no edit or delete controls.

Design: white surfaces, navy header `#0E1E3D`, accent `#0078D4`, loading, empty and error states, errors show category, message and request ID.

## Starter prompt

Fill in the placeholders and paste into your agent.

````text
Read AGENTS.md and DEPENDENCIES.md, then build Scenario 2 from scenario-2-planning-writeback/README.md end to end.

Inputs:
- Tenant ID: <TENANT_ID>
- Fabric workspace name: <WORKSPACE_NAME> (on an active Fabric capacity; I am Admin or Member)
- Rayfin version: use the current 1.36.x and keep every @microsoft/rayfin-* package on the same version

First read data/Northwind_Savings_Plan_Seed.xlsx, especially its README and Assumptions sheets; they define the rules. Then:
1. Scaffold the app: npm create @microsoft/rayfin@latest -- savings-planner --template blankapp --workspace <WORKSPACE_NAME>. Read the generated AGENTS.md and .agents/skills (rayfin, rayfin-functions) and follow them, including how they say to enable data and functions.
2. Build the five governed entities with the permission rules in the scenario README, and apply the schema.
3. Build the previewPlan and submitPlanVersion functions with a pure, unit-tested calculation module. Write Vitest tests that assert the expected results in the scenario README, and run typegen so types.ts is generated, never hand-edited.
4. Build the five pages. The Import page must upload the .xlsx in the browser and be idempotent. No mock data, and no submission totals computed in the browser.
5. Run build, lint and tests, then deploy with npx rayfin up and capture the hostingUrl from npx rayfin up status --json.
6. Verify the deployed backend as far as you can without a browser: import the seed (24 initiatives, 63 phasing rows) twice to prove idempotency, run previewPlan for Base, Stretch and Conservative, give NW-017 an owner, submit Base once as "SteerCo #1", and confirm that updating or deleting that PlanVersion is refused. Versions can never be deleted, so submit only once.
7. Compare with the expected results and report differences. Tell me exactly what you verified and what you could not (for example anything that needs an interactive browser sign-in).

Stop and ask me only for interactive sign-ins (az login, npx rayfin login) or tenant settings I must enable.
````

## Expected results

| Check | Expected |
|---|---|
| Import | 24 initiatives and 63 phasing rows; a second import creates nothing new |
| Validate Base, as imported | 1 error (NW-017, no owner) and 1 warning (NW-021); committed 15 of 21 phased initiatives |
| Validate Base after giving NW-017 an owner | 0 errors, 1 warning (NW-021) |
| Base totals | FY27 **$19,919,000** · FY28 **$34,463,200** · exit run-rate **$34,463,200** · one-time cost **$2,430,000** · NPV **$46,757,829.92** (±$0.01) |
| Validate Stretch | 5 warnings (NW-004, NW-017, NW-018, NW-019, NW-021); exit run-rate **$41,356,000** |
| Validate Conservative | no findings; exit run-rate **$25,847,200** |
| Submit Base as "SteerCo #1" (after the owner fix) | status `submitted`, run-rate $34,463,200, 21 snapshot lines |
| Submit Base as imported | status `rejected`, nothing saved |
| Immutability | updating or deleting a `PlanVersion` or `PlanVersionLine` is refused by the data layer |
| Deployment | `npx rayfin up status --json` shows `deployed: true` and a `hostingUrl` |

With NW-017 ownerless, the owner error also appears when validating Stretch and Conservative. Use **Validate**, not Submit, for repeat checks, because every submission is permanent history in the workspace.

Open the `hostingUrl` in a browser and sign in to try the UI: the register edits and the Plan summary flow.

## Tips if your agent gets stuck

These were hit while validating on Rayfin 1.36.x.

| Symptom | Likely cause and fix |
|---|---|
| Enabling functions creates a second project or the wrong layout | Follow `.agents/skills/rayfin-functions/SKILL.md` in the scaffolded project. In 1.36.x it enables data and functions with `npm run pack:add -- data-modeling --no-install`, then `-- functions --no-install`, then one `npm install --ignore-scripts`. Avoid `npx rayfin functions init` if the skill says so. |
| `types.ts` (function types) does not exist | It is generated by `npx rayfin dev functions apply`, which needs a deployed app and Azure Functions Core Tools (`func`). Install Core Tools, open a fresh shell so PATH updates, then rerun. A "Python worker not supported" warning is harmless. |
| Create fails with "fields referenced by the database policy are not present" | A create policy references a field the record did not send. NW-017 has no owner email, so the `SavingsPhasing` create rule uses `createdBy = claims.sub` only. |
| `Initiative.update` or `delete` fails with "argument `id` is required" | Update and delete need `{ id }`; filtering by `initiativeCode` does not work. |
| Relationship fields fail typing on create | Foreign-key fields are required in the record type. Create rows with `initiative: { id }`, and type the id fields as optional in your own record types. |
| Local function call returns HTTP 502 | The Functions host is not running locally. Start `npm run dev` with functions enabled. |
| A Node helper script hangs after finishing | Call `process.exit` when done. The client keeps the process alive. |
| 401 or 403 on deploy | Session expired. Run `npx rayfin login --tenant <TENANT_ID>` again. |

Known limitation to mention in your write-up: because `submitPlanVersion` writes as the caller, any signed-in user could also create a `PlanVersion` directly through the data API. A line-write failure part-way through a submission cannot be cleaned up, since versions are immutable.
