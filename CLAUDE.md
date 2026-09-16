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

**Phases 0-4 are done and live** (model-identifier verification, schema, catalog discovery job,
completions sweep job, frontend scaffold + landing page). Project ref `huladiqsospiarkumujz`
(`https://huladiqsospiarkumujz.supabase.co`). Next up is Phase 5 (Models page + model detail page).
What's on disk / live, condensed to what's still load-bearing (full blow-by-blow of each
verification run lives in git history / conversation history, not repeated here):

- **Backend jobs** (`backend/nimtracker/`): `catalog_scraper.py` (daily catalog job,
  `run_catalog_job()`) and `completions_probe.py` (hourly sweep, `run_completions_sweep()`), both
  proven end-to-end against the live project, not just unit-tested. `db.py` holds all SQL, no
  business logic. Neither job's GitHub Actions workflow exists yet (`catalog-discovery.yml`,
  `completions-sweep.yml`) — deliberately held for a separate pass, so nothing is running on a
  schedule against the live project yet. Live data right now: 34 tracked models, 1 `catalog_run`,
  1 `execution` (13 succeeded that run).
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
- **Every DB function (`model_state_as_of`, all `landing_*` RPCs) is `SECURITY INVOKER`, explicit,
  never DEFINER**, with `EXECUTE` explicitly revoked from `PUBLIC` and re-granted to `anon` only —
  never left on Postgres's default grant. Proven with a direct contrast test, not just asserted: an
  identical query as `SECURITY INVOKER` vs `SECURITY DEFINER` returns 0 rows vs. the real count from
  `catalog_run` (RLS-enabled, zero policies) — see `db/tests/landing_functions_test.sql`.
- **Frontend** (`frontend/`): Vite + React 18 + TypeScript + Tailwind v3 + Tremor 3.18.7 (see
  Architecture section below for why those specific versions, not current majors). Landing page
  (KPI row, merged "Models Available Over Time" chart with an Overall/By Provider tab toggle, Top 5
  Fastest/Throughput tables) reads live data through `landing_*` RPC functions using the anon key —
  verified with real anon-key network calls shown directly (not just "it rendered"), and by actually
  loading the page in a browser, which caught two real bugs `tsc`/`vite build` didn't: an unmemoized
  `since` value causing an infinite refetch loop (fixed with `useMemo`), and a Top 5 table column
  silently clipped by Tremor's default sizing (measured in-browser: 564px of content in a 496px
  container). No router yet — single page, `App.tsx` renders `LandingPage` directly; Phase 5 adds
  routing when a second real page exists.
- **Deferred, not forgotten, with reasons:**
  - Light/dark theme toggle — do it once, after every page exists, not piecemeal per-page.
  - Nav bar — comes naturally with Phase 5's routing; building one now for a single-page app would
    be premature.
- `db/tests/*.sql` (`model_state_as_of_test.sql`, `rls_test.sql`, `landing_functions_test.sql`) —
  rerun after any change to the functions/policies they cover; see "Setup / commands." Always
  verify locally before touching the live project — never treat a local pass as optional (Hard
  rules above).

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
  `backend/tests/test_resolution.py` gets created when `resolution.py` does (Phase 3).
- **Schema verification (local only, never against the real Supabase project without
  confirmation — see Hard rules):** apply `db/schema.sql` then `db/rls_policies.sql` to a scratch
  Postgres instance and run `db/tests/model_state_as_of_test.sql` against it. A throwaway Docker
  container works well for this and leaves nothing behind:
  ```
  docker run -d --name nimtracker-schema-test -e POSTGRES_PASSWORD=test -p 55432:5432 postgres:16
  cat db/schema.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  cat db/tests/model_state_as_of_test.sql | docker exec -i nimtracker-schema-test psql -U postgres -v ON_ERROR_STOP=1
  docker rm -f nimtracker-schema-test
  ```
  `rls_policies.sql` references the `anon` role, which plain Postgres doesn't have — `create role
  anon;` first if testing that file too. Note plain Postgres also has no base GRANTs to `anon` by
  default the way Supabase does; grant `select` (or full CRUD, to test RLS itself rather than the
  GRANT layer) explicitly before checking policy behavior. Also run `db/tests/rls_test.sql` the same
  way — it does its own role/grant setup internally, transaction-wrapped and rolled back.
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
- **Frontend:** not started — no `package.json` yet. Check the plan's Repository Layout section
  (`NIMTracker-implementation-plan.md` §3) before inventing structure. `.env.example` already exists
  with the two Vite-exposed variable names it will need.
