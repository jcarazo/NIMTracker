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

This repo is pre-code. The only tracked file is `.gitignore`; no backend, frontend, or database
code exists yet. All project context lives in `_planning/` (gitignored — local planning material,
not committed, but present on disk and authoritative):

- `_planning/NIMTracker-implementation-plan.md` — phase-by-phase build plan, repository layout,
  and the guided Supabase setup walkthrough. **Read this in full before writing any code.**
- `_planning/design_decisions.md` — the full functional spec: use cases, schema rationale, the
  model discovery/testing pipeline, and every view's data requirements. **Read this in full too.**
- `_planning/reference/*.py` (`scrape_catalog.py`, `check_completions.py`, `check_models_list.py`,
  `check_rate_limit.py`) — throwaway validation scripts that proved the scraping approach and the
  error taxonomy. Reference only — do not copy into production code; rewrite using `httpx` and
  `psycopg` per the plan.
- `_planning/reference/schema.sql` — a first-pass schema based on the spec. Will be adjusted in
  Phase 1, not used verbatim.

Build in the phase order the implementation plan lays out (Phase 0 → 7). Do not skip ahead to
later-phase code (e.g. frontend) before earlier phases (schema, Supabase project) are actually in
place — later phases depend on concrete outputs of earlier ones (table names, `api_model_id`
values, etc.), not just their written intent.

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
  from the code snippet on each model's own detail page (authoritative), with "slug minus leading
  slash" as a fallback only where the snippet is missing — the two are not assumed identical
  without checking.

## Explicitly out of scope for v1

Alerting/notifications, Artificial-Analysis-dependent metrics (Intelligence Index, Score, Intel,
TTFT via streaming), a "Compare" view, and correct probing for embedding/vision/retrieval-only
models (they stay excluded from "tested" until revisited). Don't build these even if they seem
like natural additions.

## Setup / commands

Not yet established — no `pyproject.toml`, `package.json`, or test suite exists yet. These will be
created as part of Phase 1+ per the implementation plan (`backend/pyproject.toml` for the Python
jobs with `backend/tests/test_resolution.py` as the first real test suite; `frontend/package.json`
for the Vite app). Do not invent commands before those files exist — check the plan's Repository
Layout section (`NIMTracker-implementation-plan.md` §3) for the intended structure first.
