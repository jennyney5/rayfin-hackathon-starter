# AGENTS.md - rules for the coding agent

Load this file before starting either scenario. The scenario README holds the goal and prompt.

## Working style

- You build; the human only handles interactive sign-ins and tenant settings. Do everything else through APIs, CLIs and files. Use the installed **Skills for Fabric** (`fabric-skills`, `powerbi-authoring`) for lakehouse, notebook, SQL endpoint, OneLake and semantic-model work, and the **Rayfin skills** in each scaffolded project (`.agents/skills/`, `AGENTS.md`) for app work. Read them before writing code.
- Verify as you go. After each phase, run a check (a query, a build, a CLI call) and compare it with the expected numbers in the scenario. Do not move on from a failed check. Fix the cause.
- State plainly what you verified and what you could not (for example a browser check that needs an interactive sign-in).

## Ask, don't invent

Ask the human for: tenant ID, workspace name, and anything else the scenario marks as an input. Never guess IDs, endpoints or credentials.

## Data and security

- Synthetic data only: load only the two workbooks in `data/`.
- No mock or hard-coded numbers in app code. If a query fails, show the error state with category, message and request ID.
- No data files in `src/` or `public/`. No tokens, keys or direct Power BI REST calls in front-end code.
- Keep `staticHosting.assetAccess: protected` and the template's Fabric sign-in flow.
- Never commit `rayfin/.env`, `rayfin/.deployments.json`, `.env.local` or any token or secret.
- Never use `--encryption-fallback-enabled` outside a dev container without an OS keychain. Never use `npx rayfin up --force` without explicit human approval.

## Fabric rules

- Create lakehouses **schema-enabled**. Tables live in the `dbo` schema, and semantic-model partitions set `schemaName: dbo`.
- The lakehouse SQL analytics endpoint can lag behind new tables. If they are not visible, refresh its metadata and retry.
- Build Direct Lake semantic models over OneLake as code (TMDL) in one pass, then deploy once.
- Validate measures with DAX (`executeQueries`) before building the app on them.

## Rayfin rules

- Run the CLI with `npx` from the project folder. All `@microsoft/rayfin-*` packages must share one version.
- After `connector add`, run the install command it prints, exactly as printed. Pass literal IDs (no `${VAR}`).
- Never hand-edit generated files (`schema.ts` for connectors, `rayfin/functions/src/types.ts`).
- Connectors do not run under `npm run dev`. Deploy with `npx rayfin up` before testing connector-backed screens.
- Long-running commands (`npm run dev`, `npx rayfin dev ...`) go in the background; wait for the ready line, check for errors, then stop them cleanly by process ID.
- Every entity needs an explicit permission decorator and a `max` on every `@text` and `@email` field. Use TC39 decorators only (never `experimentalDecorators`).
- Paginate every list with `.first(100).after(cursor).executePaginated()`.

## Identity facts

- Workspace Admins, Members and Contributors are not filtered by row-level security.
- In functions, `ctx.getDataClient()` runs as the caller, while `ctx.Tokens.<Audience>` is the **app identity** (the owner of the App item). A local run uses your own identity, so a local success does not prove the app identity has access.
