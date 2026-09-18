# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Hard rules

- **Never run any command that writes to, migrates, or modifies the real Supabase project**
  (schema changes, RLS policies, data writes, table creation, CLI `db push`, etc.) without explicit
  confirmation from Javier first — even if the implementation plan describes the change as already
  decided. Planning documents record intent; they are not standing authorization to execute against
  the live project.
- **Never commit, copy, or reproduce the contents of `_planning/` into any tracked file in this
  repo.** It stays local and gitignored — read it for context, don't quote it into committed code,
  docs, or comments.

## Current state

**Phases 0-5 are done and live** (model-identifier verification, schema, catalog discovery job,
completions sweep job, frontend scaffold + landing page, Models page + model detail page). Project
ref `huladiqsospiarkumujz` (`https://huladiqsospiarkumujz.supabase.co`). Next up is Phase 6
(Executions page). What's on disk / live, condensed to what's still load-bearing (full blow-by-blow
of each verification run lives in git history / conversation history, not repeated here):

- **Backend jobs** (`backend/nimtracker/`): `catalog_scraper.py` (daily catalog job,
  `run_catalog_job()`) and `completions_probe.py` (hourly sweep, `run_completions_sweep()`), both
  proven end-to-end against the live project. `db.py` holds all SQL, no business logic. **Both
  jobs' GitHub Actions workflows (`catalog-discovery.yml`, `completions-sweep.yml`) are committed
  and actually running on schedule against the live project** — daily catalog discovery at 03:17
  UTC, hourly completions sweep at :07 past the hour.
- **`db.get_connection()` validates the DSN's format before calling `psycopg.connect()`**, raising
  a clear error (never echoing any part of the actual value) instead of a cryptic
  `psycopg.ProgrammingError`. Added after a real CI failure traced to the GitHub Actions
  `SUPABASE_DB_URL` secret's value apparently being set to its own name — local runs never caught it
  because they go through `backend/.env`'s separately-set value, never cross-checked against the CI
  secret. See `backend/tests/test_db.py`.
- **`model.last_seen_working_at` / `delisted_at` / `delisted_reason` are now actually written** by
  `run_completions_sweep()` via `db.update_model_lifecycle()` — these columns existed in the schema
  since Phase 1 with a comment claiming the completions job "owns" them, but no code ever wrote them
  until Phase 5, found missing only because the Models table (the first real consumer of
  `last_seen_working_at`) came back empty against live data despite real recorded successes. On a
  fresh success: `last_seen_working_at` moves forward, `delisted_at`/`reason` clear back to null (a
  model that comes back working must stop reading as delisted). On an explicit `removed`-category
  failure (404/410): `delisted_at`/`reason` are set immediately. Any other failure category touches
  neither field — a single timeout/rate-limit is not a delisting signal, that's what
  `model_state_as_of()`'s live 24h-rolling-window check is for. The 14 models affected by the gap's
  history were backfilled once, directly against live (a one-time `UPDATE`, not code) — see git
  history for the exact statement if ever needed again.
- **The two jobs have opposite retry philosophies on purpose** — catalog job retries once on a
  transient-looking failure (navigation error, or the specific `/experience-unavailable` redirect);
  completions job retries *zero* times for anything (timeout/429/5xx all recorded immediately) —
  design_decisions.md is explicit that an in-run retry there risks manufacturing a false "working"
  result; the next hourly run is the real retry. Don't port one job's retry pattern into the other.
- **`model.catalog_href`** — stores the raw, pre-redirect catalog-list href separately from `slug`
  (the resolved value), specifically because a slug-only fallback lookup misses a model whose href
  redirects elsewhere (confirmed real: `ising-calibration-1-35b-a3b` → `ising-calibration-1.5-31b`).
  `find_model_by_href()` in `catalog_scraper.py` tries slug first, `catalog_href` second.
- **`resolve()` in `resolution.py` never actually returns `excluded_non_text`** — every failure
  counts as `counted_error` in v1. Real tag data showed a tags-based exclusion heuristic can't be
  built safely without completions-failure evidence to validate it against first (design_decisions.md
  already burned two heuristics on this exact mistake). Revisit only with real evidence, not a
  guessed tags rule.
