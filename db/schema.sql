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
$$ language plpgsql stable security invoker;
-- security invoker made explicit in Phase 4 (was already the implicit
-- default -- Postgres defaults to invoker when unspecified -- but
-- explicit beats implicit for a function whose entire safety property
-- depends on it, per the same principle applied to the Phase 4 landing
-- functions below).

revoke execute on function model_state_as_of(text, timestamptz) from public;
grant execute on function model_state_as_of(text, timestamptz) to anon;
-- Also added in Phase 4: this function had no explicit grant before,
-- meaning it relied on Postgres's default EXECUTE-TO-PUBLIC grant.
-- Harmless in practice (it doesn't take a shortcut around RLS, being
-- invoker), but inconsistent with the "no default grants" posture
-- established below -- fixed here for the same reason, not because it
-- was ever exploitable.

-- =========================================================================
-- LANDING PAGE AGGREGATE FUNCTIONS (Phase 4)
--
-- PostgREST (what @supabase/supabase-js actually talks to) can't express
-- arbitrary GROUP BY / aggregate queries or a caller-supplied time-window
-- parameter -- it only does filters and foreign-key joins. Every one of
-- these needs a time window, so they're RPC functions, not plain tables
-- or views (a view can't take a parameter).
--
-- SECURITY INVOKER, always -- never DEFINER. A SECURITY DEFINER function
-- runs with the OWNER's privileges (typically a superuser-ish role that
-- owns the tables), which would silently bypass RLS entirely for every
-- table the function touches, regardless of who's allowed to call the
-- function itself. INVOKER means the function runs as whatever role
-- actually called it (`anon`, via the frontend's anon key) -- so RLS
-- applies inside the function body exactly as if `anon` had run the
-- query directly. Verified, not just asserted: see
-- db/tests/landing_functions_test.sql, which proves this with a direct
-- comparison -- an invoker test function reading catalog_run (RLS
-- enabled, zero policies, so even anon-with-full-grants sees 0 rows) vs.
-- a security-definer version of the identical query, which sees the
-- real row count. That's the concrete failure mode INVOKER prevents.
--
-- EXECUTE is explicitly revoked from PUBLIC and re-granted to `anon`
-- only, on every function below -- never left on Postgres's default
-- EXECUTE-TO-PUBLIC grant. Matches db/rls_policies.sql's existing
-- explicit-grant posture for tables; a function is just as much a way
-- to reach table data as a SELECT is.
--
-- IMPORTANT, learned the hard way in Phase 5: `revoke ... from public`
-- is NOT the whole story on Supabase. Postgres's built-in PUBLIC
-- pseudo-role default is a separate mechanism from Supabase's OWN
-- per-role `ALTER DEFAULT PRIVILEGES`, which auto-grants EXECUTE
-- directly to `anon`, `authenticated`, AND `service_role` individually
-- on every new function in the `public` schema -- confirmed by reading
-- `pg_default_acl` directly, not assumed. Revoking from PUBLIC does
-- NOT touch these three roles' own separate grants. Real consequence:
-- every function below originally had `authenticated` and
-- `service_role` silently holding EXECUTE despite this comment's claim
-- of explicit-only grants -- harmless here in practice (all are
-- SECURITY INVOKER + RLS-gated, `authenticated` is unreachable since
-- this app has no auth, `service_role` is never shipped to the
-- frontend), but for `trigger_github_workflow()` below (SECURITY
-- DEFINER, touches a Vault-stored secret) the same silent
-- `anon`-has-EXECUTE default was a genuine live risk, caught only by
-- reading `pg_proc.proacl` directly after creating it, not by trusting
-- the `revoke ... from public` line to have been sufficient. Fixed
-- retroactively for every function (see the grant-hygiene block after
-- the Phase 5 functions below) and going forward via `ALTER DEFAULT
-- PRIVILEGES FOR ROLE postgres ... REVOKE EXECUTE ... FROM
-- authenticated, service_role` -- `anon`'s default grant is
-- deliberately left alone, since every function in this file is meant
-- for `anon` anyway. The per-function `revoke ... from public` /
-- `grant ... to anon` pattern below is still required for new
-- functions (PUBLIC's own default is untouched by the ALTER DEFAULT
-- PRIVILEGES fix), just no longer silently leaking to authenticated/
-- service_role too.
--
-- All take `p_since timestamptz` -- NULL means unbounded ("All time"),
-- otherwise only execution rows with started_at >= p_since count. All
-- STABLE (pure reads, result depends only on arguments + current table
-- contents within one statement).
-- =========================================================================

-- Global page subtitle (<N> tracked, <M> working) and the landing page's
-- "Models Available" KPI, which the design doc defines as the exact same
-- window-based distinct-count -- one function, two consumers.
create or replace function landing_subtitle_counts(p_since timestamptz)
returns table(tracked bigint, working bigint)
language sql stable security invoker
as $$
  select
    (select count(*) from model) as tracked,
    (select count(distinct r.model_slug)
     from result r
     join execution e on e.id = r.execution_id
     where r.success = true
       and (p_since is null or e.started_at >= p_since)) as working;
$$;

revoke execute on function landing_subtitle_counts(timestamptz) from public;
grant execute on function landing_subtitle_counts(timestamptz) to anon;

-- Best Response / Best Throughput KPIs, model + provider shown per
-- design doc. Combined into one round trip via a full outer join on
-- two independent 0-or-1-row subqueries -- if one side has no
-- successes in-window at all, the other side's values still come back
-- rather than the whole row disappearing.
create or replace function landing_kpis(p_since timestamptz)
returns table(
  best_response_model_slug text,
  best_response_provider text,
  best_response_time_s numeric,
  best_throughput_model_slug text,
  best_throughput_provider text,
  best_throughput_tok_s numeric
)
language sql stable security invoker
as $$
  select
    br.model_slug, br.provider, br.response_time_s,
    bt.model_slug, bt.provider, bt.tokens_per_sec
  from
    (select r.model_slug, m.provider, r.response_time_s
     from result r
     join execution e on e.id = r.execution_id
     join model m on m.slug = r.model_slug
     where r.success = true and (p_since is null or e.started_at >= p_since)
     order by r.response_time_s asc
     limit 1) br
  full outer join
    (select r.model_slug, m.provider, r.tokens_per_sec
     from result r
     join execution e on e.id = r.execution_id
     join model m on m.slug = r.model_slug
     where r.success = true and (p_since is null or e.started_at >= p_since)
     order by r.tokens_per_sec desc
     limit 1) bt
  on true;
$$;

revoke execute on function landing_kpis(timestamptz) from public;
grant execute on function landing_kpis(timestamptz) to anon;

-- "Models Available Over Time, by Provider" -- the one query the schema
-- check in design_decisions.md called out as needing a heavier live
-- query (Result joined to Model, grouped by provider, per execution).
-- "Models Available Over Time" (the overall, non-provider-split trend)
-- deliberately has NO function -- it's a direct, unfiltered-by-join read
-- of execution.started_at/models_succeeded_count, which PostgREST can
-- do natively without an RPC.
create or replace function landing_availability_by_provider(p_since timestamptz)
returns table(started_at timestamptz, provider text, succeeded_count bigint)
language sql stable security invoker
as $$
  select e.started_at, m.provider, count(*) as succeeded_count
  from result r
  join execution e on e.id = r.execution_id
  join model m on m.slug = r.model_slug
  where r.success = true
    and (p_since is null or e.started_at >= p_since)
  group by e.started_at, m.provider
  order by e.started_at asc, m.provider asc;
$$;

revoke execute on function landing_availability_by_provider(timestamptz) from public;
grant execute on function landing_availability_by_provider(timestamptz) to anon;

-- Top 5 Fastest / Top 5 Throughput tables.
create or replace function landing_top5_fastest(p_since timestamptz)
returns table(model_slug text, provider text, model_name text, best_response_time_s numeric)
language sql stable security invoker
as $$
  select r.model_slug, m.provider, m.model_name, min(r.response_time_s) as best_response_time_s
  from result r
  join execution e on e.id = r.execution_id
  join model m on m.slug = r.model_slug
  where r.success = true
    and (p_since is null or e.started_at >= p_since)
  group by r.model_slug, m.provider, m.model_name
  order by best_response_time_s asc
  limit 5;
$$;

revoke execute on function landing_top5_fastest(timestamptz) from public;
grant execute on function landing_top5_fastest(timestamptz) to anon;

create or replace function landing_top5_throughput(p_since timestamptz)
returns table(model_slug text, provider text, model_name text, best_tokens_per_sec numeric)
language sql stable security invoker
as $$
  select r.model_slug, m.provider, m.model_name, max(r.tokens_per_sec) as best_tokens_per_sec
  from result r
  join execution e on e.id = r.execution_id
  join model m on m.slug = r.model_slug
  where r.success = true
    and (p_since is null or e.started_at >= p_since)
  group by r.model_slug, m.provider, m.model_name
  order by best_tokens_per_sec desc
  limit 5;
$$;

revoke execute on function landing_top5_throughput(timestamptz) from public;
grant execute on function landing_top5_throughput(timestamptz) to anon;

-- =========================================================================
-- MODELS PAGE + MODEL DETAIL PAGE AGGREGATE FUNCTIONS (Phase 5)
--
-- Same posture as the landing functions above: SECURITY INVOKER always
-- (RLS applies as if `anon` ran the query directly), EXECUTE explicitly
-- revoked from PUBLIC and re-granted to anon only, `p_since timestamptz`
-- with NULL meaning unbounded.
--
-- Two recurring patterns specific to this phase, used throughout:
--
-- 1. "Seen at least once" (model.last_seen_working_at is not null) is an
--    ALL-TIME condition, never intersected with p_since -- a model that
--    worked last month must still appear in the Models table (with null
--    metrics) even if the selected window is "Last hour" and it has zero
--    activity in it. This is why every function below that filters models
--    on last_seen_working_at LEFT JOINs to result/execution unconditionally
--    and pushes the p_since check into each aggregate's own FILTER clause,
--    rather than a WHERE/JOIN-condition window filter -- the latter would
--    silently drop a model with zero in-window rows from the GROUP BY
--    entirely instead of returning it with nulls. Caught by
--    models_and_detail_functions_test.sql's "model seen all-time but no
--    activity in the selected window" case before this shipped, not
--    discovered after.
--
-- 2. A model's Available/Removed/Degraded STATE is always computed via
--    model_state_as_of(slug, now()) -- i.e. live, "as of right now" --
--    independent of p_since. Only the numeric metrics (avg/best/uptime%)
--    are scoped to the selected window. Deliberate: flipping the
--    time-range dropdown should never make a model's health badge
--    flicker between states, only change the historical numbers next to
--    it. Approved explicitly during Phase 5 planning (see conversation
--    history / commit message), not the only defensible reading of the
--    design doc.
-- =========================================================================

-- Models table: one row per "seen at least once" model, aggregated over
-- the selected window. AVG/BEST/THROUGHPUT = avg/min/max, matching the
-- design doc's explicit "AVG/MIN/MAX, same pattern as the landing page's
-- Top 5 tables" note. UPTIME% is null (not 0) when the model has zero
-- tested (non-excluded_non_text) results in the window, so the frontend
-- can render "--" instead of a misleading 0%.
create or replace function models_table_summary(p_since timestamptz)
returns table(
  model_slug text,
  provider text,
  model_name text,
  state text,
  avg_response_time_s numeric,
  best_response_time_s numeric,
  best_tokens_per_sec numeric,
  uptime_pct numeric
)
language sql stable security invoker
as $$
  select
    m.slug,
    m.provider,
    m.model_name,
    model_state_as_of(m.slug, now()) as state,
    avg(r.response_time_s) filter (
      where r.success and (p_since is null or e.started_at >= p_since)
    ) as avg_response_time_s,
    min(r.response_time_s) filter (
      where r.success and (p_since is null or e.started_at >= p_since)
    ) as best_response_time_s,
    max(r.tokens_per_sec) filter (
      where r.success and (p_since is null or e.started_at >= p_since)
    ) as best_tokens_per_sec,
    case when count(r.id) filter (
           where r.resolution != 'excluded_non_text' and (p_since is null or e.started_at >= p_since)
         ) > 0
      then round(
        100.0 * count(r.id) filter (
          where r.success and r.resolution != 'excluded_non_text' and (p_since is null or e.started_at >= p_since)
        ) / count(r.id) filter (
          where r.resolution != 'excluded_non_text' and (p_since is null or e.started_at >= p_since)
        ), 1)
      else null
    end as uptime_pct
  from model m
  left join result r on r.model_slug = m.slug
  left join execution e on e.id = r.execution_id
  where m.last_seen_working_at is not null
  group by m.slug, m.provider, m.model_name;
$$;

revoke execute on function models_table_summary(timestamptz) from public;
grant execute on function models_table_summary(timestamptz) to anon;

-- One grouped query for every model's TREND sparkline data at once
-- (response-time trend, not availability -- deliberately a different
-- signal from the landing page's chart, per the design doc). Same
-- "one query returning many rows, not N+1 per-row queries" shape already
-- accepted for the provider-trend chart and Top 5 tables. The frontend
-- groups these client-side by model_slug into each row's sparkline array.
create or replace function models_table_sparklines(p_since timestamptz)
returns table(model_slug text, started_at timestamptz, response_time_s numeric)
language sql stable security invoker
as $$
  select r.model_slug, e.started_at, r.response_time_s
  from result r
  join execution e on e.id = r.execution_id
  where r.success = true
    and (p_since is null or e.started_at >= p_since)
  order by r.model_slug, e.started_at asc;
$$;

revoke execute on function models_table_sparklines(timestamptz) from public;
grant execute on function models_table_sparklines(timestamptz) to anon;

-- Model detail page's model-selector dropdown. Per the design doc, this
-- list is "seen at least once" WITHIN the current filter window --
-- deliberately different from the Models table's all-time rule (point 1
-- above): a model that only ever worked last month shouldn't be
-- selectable while the window is "Last hour", since its detail page
-- would just show empty charts.
create or replace function model_selector_options(p_since timestamptz)
returns table(model_slug text, provider text, model_name text)
language sql stable security invoker
as $$
  select distinct m.slug, m.provider, m.model_name
  from model m
  join result r on r.model_slug = m.slug
  join execution e on e.id = r.execution_id
  where r.success = true
    and (p_since is null or e.started_at >= p_since)
  order by m.provider, m.model_name;
$$;

revoke execute on function model_selector_options(timestamptz) from public;
grant execute on function model_selector_options(timestamptz) to anon;

-- Model detail KPI boxes: UPTIME (%, tested_count/success_count),
-- AVG RESPONSE, BEST RESPONSE, AVG THROUGHPUT. Note AVG THROUGHPUT here
-- vs. the Models table's best/MAX throughput column -- the two pages
-- deliberately use different aggregations of the same field, per the
-- design doc's own wording for each page. STATE is live (point 2 above);
-- the rest is scoped to p_since. A single bare aggregate (no GROUP BY),
-- so it always returns exactly one row, all nulls if there's no in-window
-- data for this model -- never zero rows.
create or replace function model_detail_kpis(p_slug text, p_since timestamptz)
returns table(
  state text,
  tested_count bigint,
  success_count bigint,
  uptime_pct numeric,
  avg_response_time_s numeric,
  best_response_time_s numeric,
  avg_tokens_per_sec numeric
)
language sql stable security invoker
as $$
  select
    model_state_as_of(p_slug, now()) as state,
    count(r.id) filter (where r.resolution != 'excluded_non_text') as tested_count,
    count(r.id) filter (where r.success and r.resolution != 'excluded_non_text') as success_count,
    case when count(r.id) filter (where r.resolution != 'excluded_non_text') > 0
      then round(100.0 * count(r.id) filter (where r.success and r.resolution != 'excluded_non_text')
                 / count(r.id) filter (where r.resolution != 'excluded_non_text'), 1)
      else null
    end as uptime_pct,
    avg(r.response_time_s) filter (where r.success) as avg_response_time_s,
    min(r.response_time_s) filter (where r.success) as best_response_time_s,
    avg(r.tokens_per_sec) filter (where r.success) as avg_tokens_per_sec
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and (p_since is null or e.started_at >= p_since);
$$;

revoke execute on function model_detail_kpis(text, timestamptz) from public;
grant execute on function model_detail_kpis(text, timestamptz) to anon;

-- "Performance vs Global Average" comparison. Deliberately the average
-- of each model's OWN uptime%/avg-response/avg-throughput, not one
-- pooled ratio across all results -- a pooled ratio would let
-- high-volume models dominate the "global average" disproportionately,
-- which isn't what "vs. the average model" should mean.
create or replace function model_detail_global_avg(p_since timestamptz)
returns table(
  avg_uptime_pct numeric,
  avg_response_time_s numeric,
  avg_tokens_per_sec numeric
)
language sql stable security invoker
as $$
  with per_model as (
    select
      case when count(r.id) filter (
             where r.resolution != 'excluded_non_text' and (p_since is null or e.started_at >= p_since)
           ) > 0
        then 100.0 * count(r.id) filter (
               where r.success and r.resolution != 'excluded_non_text' and (p_since is null or e.started_at >= p_since)
             ) / count(r.id) filter (
               where r.resolution != 'excluded_non_text' and (p_since is null or e.started_at >= p_since)
             )
        else null
      end as uptime_pct,
      avg(r.response_time_s) filter (
        where r.success and (p_since is null or e.started_at >= p_since)
      ) as avg_response_time_s,
      avg(r.tokens_per_sec) filter (
        where r.success and (p_since is null or e.started_at >= p_since)
      ) as avg_tokens_per_sec
    from model m
    left join result r on r.model_slug = m.slug
    left join execution e on e.id = r.execution_id
    where m.last_seen_working_at is not null
    group by m.slug
  )
  select round(avg(uptime_pct), 1), avg(avg_response_time_s), avg(avg_tokens_per_sec)
  from per_model;
$$;

revoke execute on function model_detail_global_avg(timestamptz) from public;
grant execute on function model_detail_global_avg(timestamptz) to anon;

-- Capability Radar normalization basis. The radar's three axes
-- (Reliability/Avg Response/Avg Throughput) have incompatible raw scales
-- and directions (a 0-100 percentage vs. seconds-lower-is-better vs.
-- tokens/sec-higher-is-better) -- this returns the best AVG response
-- time and best AVG throughput achieved by any seen-at-least-once model
-- in the window, so the frontend can normalize a single model's own
-- avg-response/avg-throughput to a comparable 0-100 scale (best model in
-- class = 100, capped there). Reliability needs no bounds, already 0-100.
create or replace function model_detail_radar_bounds(p_since timestamptz)
returns table(best_avg_response_time_s numeric, best_avg_tokens_per_sec numeric)
language sql stable security invoker
as $$
  with per_model as (
    select
      avg(r.response_time_s) filter (
        where r.success and (p_since is null or e.started_at >= p_since)
      ) as avg_response_time_s,
      avg(r.tokens_per_sec) filter (
        where r.success and (p_since is null or e.started_at >= p_since)
      ) as avg_tokens_per_sec
    from model m
    left join result r on r.model_slug = m.slug
    left join execution e on e.id = r.execution_id
    where m.last_seen_working_at is not null
    group by m.slug
  )
  select min(avg_response_time_s), max(avg_tokens_per_sec) from per_model;
$$;

revoke execute on function model_detail_radar_bounds(timestamptz) from public;
grant execute on function model_detail_radar_bounds(timestamptz) to anon;

-- Error Breakdown donut. Failure-only slices using the full validated
-- taxonomy -- NIMStats' original only had two buckets (Timeout,
-- Connection Closed), the exact collapse this whole project fixes.
-- excluded_non_text rows are never counted as errors here, consistent
-- with every other consumer of the taxonomy.
create or replace function model_detail_error_breakdown(p_slug text, p_since timestamptz)
returns table(error_category text, error_count bigint)
language sql stable security invoker
as $$
  select r.error_category, count(*) as error_count
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and r.success = false
    and r.resolution != 'excluded_non_text'
    and (p_since is null or e.started_at >= p_since)
  group by r.error_category
  order by error_count desc;
