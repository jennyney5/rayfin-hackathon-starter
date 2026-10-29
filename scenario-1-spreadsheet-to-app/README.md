# Scenario 1 - Spreadsheet to App

Turn a client Excel extract into a deployed, governed Fabric app.

**Chain:** Excel workbook → OneLake lakehouse `northwind_lh` (5 Delta tables) → Direct Lake semantic model `Northwind Spend Model` (15 measures) → Rayfin Data App `spend-diagnostic` (4 pages) → deployed App item.

Before you start, read [../DEPENDENCIES.md](../DEPENDENCIES.md) and [../AGENTS.md](../AGENTS.md).

## Source data

[`../data/Northwind_Spend_Extract_FY2026.xlsx`](../data/Northwind_Spend_Extract_FY2026.xlsx) - accounts-payable spend for fictional Northwind Industrial Group, FY2026. The `README` sheet has the data dictionary and data-quality notes.

| Sheet | Rows | Content |
|---|---|---|
| `Spend_Lines` | 18,438 | One row per invoice line: date, business unit, site, supplier, category L1/L2, PO number and flag, payment terms, amount (USD) |
| `Suppliers` | 606 | Country, primary category, tier (Strategic / Preferred / Approved / Tail), contract status, diverse-supplier flag |
| `Categories` | 25 | Taxonomy, addressability, illustrative savings range (low and high %), primary lever |
| `Business_Units` | 4 | Region, FY2026 revenue ($M), business-unit lead and email |
| `Calendar` | 365 | One row per day of 2026 |

Gotchas called out in the workbook: read `po_number` as text (digit-only values become floats otherwise), join suppliers on `supplier_id` (names repeat across countries), and about 2% of spend is in an `Unmapped` category.

## What you build

1. **Lakehouse** `northwind_lh`, **schema-enabled**, with the workbook uploaded to `Files/raw/` and a notebook `load_spend_workbook` that writes five Delta tables to the `dbo` schema: `spend_lines`, `suppliers`, `categories`, `business_units`, `calendar`. IDs are strings, dates are `date`, and reruns are safe (overwrite).
2. **Semantic model** `Northwind Spend Model`, Direct Lake over `northwind_lh` (all five tables, partitions with `schemaName: dbo`):
   - Many-to-one, single-direction relationships from `spend_lines` to `suppliers[supplier_id]`, `categories[category_l2]`, `business_units[business_unit]` and `calendar[date]` (on `invoice_date`).
   - `calendar` marked as the date table; `calendar[month_name]` sorted by `month_number`; `spend_lines[supplier_id]`, `po_number` and `invoice_line_id` hidden.
   - **15 measures** on `spend_lines`, each with a format string and a description (the app agent reads descriptions before writing DAX). See the table below.
   - 3 row-level-security roles with read permission: `Aerospace only` (`business_units[business_unit] = "Aerospace Components"`), `BU lead (dynamic)` (`business_units[bu_lead_email] = USERPRINCIPALNAME()`), and `Engagement team` (no filter).
3. **Rayfin Data App** `spend-diagnostic` from the `dataapp` template, using a `fabric-semanticmodel` connector named `spendmodel`, deployed with `npx rayfin up`.

### Measures

| Measure | Meaning | Format |
|---|---|---|
| Total Spend | Sum of `invoice_amount_usd` | `$#,0.0,,"M"` |
| Addressable Spend | Total Spend for categories marked addressable | `$#,0.0,,"M"` |
| Addressable % | Addressable Spend / Total Spend | `0.0%` |
| Savings Opportunity Low | Spend × each category's low savings % | `$#,0.0,,"M"` |
| Savings Opportunity Mid | Average of low and high | `$#,0.0,,"M"` |
| Savings Opportunity High | Spend × each category's high savings % | `$#,0.0,,"M"` |
| Supplier Count | Distinct suppliers with spend | `#,0` |
| Invoice Lines | Count of invoice lines | `#,0` |
| Non-PO Spend % | Share of spend with `po_flag = Non-PO` | `0.0%` |
| Tail Spend % | Share of spend with Tail-tier suppliers | `0.0%` |
| Contract Coverage % | Share of spend with suppliers under contract | `0.0%` |
| Unmapped Spend % | Share of spend in the `Unmapped` category | `0.0%` |
| Top 10 Supplier Share % | Share of spend with the 10 largest suppliers | `0.0%` |
| Weighted Payment Terms (days) | Payment terms weighted by invoice amount | `0.0` |
| Spend % of Revenue | Total Spend / business-unit revenue | `0.0%` |