- **Every DB function (`model_state_as_of`, all `landing_*`/`models_table_*`/`model_detail_*`/
  `model_selector_options` RPCs) is `SECURITY INVOKER`, explicit, never DEFINER**, with `EXECUTE`
  explicitly revoked from `PUBLIC` and re-granted to `anon` only — never left on Postgres's default
  grant. Proven with a direct contrast test, not just asserted: an identical query as `SECURITY
  INVOKER` vs `SECURITY DEFINER` returns 0 rows vs. the real count from `catalog_run` (RLS-enabled,
  zero policies) — see `db/tests/landing_functions_test.sql`. The Phase 5 functions additionally
  guard against a subtler bug: a model "seen at least once" all-time but with zero results in the
  currently-selected window must still appear (with null metrics), not silently vanish — every one
  of them pushes the `p_since` check into each aggregate's own `FILTER` clause rather than a
  `WHERE`/JOIN-condition window filter, which would drop such a model from the `GROUP BY` entirely.
  See `db/tests/models_and_detail_functions_test.sql`.
- **`revoke execute on function X from public` is NOT the whole grant-hygiene story on Supabase —
  learned the hard way while building the pg_cron infra below.** Supabase sets its own per-role
  `ALTER DEFAULT PRIVILEGES` that auto-grant `EXECUTE` directly to `anon`, `authenticated`, AND
  `service_role` individually on every new `public`-schema function — a separate mechanism from the
  Postgres built-in `PUBLIC` pseudo-role default, confirmed by reading `pg_default_acl` directly.
  Revoking from `PUBLIC` doesn't touch it. Real consequence: every RPC function in this project had
  `authenticated`/`service_role` silently holding `EXECUTE` despite every function's own
  `revoke ... from public` line claiming explicit-only grants — harmless in practice for those (all
  `SECURITY INVOKER` + RLS-gated, `authenticated` unreachable since this app has no auth,
  `service_role` never shipped to the frontend), but it meant the "explicit grants only" claim
  throughout `db/schema.sql` wasn't actually true. Fixed retroactively (explicit revoke on every
  existing function — verified via `pg_proc.proacl` before/after, not just re-running the revoke
  and assuming) and going forward via `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated, service_role` (verified against a real throwaway
  function created after the fix — confirmed clean). `anon`'s own default grant is deliberately left
  alone; every function in this file is meant for `anon`, so leaving that one gives no false
  security. See `db/schema.sql`'s "GRANT HYGIENE FIX" block and the long comment above the landing
  functions for the full mechanism writeup.
- **`trigger_github_workflow(p_workflow_file text)` is the one deliberate `SECURITY DEFINER`
  exception in this codebase** — everything else is `SECURITY INVOKER`, no exceptions. It exists to
  let a pg_cron job (running as `postgres`) call GitHub's `workflow_dispatch` API via `pg_net`,
  authenticated with a PAT stored in Supabase Vault (`vault.decrypted_secrets`, name
  `github_actions_pat`) — reading Vault requires elevated privilege `postgres`-as-caller doesn't
  have under INVOKER semantics, which is the actual, narrow reason DEFINER is used here. Safe
  specifically because `EXECUTE` is granted ONLY to `postgres` (verified via `pg_proc.proacl` — the
  ALTER DEFAULT PRIVILEGES gap above made `anon` having it a real risk here, not a theoretical one,
  since this function can trigger arbitrary GitHub Actions runs and touches a live secret) — never
  reachable from the frontend's anon key. Don't copy this pattern anywhere the caller isn't
  guaranteed to be `postgres`/pg_cron specifically.
