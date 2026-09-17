-- Phase 5: Models-table and model-detail-page aggregate RPC functions.
-- See db/schema.sql for the full rationale comments -- this file
-- mirrors that content exactly. Verified locally via Docker Postgres +
-- db/tests/models_and_detail_functions_test.sql before this migration
-- was created (see CLAUDE.md, Hard rules).

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