### App pages

1. **Executive overview** - KPI cards, spend by business unit, spend by month (`calendar[year_month]`), and a three-bullet "So what" panel computed from the query results (no LLM).
2. **Category deep-dive** - top 15 `category_l2` coloured by `category_l1`, business unit × `category_l1` heatmap, savings range by `category_l1`.
3. **Supplier concentration** - Pareto of the top 50 suppliers, spend by supplier tier, top-25 supplier grid.
4. **Opportunity** - waterfall from Addressable Spend to Mid savings by `primary_lever`, and a category table that flags fragmentation (more than 40 suppliers).

Design: white surfaces, navy headers `#0E1E3D`, one accent `#0078D4`, $M and % with one decimal, loading, empty and error states on every visual, readable at 1366 px. Label savings as **illustrative benchmarks**.


## Let's get started

Start with one sign-in: the Azure CLI. It is interactive (it opens a browser), so your coding agent can't do it for you.

**Why `az login`?** The agent does the Fabric work for you through APIs rather than the portal: it creates the lakehouse, uploads the workbook, runs the notebook, deploys the semantic model and runs DAX checks. Every one of those calls needs an Entra token for *you*, and the Azure CLI is where the agent gets it. Signing in means it acts with your permissions in your workspace, and nothing more. No credentials are pasted into the agent or stored in the repo.

```
az login --tenant <tenantID>
```

Optional check: `az account get-access-token --resource https://api.fabric.microsoft.com` confirms you can get a Fabric token. If it fails with `AADSTS500014`, Fabric is disabled for that tenant: use the correct tenant or ask a Fabric admin. The agent runs the same check itself, so you can skip this.

Then paste the prompt below into your agent. Later, when it reaches the app step, the agent will ask you to sign in to the Rayfin CLI as well. That sign-in is separate, and you only need it then.

## Starter prompt

Fill in the placeholders and paste into your agent.

````text
I am a procurement consultant. A client sent me an Excel workbook, a fiscal-year accounts-payable extract for Northwind Industrial Group (synthetic): Spend_Lines (18,438 invoice lines), Suppliers, Categories, Business_Units and Calendar sheets, plus a README sheet with the data dictionary. I need to turn it into a governed Fabric app my engagement team can use to find savings. Build all of it, end to end, on Microsoft Fabric. Use the workbook as the only business-data source; consult the installed skills and generated template guidance for implementation.

Inputs:
- Workbook path: <PATH_TO_Northwind_Spend_Extract_FY2026.xlsx>
- Alias: <ALIAS> (my short lowercase alias, for example memasanz; the workspace is shared with other people)
- Tenant ID: <TENANT_ID>
- Fabric workspace name: <WORKSPACE_NAME> (on an active Fabric capacity; I am Admin or Member)

Rules:
- Before doing anything, check the Inputs. If Alias is still the literal text <ALIAS> (or empty), stop and ask me for a short lowercase alias (letters and numbers only, for example memasanz) and do not create anything until I give one. Do the same for any other input that is still a <PLACEHOLDER>.
- The workspace is shared. Suffix the name of every item you create with my alias so nothing collides with other people's work: lakehouse northwind_lh_<ALIAS>, notebook load_spend_workbook_<ALIAS>, semantic model "Northwind Spend Model - <ALIAS>", Rayfin app spend-diagnostic-<ALIAS>. Never modify, overwrite or delete items that do not carry my alias, and list items before creating them to avoid duplicates.
- Create the lakehouse schema-enabled, with tables in the dbo schema and semantic-model partitions set to schemaName: dbo. The SQL analytics endpoint can lag behind new tables: refresh its metadata and retry.
- Build the Direct Lake model over OneLake as TMDL in one pass, then deploy once.
- Follow the generated template's AGENTS.md and relevant .agents/skills/ files for version-specific CLI commands, dependencies, connector registration, schema discovery, query validation, app code and deployment. For app work, follow the generated AGENTS.md when it specializes general skill guidance. This prompt defines required outcomes and safeguards, not replacement implementation mechanics.
- Read the workbook's README and analyze its sheets before scaffolding the app. Complete and validate Fabric ingestion and the semantic model before scaffolding as well. This scenario-specific data-first order overrides generic scaffold-first guidance.
- Keep staticHosting.assetAccess: protected and the template's Fabric sign-in flow. Never commit rayfin/.env, rayfin/.deployments.json, .env.local or any secret. Never use npx rayfin up --force without asking me.
- Read the Fabric skills before touching Fabric, and the generated AGENTS.md and .agents/skills before writing app code.
- Reconcile every number against the source workbook itself (compute totals and counts directly from it), not against remembered values.