$$;

revoke execute on function model_detail_error_breakdown(text, timestamptz) from public;
grant execute on function model_detail_error_breakdown(text, timestamptz) to anon;

-- Response Time History -- same per-model time-series shape as the
-- Models table's sparkline, unaggregated, single model, full window.
create or replace function model_detail_response_time_history(p_slug text, p_since timestamptz)
returns table(started_at timestamptz, response_time_s numeric)
language sql stable security invoker
as $$
  select e.started_at, r.response_time_s
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and r.success = true
    and (p_since is null or e.started_at >= p_since)
  order by e.started_at asc;
$$;

revoke execute on function model_detail_response_time_history(text, timestamptz) from public;
grant execute on function model_detail_response_time_history(text, timestamptz) to anon;

-- Run History (last 20). Deliberately ignores p_since entirely -- per
-- the design doc, NIMStats' separate "RUNS LIMIT: 30/50/100/All" control
-- is replaced by the shared time filter for everything ELSE on this
-- page, but Run History keeps its own fixed "last 20" windowing so it
-- never goes empty just because a short time range (e.g. "Last hour")
-- is selected. Includes response_text/error_body directly -- this is the
-- data source for the "view response" modal, no separate lookup needed.
create or replace function model_detail_run_history(p_slug text)
returns table(
  execution_id uuid,
  started_at timestamptz,
  success boolean,
  error_category text,
  response_time_s numeric,
  tokens_per_sec numeric,
  response_text text,
  error_body text
)
language sql stable security invoker
as $$
  select e.id, e.started_at, r.success, r.error_category, r.response_time_s, r.tokens_per_sec, r.response_text, r.error_body
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and r.resolution != 'excluded_non_text'
  order by e.started_at desc
  limit 20;