- **Why GitHub's own `schedule:` cron trigger is being supplemented with an external pg_cron +
  pg_net trigger**: confirmed (via inspecting NIMStats' actual production workflow) that
  `schedule:`-triggered GitHub Actions runs are unreliable enough in practice that NIMStats itself
  relies entirely on an external caller hitting `workflow_dispatch` on a schedule instead. Supabase
  pg_cron now calls `workflow_dispatch` on both `catalog-discovery.yml` and `completions-sweep.yml`
  hourly/daily via `trigger_github_workflow()` above. The `schedule:` trigger is deliberately still
  left in both YAML files as a redundant backup for now (`completions-sweep.yml`'s
  `cancel-in-progress: true` already makes an accidental overlap harmless) — not removed until the
  pg_cron path has proven itself reliable over real days of operation, a decision explicitly
  deferred, not forgotten.
- **`db/pg_cron_setup.sql` is the first piece of database state in this project that cannot be
  verified against a local Docker container** — `pg_cron` requires `shared_preload_libraries`
  configured at the Postgres *server* level, which Supabase's managed platform provides but a plain
  `postgres:16` image does not, so `create extension pg_cron` fails there. It was verified
  live-only, by necessity, not because local-first verification was skipped — every actual claim
  (extensions enabled, function's ACL locked to `postgres`-only, `cron.schedule`'s upsert-by-name
  behavior) was still independently confirmed by querying the live project directly (`pg_proc.proacl`,
  `cron.job`, re-running `cron.schedule` and checking the `jobid` didn't change), same evidentiary
  standard as everywhere else in this project, just against the live project instead of a throwaway
  container since no throwaway container option exists for this one.
- **Frontend** (`frontend/`): Vite + React 18 + TypeScript + Tailwind v3 + Tremor 3.18.7 (see
  Architecture section below for why those specific versions, not current majors) plus
  `react-router-dom` (`HashRouter` — see Architecture) and `recharts` (pinned to the version Tremor
  itself bundles, `2.15.4`, for the Capability Radar — no Tremor radar component exists). Landing
  page, Models page (name filter, per-model sparklines, state badge + uptime%, row click-through),
  and model detail page (KPI boxes, Capability Radar, Performance vs Global Average, Error Breakdown
  donut, Availability Heatmap via Tremor's `Tracker`, Response Time History, Run History with a
  response-text modal) all read live data through RPC functions using the anon key — verified by
  actually loading every page in a browser against real data, which caught real bugs `tsc`/`vite
  build` didn't: an unmemoized `since` value causing an infinite refetch loop (Phase 4, fixed with
  `useMemo`); a Top 5 table column clipped by Tremor's default sizing (Phase 4, measured in-browser);
  and, in Phase 5, **the Capability Radar (`CapabilityRadar.tsx`) is currently BROKEN and shipped
  that way — recharts' `RadarChart` does not render in this project's toolchain (Vite 8 / React
  18.3.1 / esbuild pre-bundling), independent of this component's code.** Every data point renders
  collapsed to the chart's exact center regardless of value. This was NOT solved despite extensive
  attempts, each of which appeared to work once and then failed on honest re-verification — this
  history matters for whoever picks it up next, so a claimed fix isn't trusted again without the
  same rigor:
  - A manual `domain` prop on `PolarRadiusAxis` plus `allowDataOverflow` (to work around recharts
    silently discarding a manual `domain` without it, and its `isDomainSpecifiedByUser` check's
    `!!domainStart` treating a literal `0` as unspecified) *appeared* to fix one model's chart —
    confirmed broken again on a genuinely cold reload (full dev-server restart, Vite dep cache
    cleared, brand-new browser tab): the first "it works" was a false positive from stale
    Vite/HMR module state, not a real fix.
  - Replacing the manual domain with a second, invisible `<Radar dataKey="anchor">` series carrying
    real `0`/`100` values (so recharts' auto-domain-from-data path — the one path that had rendered
    correctly — would naturally union to a fixed `[0,100]` range) also failed on a clean reload,
    for every model tested, including the one that had "worked" moments earlier with identical code.
  - Isolated every other variable one at a time, all disproven: a literal `0` data value (tested by
    forcing a `0.5` floor instead — no effect), a sibling `DonutChart` mounted elsewhere on the same
    page (removed it — no effect), React `StrictMode`'s double-invoke behavior (removed it — no
    effect). **The conclusive test: a bare RadarChart copy-pasted from recharts' own docs, mounted
    standalone with zero app code and a fixed-pixel-size (not percentage/ResponsiveContainer-timing-
    dependent) container, also rendered every point collapsed to center.** This is an
    environment-level incompatibility with recharts' polar-chart family specifically — every other
    chart type in this app (`AreaChart`, `DonutChart`, `BarChart` equivalents via Tremor) renders
    correctly.
  - `CapabilityRadar.tsx` currently contains the anchor-series version (the best-reasoned attempt,
    not a confirmed fix) with a prominent file-level comment explaining all of this. Needs a real
    decision — most likely trying a different recharts 2.x patch version, or dropping `RadarChart`
    for this specific visualization — not another round of guessing at `PolarRadiusAxis` props.
