-- NIM Availability Tracker — Schema (v1)
-- Target: PostgreSQL / Supabase. Derived from design_decisions.md after
-- walking all four views (landing, Models, model detail, Executions)
-- against these entities and confirming every requirement is answerable,
-- then adjusted per the Phase 0 model-identifier verification pass (see
-- NIMTracker-implementation-plan.md, Phase 1) -- two real findings from
-- scraping the live catalog changed this schema, noted inline below.

create extension if not exists "pgcrypto"; -- for gen_random_uuid()

-- =========================================================================
-- MODEL — persistent registry, one row per distinct model ever discovered.
-- =========================================================================
create table model (
  -- The catalog-card href is NOT guaranteed to be a model's stable
  -- identity -- confirmed during Phase 0: at least one model's catalog
  -- href 30x-redirected to a different, canonical slug on its own detail
  -- page. This column must always hold the RESOLVED slug (i.e. wherever
  -- the detail-page scrape actually landed after following redirects),
  -- never the raw catalog-list href as-scraped. Getting this wrong means
  -- a redirecting model eventually creates a duplicate row instead of
  -- updating the existing one.
  slug                        text primary key, -- e.g. 'moonshotai/kimi-k3', resolved, no leading slash
  provider                    text not null,
  model_name                  text not null,
  description                 text,
  tags                        text[],

  -- The raw, as-scraped catalog-card href (e.g.
  -- '/nvidia/ising-calibration-1-35b-a3b'), kept verbatim (leading slash
  -- and all) purely as a secondary lookup key -- NOT an identity column,
  -- `slug` is still that. Added in Phase 2 after finding a real gap: when
  -- a model's detail-page scrape fails on a given run, the only fallback
  -- lookup available is by slug -- but a REDIRECTING model's href never
  -- equals its resolved slug (see the comment on `slug` above), so that
  -- lookup silently misses and the catalog job would insert a duplicate
  -- row instead of finding the existing one. Confirmed real, not
  -- hypothetical: '/nvidia/ising-calibration-1-35b-a3b' 30x-redirects to
  -- 'nvidia/ising-calibration-1.5-31b' right now. Populated on every
  -- successful list scrape for every model in it, independent of whether
  -- that model's own detail-page scrape succeeds this run.
  catalog_href                text,

  -- catalog badges (from the live catalog scrape)
  is_free_endpoint            boolean not null default true,
  deprecation_days            integer, -- from "Deprecation in Xd" badge; null = no warning currently shown

  -- heuristic signal from the model's own detail page.
  -- ADVISORY ONLY, per the resolution table below — this NEVER gates
  -- whether a model gets tested. Two prior heuristics (catalog tags,
  -- then sidebar-presence alone) were built and empirically disproven
  -- on real data before this design was settled.
  output_modalities           text,     -- e.g. 'Text', 'Text, Image'; null = unknown or non-standard page template
  has_specifications_sidebar  boolean,  -- null = unknown (scrape never succeeded for this model)
  is_text_completion_model    boolean,  -- derived: has_specifications_sidebar AND output_modalities ILIKE '%text%'; null = unknown

  -- extra detail-page metadata, used by the model detail page
  context_length              text,     -- e.g. '1M' — kept as scraped text, not normalized to a number
  parameters                  text,     -- e.g. '30B', '2.8T' — same reasoning
  function_calling            boolean,
  structured_output           boolean,
  reasoning                   boolean,

  -- provenance of the LAST successful scrape for this model's detail page
  -- (the sidebar / heuristic fields above)
  detail_source               text not null default 'unknown'
                               check (detail_source in ('live', 'db_fallback', 'unknown')),

  -- The literal `model` value the completions job must call the API with
  -- (NVIDIA's own documented identifier for this model, scraped from the
  -- code snippet on its detail page) -- distinct from `slug`, which is
  -- the catalog identity/URL. Added in Phase 1 after the Phase 0 pass:
  -- zero mismatches were observed against "slug minus leading slash" on
  -- the full live catalog (35 models), but the redirect finding above
  -- means slug itself can drift, so this is stored explicitly with
  -- provenance rather than recomputed from slug at call time.
  api_model_id                text,     -- null only if api_model_id_source = 'unknown'
  api_model_id_source         text not null default 'unknown'
                               check (api_model_id_source in ('scraped_snippet', 'derived_fallback', 'unknown')),

  -- lifecycle
  first_discovered_at         timestamptz not null default now(),
  last_seen_working_at        timestamptz, -- null = never had a single successful completion; drives the Models-table "seen at least once" rule
  delisted_at                 timestamptz, -- set immediately on an explicit 410 w/ end-of-life date, OR after the 24h rolling-failure window for ambiguous failures (see model_state_as_of below)
  delisted_reason             text,        -- free text, e.g. NVIDIA's own end-of-life message, or 'no successful completion in trailing 24h'

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

create index idx_model_last_seen_working on model (last_seen_working_at)
  where last_seen_working_at is not null; -- speeds the "seen at least once" filter used by Models page + model selector

-- =========================================================================
-- CATALOG_RUN — one row per daily catalog-discovery run.
--
-- Added in Phase 1. The reference schema tracked list-source provenance
-- as a column on EXECUTION, which conflated it with the hourly
-- completions sweep -- but catalog discovery (daily) and completions
-- testing (hourly) are separate activities (design_decisions.md,
-- "Cadence"): the hourly sweep doesn't scrape a list at all, it just
-- tests whatever model rows already exist. This table gives the daily
-- job's own list-source fallback (design_decisions.md, "Fallback
-- strategy") somewhere to actually be recorded, instead of only being
-- handled silently in `model.detail_source` per-row.
-- =========================================================================
create table catalog_run (
  id                  uuid primary key default gen_random_uuid(),
  started_at          timestamptz not null default now(),

  list_source         text not null default 'live'
                       check (list_source in ('live', 'db_fallback')),
  models_found_count  integer, -- count of cards on the list page this run (or in the db-fallback list used)

  created_at          timestamptz not null default now()
);

create index idx_catalog_run_started_at on catalog_run (started_at desc);

-- =========================================================================
-- EXECUTION — one row per hourly completions-testing run.
-- Note: this is the completions run only, NOT the daily catalog-discovery
-- refresh — those are two separate activities (see design_decisions.md,
-- "Cadence" section, and catalog_run above).
-- =========================================================================
create table execution (
  id                       uuid primary key default gen_random_uuid(),
  started_at               timestamptz not null,

  -- denormalized summary fields, populated once when the run completes.
  -- These exist specifically so the Executions page's collapsed row and
  -- the landing page's overall "Models Available Over Time" trend chart
  -- are a direct read with zero aggregation — confirmed during the
  -- landing-page schema check as the reason this denormalization earns
  -- its place rather than being redundant with Result.
  models_tested_count      integer not null default 0,   -- excludes resolution = 'excluded_non_text' rows
  models_succeeded_count   integer not null default 0,
  fastest_model_slug       text references model(slug),
  fastest_response_time_s  numeric,

  created_at               timestamptz not null default now()
);

create index idx_execution_started_at on execution (started_at desc); -- every time-filtered view range-scans this

-- =========================================================================
-- RESULT — core fact table. One row per model per execution.
-- =========================================================================
create table result (
  id                 uuid primary key default gen_random_uuid(),
  execution_id       uuid not null references execution(id) on delete cascade,
  model_slug         text not null references model(slug),

  success            boolean not null,
  error_category     text
                      check (error_category in
                        ('removed', 'rate_limited', 'degraded', 'timeout',
                         'server_error', 'empty_response', 'other')
                        or error_category is null),
  error_body         text, -- raw error response, capped length at write time (see check_completions.py pattern)

  response_time_s    numeric,
  completion_tokens  integer,
  prompt_tokens      integer,
  tokens_per_sec     numeric,
  response_text      text, -- full response text; powers the "view response" modal on Executions and model detail Run History

  -- SNAPSHOTTED AT WRITE TIME — confirmed, not recomputed later from the
  -- model's current heuristic data. A past execution's tested/working
  -- counts must never silently change if the heuristic is later improved
  -- or a model's classification changes. See design_decisions.md,
  -- "Core entities" section, for the full trade-off discussion.
  resolution         text not null
                      check (resolution in
                        ('counted_working', 'counted_error', 'excluded_non_text')),

  created_at         timestamptz not null default now(),

  unique (execution_id, model_slug) -- one result per model per execution
);

create index idx_result_model_time on result (model_slug, execution_id); -- per-model time series (sparklines, Response Time History)
create index idx_result_execution on result (execution_id);             -- Executions page expanded-row lookups
create index idx_result_resolution on result (resolution);              -- fast filtering to the "tested" set (excludes excluded_non_text)

-- =========================================================================
-- SHARED STATE-DERIVATION LOGIC
--
-- Confirmed during the model-detail-page schema check as needed by
-- multiple separate consumers: the Models-page Uptime column, the
-- model-detail Uptime KPI, the Capability Radar's Reliability axis, the
-- Error Breakdown, and the Availability Heatmap. Written once here so
-- every consumer reads from the same logic instead of drifting out of
-- sync.
--
-- The Heatmap specifically requires "state AS OF a given point in time,"
-- not just "state right now" — that's a real constraint on this
-- function's shape, not an optional extra.
--
-- Hardened in Phase 1 against five scenarios (see db/tests/
-- model_state_as_of_test.sql): only-successes, explicit 410, failures
-- inside the 24h window, failures outside the 24h window, and no results
-- at all. Each is asserted against a real Postgres instance, not just
-- read as correct.
-- =========================================================================
create or replace function model_state_as_of(p_slug text, p_as_of timestamptz)
returns text as $$
declare
  v_delisted_at        timestamptz;
  v_most_recent_at     timestamptz;
  v_most_recent_success boolean;
  v_last_success_at    timestamptz;
begin
  select delisted_at into v_delisted_at from model where slug = p_slug;

  -- immediate removal: an explicit 410 w/ end-of-life date sets
  -- model.delisted_at directly at ingestion time, not via this function
  if v_delisted_at is not null and v_delisted_at <= p_as_of then
    return 'removed';
  end if;

  -- find the most recent result as of p_as_of
  select e.started_at, r.success
  into v_most_recent_at, v_most_recent_success
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and r.resolution != 'excluded_non_text'
    and e.started_at <= p_as_of
  order by e.started_at desc
  limit 1;

  if v_most_recent_at is null then
    return 'unknown'; -- no results at all as of this point in time
  end if;

  if v_most_recent_success then
    return 'available';
  end if;

  -- most recent result is a failure -- distinguish DEGRADED (still within
  -- the 24h grace window since the last success) from REMOVED (a full 24h
  -- has passed with zero successes). These are genuinely different states,
  -- not the same outcome -- an earlier draft of this function wrongly
  -- collapsed them into one.
  select max(e.started_at) into v_last_success_at
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and r.success
    and r.resolution != 'excluded_non_text'
    and e.started_at <= p_as_of;

  if v_last_success_at is null or p_as_of - v_last_success_at >= interval '24 hours' then
    return 'removed';  -- 24h+ with zero successes -- confirmed broken, per the rolling-failure-window rule
  else
    return 'degraded'; -- currently failing, but still inside the 24h grace window
  end if;
end;
$$ language plpgsql stable;
