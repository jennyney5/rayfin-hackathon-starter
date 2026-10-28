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

## Starter prompt

Fill in the placeholders and paste into your agent.

````text
Read AGENTS.md and DEPENDENCIES.md, then build Scenario 1 from scenario-1-spreadsheet-to-app/README.md end to end.

Inputs:
- Tenant ID: <TENANT_ID>
- Fabric workspace name: <WORKSPACE_NAME> (on an active Fabric capacity; I am Admin or Member)
- Rayfin version: use the current 1.36.x and keep every @microsoft/rayfin-* package on the same version

Work in this order, and verify each step against the "Expected results" in the scenario README before moving on:
1. Use the Fabric skills to create the schema-enabled lakehouse northwind_lh, upload data/Northwind_Spend_Extract_FY2026.xlsx to Files/raw/, and create and run the notebook load_spend_workbook that loads the five tables into dbo. Validate row counts, total spend and column types on the SQL analytics endpoint (refresh its metadata if the tables are not visible yet).
2. Use the powerbi-authoring skill to author and deploy the Direct Lake semantic model "Northwind Spend Model" as TMDL: relationships, date table, hidden keys, 15 measures with format strings and descriptions, and the 3 RLS roles. Validate every measure with DAX through the executeQueries API.
3. Scaffold the Rayfin app: npm create @microsoft/rayfin@latest -- spend-diagnostic --template dataapp --workspace <WORKSPACE_NAME>. Read the generated AGENTS.md and .agents/skills. Add a fabric-semanticmodel connector named spendmodel with the literal workspace and model IDs, run the install command the CLI prints, and prove it returns rows with npx rayfin connector invoke.
4. Build the four pages described in the scenario README, with no mock data. Run the build, lint and tests, then deploy with npx rayfin up and capture the hostingUrl from npx rayfin up status --json.
5. Compare the deployed model's numbers with the expected results and report any difference. Tell me exactly what you verified and what you could not verify.

Stop and ask me only for interactive sign-ins (az login, npx rayfin login) or tenant settings I must enable.
````

## Expected results

Check these through DAX (Power BI `executeQueries`) and again through the connector (`npx rayfin connector invoke spendmodel executeQuery`).

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
| Deployment | `npx rayfin up status --json` shows `deployed: true` and a `hostingUrl` |

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
| Connector name mismatch (`client.connectors.spendmodel` untyped) | Use exactly `spendmodel` in `rayfin.yml`, the connector schema, and the client runtime map. |
| 401 or 403 from the CLI | Session expired. Run `npx rayfin login --tenant <TENANT_ID>` again. |

Row-level security applies to Viewers. Workspace Admins, Members and Contributors see all rows, so do not use your own account to test it.