- **Two real color collisions exist in the categorical palette (`frontend/src/lib/chartColors.ts`),
  confirmed via direct swatch comparison, not just reasoned about** — `Degraded` (model state) and
  `rate_limited` (error category) are both literally `#f59e0b`; `Removed` (model state) and
  `removed` (error category) are both literally `#f43f5e`, not just similar shades. Both pairs are
  currently invisible only because `rate_limited` has never fired once in this project's history and
  no model is currently in `Removed` state — a data coincidence, not evidence the palette is safe.
  The model detail page renders the state badge and the Error Breakdown donut on the same screen, so
  if either condition ever occurs for a real model, its state badge and a donut slice will render in
  identical color, side by side. **Before that page ships as one of these two states colliding for
  real, give the state badge and the donut a distinguishing cue (an icon, a border, a different
  shade)** — don't rely on the coincidence continuing. Full detail, including how this was verified
  (a real live-page screenshot plus a labeled constructed swatch comparison, since live data can't
  currently produce either collision), lives in `DESIGN.md`'s Colors section.
- **Deferred, not forgotten, with reasons:**
  - Light/dark theme toggle — do it once, after every page exists, not piecemeal per-page.
- `db/tests/*.sql` (`model_state_as_of_test.sql`, `rls_test.sql`, `landing_functions_test.sql`,
  `models_and_detail_functions_test.sql`) — rerun after any change to the functions/policies they
  cover; see "Setup / commands." Always verify locally before touching the live project — never
  treat a local pass as optional (Hard rules above).

All project context otherwise lives in `_planning/` (gitignored — local planning material, not
committed, but present on disk and authoritative):

- `_planning/NIMTracker-implementation-plan.md` — phase-by-phase build plan, repository layout,
  and the guided Supabase setup walkthrough, now updated with the Phase 0/1 findings folded in.
  **Read this in full before writing any code.**
- `_planning/design_decisions.md` — the full functional spec: use cases, schema rationale, the
  model discovery/testing pipeline, and every view's data requirements. **Read this in full too.**
  Not updated with Phase 0/1 findings — `NIMTracker-implementation-plan.md` and `db/schema.sql` are
  the current source of truth where the two disagree (e.g. `api_model_id`, `catalog_run`).
- `_planning/reference/*.py` (`scrape_catalog.py`, `check_completions.py`, `check_models_list.py`,
  `check_rate_limit.py`) — throwaway validation scripts that proved the scraping approach and the
  error taxonomy. Reference only, superseded by `backend/nimtracker/catalog_scraper.py` for the
  parts it now covers.
- `_planning/reference/schema.sql` — superseded by `db/schema.sql`. Kept only for history.

Build in the phase order the implementation plan lays out (Phase 0 → 7). Do not skip ahead to
later-phase code (e.g. frontend) before earlier phases (Supabase project) are actually in place —
later phases depend on concrete outputs of earlier ones, not just their written intent.

## What this app is

A tracker for NVIDIA's free NIM model endpoints: discovers the current catalog of free-tier models
daily, probes every one of them with a real completions call hourly, and shows results
(availability over time, response time, throughput, error taxonomy) in a small dashboard. Single
persona (the user themself) — no auth, no multi-tenant concerns.

## Architecture (finalized — do not re-litigate)

- **Automation: Python**, pinned to the current stable release at setup time (not floored at an
  older version) — confirm Playwright, `httpx`, and `psycopg` all publish wheels for it first.
  HTTP calls via `httpx` (not `urllib`), real timeout/retry control. Direct Postgres writes via
  `psycopg`.
- **Scraping: Playwright (Chromium)** against `build.nvidia.com`'s live catalog page (filtered to
  Free Endpoint models) — **not** the `/v1/models` API endpoint, which was tried and dropped after
  it proved to include mostly legacy/deprecated noise with no reliable free-tier filter.
- **Database: Supabase Postgres**, written to from GitHub Actions via a direct Postgres connection
  string (the Session pooler, not the direct/IPv6-only connection) — never via the REST API or
  Edge Functions. Edge Functions were considered and rejected: their 150s request idle timeout is
  shorter than observed real model response times (up to ~166s).