$$;

revoke execute on function model_detail_run_history(text) from public;
grant execute on function model_detail_run_history(text) to anon;

-- Availability Heatmap: one cell per execution where this model was
-- actually tested (INNER JOIN result on this model_slug -- an execution
-- before this model was discovered correctly produces no cell at all,
-- rather than a spurious "removed" one), state via the same
-- model_state_as_of() used everywhere else, evaluated "as of" that
-- execution's own started_at -- the one consumer that actually needs
-- the "state at time T" shape model_state_as_of was designed for, not
-- just "state right now".
create or replace function model_detail_availability_heatmap(p_slug text, p_since timestamptz)
returns table(started_at timestamptz, state text)
language sql stable security invoker
as $$
  select e.started_at, model_state_as_of(p_slug, e.started_at) as state
  from execution e
  join result r on r.execution_id = e.id and r.model_slug = p_slug
  where (p_since is null or e.started_at >= p_since)
  order by e.started_at asc;
$$;

revoke execute on function model_detail_availability_heatmap(text, timestamptz) from public;
grant execute on function model_detail_availability_heatmap(text, timestamptz) to anon;

-- =========================================================================
-- GRANT HYGIENE FIX (retroactive) -- Phase 5, applied after discovering
-- the ALTER DEFAULT PRIVILEGES gap explained in the long comment above
-- the landing functions. Every RPC function created before this point
-- silently had `authenticated` and `service_role` holding EXECUTE via
-- Supabase's own default-privilege mechanism, never actually granted
-- by any `grant ... to` line in this file. Explicit revoke here for
-- every existing function, then a standing fix so this stops
-- recurring for every function written after this point.
-- =========================================================================