Work in this order and verify each step before moving on:
1. Use the Fabric skills to create the schema-enabled lakehouse northwind_lh_<ALIAS>, upload the workbook to Files/raw/, and create and run the notebook load_spend_workbook_<ALIAS> that loads the five data sheets into dbo as spend_lines, suppliers, categories, business_units and calendar. Read the workbook's README sheet first. Keep IDs and po_number as text (digit-only PO numbers turn into floats otherwise), join suppliers on supplier_id (supplier names repeat across countries), and note that about 2% of spend sits in an Unmapped category. Validate row counts, total spend and column types on the SQL analytics endpoint.
2. Use the powerbi-authoring skill to author and deploy the Direct Lake semantic model "Northwind Spend Model - <ALIAS>" as TMDL: relationships, date table, hidden keys, 15 measures with format strings and descriptions, and the 3 RLS roles. Validate every measure with DAX through the executeQueries API.
   - Direct Lake over northwind_lh_<ALIAS>, all five tables, with partitions set to `schemaName: dbo`.
   - Many-to-one, single-direction relationships from spend_lines to suppliers[supplier_id], categories[category_l2], business_units[business_unit] and calendar[date] (on invoice_date).
   - calendar marked as the date table; calendar[month_name] sorted by month_number; spend_lines[supplier_id], po_number and invoice_line_id hidden.
   - 15 measures on spend_lines, each with a format string and a description (the app agent reads descriptions before writing DAX):
     - Total Spend: sum of invoice_amount_usd, `$#,0.0,,"M"`
     - Addressable Spend: Total Spend for categories marked addressable, `$#,0.0,,"M"`
     - Addressable %: Addressable Spend / Total Spend, `0.0%`
     - Savings Opportunity Low / Mid / High: spend times each category's low / average of low and high / high savings %, `$#,0.0,,"M"`. Iterate the categories table itself, for example SUMX(categories, [Total Spend] * categories[savings_low_pct] / 100); MAX of a category column inside an iterator ignores the current category and overstates savings.
     - Supplier Count: distinct suppliers with spend, `#,0`
     - Invoice Lines: count of invoice lines, `#,0`
     - Non-PO Spend %: share of spend with po_flag = Non-PO, `0.0%`
     - Tail Spend %: share of spend with Tail-tier suppliers, `0.0%`
     - Contract Coverage %: share of spend with suppliers under contract, `0.0%`
     - Unmapped Spend %: share of spend in the Unmapped category, `0.0%`
     - Top 10 Supplier Share %: share of spend with the 10 largest suppliers, `0.0%`
     - Weighted Payment Terms (days): payment terms weighted by invoice amount, `0.0`
     - Spend % of Revenue: Total Spend / business-unit revenue, `0.0%`
   - 3 row-level-security roles with read permission: `Aerospace only` (`business_units[business_unit] = "Aerospace Components"`), `BU lead (dynamic)` (`business_units[bu_lead_email] = USERPRINCIPALNAME()`) and `Engagement team` (no filter).