- **Frontend: React + TypeScript + Vite + Tailwind + Tremor** (built on Recharts), Supabase client
  (`@supabase/supabase-js`) queries data directly using the anon key.
- **Routing: `react-router-dom`'s `HashRouter`, not `BrowserRouter` — a deliberate Phase 5 choice,
  not an oversight to "fix" later.** Deployment is GitHub Pages (see Deployment below), which has no
  SPA-fallback routing set up yet — that's still Phase 7. `BrowserRouter` would 404 on a direct link
  or page refresh to e.g. `/models/some-model` since GH Pages has no real file at that path.
  `HashRouter` (`/#/models/some-model`) never sends a route change to the server at all, sidestepping
  the problem with zero deploy config, at the cost of a `#` in every URL. **Revisiting this (e.g.
  switching to `BrowserRouter` plus a GH Pages `404.html` SPA-fallback trick) is an explicit Phase 7
  decision**, to be made once that fallback actually exists — not something a future session should
  "fix" by itself on the assumption hash-routing was a mistake. Also note: `model.slug` contains a
  literal `/` (e.g. `moonshotai/kimi-k3`), so the model detail route is a splat (`models/*`), not
  `models/:slug` — a single param wouldn't match a slash-containing segment correctly.
- **Pinned deliberately: Tremor 3.18.7 (stable), React 18, Tailwind v3 — not the current majors.**
  Checked directly against npm at Phase 4 planning time: `@tremor/react`'s `latest` tag (3.18.7)
  requires `react: ^18.0.0` and its classes don't render correctly under Tailwind v4's new engine
  (confirmed via Tremor's own GitHub issues, not just assumed). A Tailwind-v4/React-19-compatible
  Tremor exists only as `4.0.0-beta-tremor-v4.x` — still an unpromoted beta even after several
  iterations, not `latest`. Deliberately chose the one-version-behind *stable* stack over the
  *current* beta for a library that renders the entire UI — **do not "helpfully" upgrade to Tailwind
  v4 / Tremor's beta line** without first re-checking whether Tremor has actually promoted a
  Tailwind-v4-compatible release to `latest`; if it has, upgrading is fine, but on unverified
  assumption it isn't. This is the one place in the stack that deliberately isn't "current stable,
  not floored" — see the Python/Playwright/httpx/psycopg line above for contrast on why that
  principle doesn't apply here.
- **Security model: RLS, not secrecy.** The anon key is expected to ship in the frontend bundle.
  `model`/`execution`/`result` get RLS enabled with a `SELECT`-only policy for `anon`; no
  insert/update/delete policy exists for that role at all (default-deny). All writes happen only
  from GitHub Actions jobs authenticated with the Postgres connection string.
- **Watch item: Supabase's "explicit Postgres grants for the Data API" rollout, effective for
  existing projects from October 2026.** design_decisions.md flagged this as an open item to verify
  once the frontend's query layer got built. Verified directly in Phase 4 (real anon-key
  `@supabase/supabase-js` calls against the live project, both `.rpc()` on the `landing_*` functions
  and a direct `.from('catalog_run').select()` negative control): as of that check, ordinary
  `GRANT EXECUTE ... TO anon` / the existing RLS `SELECT` policies were sufficient on their own —
  no separate Data-API-specific opt-in was needed. **This was confirmed working *before* the October
  2026 rollout date**, not after it. If any database-access call from the frontend (a `.rpc()` call
  or a direct table `select`) starts failing after that date, re-verify the anon-key RPC/RLS path
  specifically first — don't assume it's unrelated just because the code hasn't changed.
- **Deployment:** three GitHub Actions workflows — daily catalog discovery, hourly completions
  sweep (both write to Supabase Postgres directly), and a frontend build+deploy to GitHub Pages via
  `actions/deploy-pages` on push to `main`.

## Core domain logic (the parts most likely to be re-derived wrong)

- **No heuristic may ever prevent a model from being tested.** Catalog/detail-page signals
  (Specifications sidebar presence, Output Modalities, tags) are advisory only — used to interpret
  a *failure* after the fact, never to skip a completions probe. This was settled after two
  heuristics were tried and empirically disproved (each wrongly excluded at least one model that
  later succeeded). The resolution table (success always counted as working regardless of
  heuristic; failure classified as real error vs. excluded-non-text based on the heuristic; unknown
  heuristic defaults to "real error", not excluded) lives in `design_decisions.md` under "Model
  discovery & testing pipeline" — implement it exactly, in one isolated, unit-tested module
  (`resolution.py` per the plan).