revoke execute on function landing_availability_by_provider(timestamptz) from authenticated, service_role;
revoke execute on function landing_kpis(timestamptz) from authenticated, service_role;
revoke execute on function landing_subtitle_counts(timestamptz) from authenticated, service_role;
revoke execute on function landing_top5_fastest(timestamptz) from authenticated, service_role;
revoke execute on function landing_top5_throughput(timestamptz) from authenticated, service_role;
revoke execute on function model_detail_availability_heatmap(text, timestamptz) from authenticated, service_role;
revoke execute on function model_detail_error_breakdown(text, timestamptz) from authenticated, service_role;
revoke execute on function model_detail_global_avg(timestamptz) from authenticated, service_role;
revoke execute on function model_detail_kpis(text, timestamptz) from authenticated, service_role;
revoke execute on function model_detail_radar_bounds(timestamptz) from authenticated, service_role;
revoke execute on function model_detail_response_time_history(text, timestamptz) from authenticated, service_role;
revoke execute on function model_detail_run_history(text) from authenticated, service_role;
revoke execute on function model_selector_options(timestamptz) from authenticated, service_role;
revoke execute on function model_state_as_of(text, timestamptz) from authenticated, service_role;
revoke execute on function models_table_sparklines(timestamptz) from authenticated, service_role;
revoke execute on function models_table_summary(timestamptz) from authenticated, service_role;

-- Going forward: stop Supabase's per-role default-privilege auto-grant
-- to authenticated/service_role for functions WE create (role
-- postgres, the role this schema is always applied as). anon's own
-- default grant is deliberately left untouched -- every function in
-- this file is meant for anon anyway, so that default is actually
-- convenient and correct, not a hole. PUBLIC's own separate default
-- (a genuinely different mechanism, see the long comment above) is
-- untouched by this statement -- the per-function `revoke ... from
-- public` pattern is still required for every new function.
alter default privileges for role postgres in schema public
  revoke execute on functions from authenticated, service_role;