3. Scaffold the Rayfin app spend-diagnostic-<ALIAS> from the dataapp template in <WORKSPACE_NAME>. Immediately read its generated AGENTS.md and relevant .agents/skills/ files and follow them for setup. Register a fabric-semanticmodel connector named spendmodel for the validated model. Use the template-prescribed tools to prove live connectivity, discover the model schema and measure descriptions, and validate every final app query before writing UI code.
4. Build four pages, all driven by live queries to the model, with no mock or hard-coded numbers:
   - Executive overview: KPI cards, spend by business unit, spend by month, and a three-bullet "So what" panel computed from the query results (no LLM).
   - Category deep-dive: top 15 categories by spend coloured by their parent category, a business unit by parent-category heatmap, and the savings range by parent category.
   - Supplier concentration: a Pareto of the top 50 suppliers, spend by supplier tier, and a top-25 supplier grid.
   - Opportunity: a waterfall from Addressable Spend down to Mid savings by primary lever, and a category table that flags fragmentation (more than 40 suppliers).
   Design: white surfaces, navy headers #0E1E3D, one accent #0078D4, $M and % to one decimal, loading, empty and error states on every visual (errors show category, message and request ID), readable at 1366 px. Label every savings figure as an illustrative benchmark.
   Run the template-prescribed build, lint and tests, then deploy and capture the hostingUrl from deployment status.
5. Run DAX through the executeQueries API and the template-prescribed connector query tools to confirm the deployed model matches the source workbook, and report any difference. Tell me exactly what you verified (with the numbers) and what you could not verify.

Stop and ask me only for interactive sign-ins (az login, npx rayfin login) or tenant settings I must enable.
````

## Expected results

Check these through DAX (Power BI `executeQueries`) and again through the connector using the generated template's prescribed query-validation tools.

| Check | Expected |
|---|---|
| Table rows | `spend_lines` 18,438 · `suppliers` 606 · `categories` 25 · `business_units` 4 · `calendar` 365 |
| Column types (SQL endpoint) | `invoice_date` and `date` = date; `invoice_line_id`, `supplier_id`, `po_number` = varchar |
| Total Spend | 1,531,439,208.96 ($1,531.4M) |
| Addressable Spend / % | 1,432,118,289.81 / 93.5% |
| Savings Low / Mid / High | 80,183,266.14 / 118,945,745.12 / 157,708,224.10 |
| Suppliers / Invoice lines | 606 / 18,438 |
| Non-PO % / Contract coverage % / Top-10 share | 23.4% / 64.2% / 13.8% |
| Tail % / Unmapped % / Spend % of revenue | 12.4% / 2.1% / 35.5% |
| Weighted payment terms | 48.1 days |
| Spend by business unit | Aerospace Components 556,899,578.47 (6,360 lines) · Industrial Automation 396,744,251.72 · Energy Systems 337,570,198.13 · Building Technologies 240,225,180.64 |
| Top L1 categories | Components $482.5M, Raw Materials $365.5M |
| Fragmentation flag | Fasteners & C-Parts: 62 suppliers, $56.6M |
| Deployment | Deployment status confirms success and provides a `hostingUrl` |

Open the `hostingUrl` (or the App item in the Fabric portal) in a browser and sign in to see the four pages.

## Tips if your agent gets stuck

| Symptom | Likely cause and fix |
|---|---|
| New tables missing on the SQL endpoint | Metadata sync lag. Refresh the SQL endpoint metadata, or wait and retry. |
| Semantic model refresh fails: "source tables do not exist or access was denied" | Partition `schemaName` does not match the lakehouse. Schema-enabled lakehouse: `schemaName: dbo`. |
| Savings measures return about 183.8M instead of 80.2M | `MAX` of a category column inside an iterator ignores the current category. Iterate the `categories` table itself, for example `SUMX(categories, [Total Spend] * categories[savings_low_pct] / 100)`. |
| `po_number` becomes a float | Read it as text when loading the workbook. |
| `error.category: api` from the connector | Execute Queries API tenant setting is off, or you lack Read and Build on the model. |
| Visuals are empty under `npm run dev` | Connectors do not run in dev. Deploy with `npx rayfin up`. |
| `error.category: query` | Wrong table, column or measure name. Re-read the model metadata. |
| Connector name mismatch (`client.connectors.spendmodel` untyped) | Follow the generated template's registration workflow for the exact name `spendmodel`; do not hand-edit generated connector wiring. |
| 401 or 403 from the CLI | Follow the generated guidance to check login status and workspace/model permissions; reauthenticate only when needed. |

Row-level security applies to Viewers. Workspace Admins, Members and Contributors see all rows, so do not use your own account to test it.