- **Intentional v1 limitation: `resolve()` never actually excludes anything (`excluded_non_text` is
  unreachable in practice).** The design doc's exclusion case requires "sidebar absent + tags
  indicate non-text," but real tag data pulled from the live `model` table during Phase 3 planning
  showed this can't be done safely with a keyword heuristic — e.g. `nemotron-3-embed-1b`'s tags
  literally include `'Text-to-Embedding'` (a naive "text" match would call it text-capable, backwards
  from reality), while `llama-guard-4-12b` (a genuine text-in/text-out safety classifier) has no
  text-ish keyword in its tags at all. Building a tag keyword list here would be exactly the kind of
  heuristic design_decisions.md already burned two attempts on and explicitly rejected. Decided:
  every failure defaults to `counted_error` for v1, regardless of heuristic signal — the ~19 current
  no-sidebar/non-standard-page models (translation, embedding, TTS, safety-guard, autonomous-vehicle
  perception, etc.) will show as `counted_error`, not silently excluded, if their completions call
  fails. Revisit only with real completions-failure evidence once Phase 3 has actually run (the same
  methodology Phase 0 used to disprove the first two heuristics), never by guessing a tags rule
  up front.
- **No cached current-state field on `model`.** Available/Removed/Degraded state is always derived
  live from `result` history via a single shared function/view (`model_state_as_of()`), never
  duplicated across the several views that need it (Models table Uptime column, model detail page
  KPIs, Error Breakdown, Availability Heatmap). The heatmap in particular needs "state as of time
  T" across a window, not just current state — design the function for that from the start.
- **`result.resolution` is snapshotted at write time**, not recomputed later from the model's
  *current* heuristic data — historical counts must stay stable even if the heuristic is later
  improved.
- **Discovery (daily) and completions testing (hourly) are separate activities**, not two tiers of
  the same cadence. Every catalog-listed model is probed every hourly sweep, unconditionally — no
  model is skipped based on prior state.
- **Hourly sweep parameters:** 240s per-model timeout, 3-way concurrency, no in-run retries on
  `rate_limited` or `server_error` (the next hourly run is the retry, by design — an immediate
  retry risks manufacturing a false "working" data point).
- **Error taxonomy** (`removed / rate_limited / degraded / timeout / server_error /
  empty_response / other`) must never be collapsed into fewer categories — this is the direct fix
  for the misleading blended "success rate" metric that motivated this rewrite.
- **Fallback strategy is DB-backed, not a second scraper.** If the catalog list scrape fails
  entirely, fall back to the last-known model list from the DB (flag `list_source: db_fallback`).
  If one model's detail-page scrape fails, fall back to that model's last DB record (flag
  `detail_source: db_fallback`, or `unknown` for a brand-new model).
