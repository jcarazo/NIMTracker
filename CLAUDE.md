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

**Phase 0 and Phase 1 are done and live. Phase 2 (catalog discovery job) is written and verified
locally, but not yet pushed/run against the live Supabase project — waiting on explicit go-ahead
for both the pending migration and the first live run.** Project ref `huladiqsospiarkumujz`
(`https://huladiqsospiarkumujz.supabase.co`). What's on disk / live so far:

- `backend/nimtracker/catalog_scraper.py` + `backend/nimtracker/db.py` — the real Phase 2 catalog
  job (`run_catalog_job()`), plus the original Phase 0 scrape-only/JSON-dump mode (still available,
  `python -m nimtracker.catalog_scraper` with no `--run-job`). Retry-once on both the list scrape
  and each detail scrape (specifically on navigation errors or a redirect to
  `/experience-unavailable` — never on a legitimate non-standard page like a translation/embedding
  demo, which has no sidebar/snippet by design, not by failure). DB-backed fallback matching
  design_decisions.md's "Fallback strategy": total list-scrape failure → `model` table untouched,
  `catalog_run.list_source = 'db_fallback'`; one model's detail-scrape failure → falls back to its
  last-known DB row via `find_model_by_href()` (slug match first, `catalog_href` match second — see
  `model.catalog_href` below); brand-new model with a failed detail scrape → still inserted,
  `detail_source: 'unknown'`, never silently dropped. One transaction per run (atomic).
  `backend/tests/test_catalog_job.py` (pytest, self-contained — spins up and tears down its own
  Docker Postgres container) covers all of this with synthetic scrape results, including the
  redirecting-href dedup case specifically. Also proven with one real end-to-end run (live
  Playwright scrape of the actual NVIDIA catalog + writes to a local container): 35 models found, 34
  distinct rows (the `ising-calibration` redirect correctly collapsed to one row instead of
  duplicating), 3 fell back to `detail_source: 'unknown'` (two `llama-3.2-*-vision-instruct` models
  and `cosmos3-nano-reasoner` all hit `/experience-unavailable` on both attempts that run — real
  evidence the retry-once discipline is necessary, not just theoretical). **Nothing from this run
  touched the live project** — output was inspected via SQL directly against the local container,
  then torn down.
- **`model.catalog_href`** (new nullable `text` column, migration
  `supabase/migrations/20260915182102_add_catalog_href.sql`, not yet pushed live) — stores the raw,
  as-scraped catalog-list href verbatim, separately from `slug` (which stays the resolved value).
  Exists specifically because a slug-only fallback lookup silently misses a model whose href
  redirects to a different resolved slug (confirmed real:
  `/nvidia/ising-calibration-1-35b-a3b` → `nvidia/ising-calibration-1.5-31b`) — without it, a
  detail-scrape failure on a redirecting model would insert a duplicate row instead of finding the
  existing one. Verified locally by replaying the two already-live migrations then applying this one
  on top (proving it works as a true incremental `ALTER`, not just inside a fresh `CREATE`), and by
  confirming a fresh single-shot `db/schema.sql` apply produces an identical column set.
  `backend/pyproject.toml` now also includes `psycopg[binary]` (confirmed 3.14-compatible) and a
  `test` extra (`pytest`). `backend/.env.example` names the two secrets the job needs
  (`NIM_API_KEY`, `SUPABASE_DB_URL`), already set as GitHub Actions repo secrets.
- **Still pending, in order, each needing explicit go-ahead separately (Hard rules above):** (1)
  `supabase db push` for the `catalog_href` migration, (2) an actual `--run-job` run against the
  live project. `.github/workflows/catalog-discovery.yml` (the scheduled cron) is explicitly held
  for a separate pass — not drafted yet, by request.
- `db/schema.sql`, `db/rls_policies.sql` — finalized in Phase 1, verified against a throwaway local
  Postgres container (not Supabase) *and* pushed to the live project via
  `supabase/migrations/20260915150904_initial_schema.sql` +
  `20260915150905_rls_policies.sql` (`supabase db push`). Independently re-verified post-push with
  `supabase db diff --linked` — zero drift on anything we wrote; the only diff lines were Supabase's
  own platform defaults (`pg_net` extension, and the `rls_auto_enable()` event trigger from the
  "Enable automatic RLS" option checked at project creation — that trigger auto-enables RLS with no
  policy on any *future* new `public`-schema table, same default-deny shape as `catalog_run` below).
- `db/tests/model_state_as_of_test.sql` — 7 scenarios (the 5 the plan asked for, plus 2 more) for
  `model_state_as_of()`, all passing against a real Postgres instance. Rerun this after any change
  to that function.
- `db/tests/rls_test.sql` — confirms `anon` can read `model`/`execution`/`result` but gets **zero**
  access to `catalog_run` (not even `SELECT`, despite real rows existing), and that writes are
  denied by RLS itself even when `anon` is granted full CRUD at the GRANT layer (matching Supabase's
  actual default privilege model, not a weaker "no grant at all" test). Rerun after any RLS change.
- `frontend/.env.example` — names `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`, the Vite-exposed
  names the eventual frontend build maps from the `SUPABASE_URL` / `SUPABASE_ANON_KEY` GitHub
  Actions secrets (already set) in `deploy-frontend.yml` (Phase 7, not written yet).
- Both SQL test files, plus the Docker-container verification workflow, are reusable — see "Setup /
  commands" below. Always rerun them locally before pushing a schema change live; never treat a
  local pass as optional before touching the real project (Hard rules above).

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
later phases depend on concrete outputs of earlier ones, not just their written intent. Next up is
Phase 2 (Guided Supabase project creation, implementation plan §6) before any code that writes to a
live project.

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
- **Security model: RLS, not secrecy.** The anon key is expected to ship in the frontend bundle.
  `model`/`execution`/`result` get RLS enabled with a `SELECT`-only policy for `anon`; no
  insert/update/delete policy exists for that role at all (default-deny). All writes happen only
  from GitHub Actions jobs authenticated with the Postgres connection string.
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