- **`api_model_id` vs `slug`:** the literal `model` string used in completions API calls is scraped
  from the code snippet on each model's own detail page (authoritative, `api_model_id_source =
  'scraped_snippet'`), with "slug minus leading slash" as a fallback only where the snippet is
  missing (`'derived_fallback'`) — the two are not assumed identical without checking. Verified
  against the full live catalog in Phase 0: zero mismatches, but store both fields with explicit
  provenance anyway (`model.api_model_id` / `model.api_model_id_source` in `db/schema.sql`) rather
  than recomputing from `slug` at call time — see the next point for why that matters.
- **`model.slug` must be the resolved slug, not the raw catalog-card href.** Phase 0 found a live
  example of a catalog card whose `href` 30x-redirects to a different, canonical detail-page URL.
  The scraper must always upsert using wherever the detail-page navigation actually landed (`page.url`
  after following redirects), never the un-navigated href straight off the list page — otherwise a
  redirecting model eventually creates a duplicate `model` row instead of updating the existing one.
- **Detail-page scrape failures need the same "no permanent conclusion from one check" discipline
  already specified for the hourly completions job.** Phase 0 observed one model transiently
  redirect to an error page on one run and load fine immediately before/after, while a different
  model redirected consistently across repeat checks. Retry once before recording a detail-page
  scrape as failed or falling back to the DB record — don't treat a single failed navigation as
  authoritative.
- **`catalog_run` is a separate table from `execution`.** The reference schema tracked catalog
  list-source provenance (`live` / `db_fallback`) as a column on `execution`, which conflated the
  daily catalog-discovery job with the hourly completions job — they're separate activities and the
  hourly sweep doesn't scrape a list at all. `db/schema.sql` gives the daily job its own
  `catalog_run` table for this instead.

## Explicitly out of scope for v1

Alerting/notifications, Artificial-Analysis-dependent metrics (Intelligence Index, Score, Intel,
TTFT via streaming), a "Compare" view, and correct probing for embedding/vision/retrieval-only
models (they stay excluded from "tested" until revisited). Don't build these even if they seem
like natural additions.

## Setup / commands

- **Backend (Python 3.14, venv at `backend/.venv`, not committed):**
  ```
  cd backend && python3 -m venv .venv && .venv/bin/pip install -e ".[test]"
  .venv/bin/playwright install chromium
  .venv/bin/python -m nimtracker.catalog_scraper --out out/some_name.json          # scrape-only, no DB
  .venv/bin/python -m nimtracker.catalog_scraper --run-job --db-url <local-dsn>    # the real job
  .venv/bin/python -m pytest tests/test_catalog_job.py -v                         # self-contained, spins up its own Docker Postgres
  ```
  `backend/out/` holds scrape output and is gitignored-worthy scratch data, not committed source.
  `backend/tests/conftest.py`'s Docker fixture also needs `create role anon;` run against the
  container before it applies `db/schema.sql` (every RPC function does `grant ... to anon`, which
  errors on a role-less plain `postgres:16` image) — already wired into the fixture.
- **Schema verification (local only, never against the real Supabase project without
  confirmation — see Hard rules):** apply `db/schema.sql` then `db/rls_policies.sql` to a scratch
  Postgres instance and run the `db/tests/*.sql` files against it. A throwaway Docker container
  works well for this and leaves nothing behind:
  ```
  docker run -d --name nimtracker-schema-test -e POSTGRES_PASSWORD=test -p 55432:5432 postgres:16
  docker exec nimtracker-schema-test psql -U postgres -c "create role anon;"
  cat db/schema.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  cat db/rls_policies.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  cat db/tests/model_state_as_of_test.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  cat db/tests/rls_test.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  cat db/tests/landing_functions_test.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  cat db/tests/models_and_detail_functions_test.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  docker rm -f nimtracker-schema-test
  ```
  **The `create role anon;` step must run before `db/schema.sql`, not after** — `schema.sql` itself
  now does `grant execute ... to anon` on every RPC function (since Phase 4), not just
  `rls_policies.sql`. Plain Postgres also has no base GRANTs to `anon` by default the way Supabase
  does; `rls_test.sql`/`landing_functions_test.sql`/`models_and_detail_functions_test.sql` each do
  their own additional role/grant setup internally, transaction-wrapped and rolled back.
- **Supabase CLI (`brew install supabase/tap/supabase`, already linked to project
  `huladiqsospiarkumujz` via `supabase link`):**
  ```
  supabase migration list         # compare local supabase/migrations/ against what's applied live
  supabase db diff --linked       # full schema diff against live — spins up a throwaway local
                                   # Supabase stack via Docker to compute it, cleans up after itself
  ```
  **`supabase db push` applies `supabase/migrations/*.sql` to the real live project — this is
  exactly the kind of command the Hard rules require confirmation for.** Never run it without
  Javier explicitly saying go for that specific push, regardless of what's already in the migrations
  directory. A new schema change goes: edit `db/schema.sql`/`db/rls_policies.sql` → verify locally
  (Docker container, both test files) → copy into a new timestamped file under
  `supabase/migrations/` → show Javier the exact file(s) → confirm → `db push` → `db diff --linked`
  to independently verify what actually landed.
- **Frontend (`frontend/`, Vite + React + TS):**
  ```
  cd frontend && npm install
  npm run dev              # local dev server; shut it down when done verifying, don't leave it running silently
  npx tsc --noEmit         # type-check
  npm run build             # tsc -b && vite build
  ```
  `frontend/.env` holds `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` — the anon key is a publishable
  key, safe to have in this file and in the built bundle (see Architecture, "Security model").
