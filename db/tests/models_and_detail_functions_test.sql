-- Verification for the Phase 5 Models-table and model-detail-page RPC
-- functions. Same discipline as landing_functions_test.sql: proves every
-- function is SECURITY INVOKER with an explicit anon EXECUTE grant (not
-- relying on default-to-PUBLIC), and specifically exercises the "model
-- seen at least once, all-time, but zero activity in the selected
-- window" scenario -- the case that would silently vanish a model from
-- models_table_summary/model_detail_global_avg/model_detail_radar_bounds
-- if the window filter were a WHERE/JOIN-condition instead of a FILTER
-- clause (see the comment above these functions in db/schema.sql).
--
-- Run against a real Postgres instance with schema.sql already applied.
-- Wrapped in a transaction and rolled back at the end. NEVER run this
-- against the real Supabase project without explicit confirmation first
-- (see CLAUDE.md, Hard rules).

begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'test_no_grants') then
    create role test_no_grants;
  end if;
end $$;

grant usage on schema public to anon;
grant select, insert, update, delete on model, execution, result, catalog_run to anon;

-- Model A: seen at least once, has one successful in-window result plus
-- one failure -- exercises the normal aggregate path for every function.
insert into model (slug, provider, model_name, api_model_id, api_model_id_source, last_seen_working_at) values
  ('test/alpha', 'TestCo', 'alpha', 'test/alpha', 'scraped_snippet', now() - interval '1 hour');

-- Model B: seen at least once (last_seen_working_at set from an old,
-- now-out-of-window success), but its only Result rows in the DB predate
-- the selected window entirely -- must still appear in
-- models_table_summary with null metrics, not vanish.
insert into model (slug, provider, model_name, api_model_id, api_model_id_source, last_seen_working_at) values
  ('test/beta', 'TestCo', 'beta', 'test/beta', 'scraped_snippet', now() - interval '10 days');

-- Model C: never seen (last_seen_working_at null) -- must never appear
-- in models_table_summary or model_selector_options at all.
insert into model (slug, provider, model_name, api_model_id, api_model_id_source) values
  ('test/gamma', 'TestCo', 'gamma', 'test/gamma', 'scraped_snippet');

insert into execution (id, started_at, models_tested_count, models_succeeded_count, fastest_model_slug, fastest_response_time_s) values
  ('11111111-1111-1111-1111-111111111201', now() - interval '1 hour', 2, 1, 'test/alpha', 2.0),
  ('11111111-1111-1111-1111-111111111202', now() - interval '30 minutes', 2, 0, null, null),
  ('11111111-1111-1111-1111-111111111203', now() - interval '10 days', 1, 1, 'test/beta', 3.0);

insert into result (execution_id, model_slug, success, error_category, resolution, response_time_s, completion_tokens, tokens_per_sec) values
  ('11111111-1111-1111-1111-111111111201', 'test/alpha', true, null, 'counted_working', 2.0, 100, 50.0),
  ('11111111-1111-1111-1111-111111111202', 'test/alpha', false, 'timeout', 'counted_error', null, null, null),
  ('11111111-1111-1111-1111-111111111203', 'test/beta', true, null, 'counted_working', 3.0, 100, 40.0);

set role anon;

-- ---------------------------------------------------------------------
-- models_table_summary: model A (in-window activity), model B (seen
-- all-time, zero in-window activity -- must appear with nulls), model C
-- (never seen -- must not appear).
-- ---------------------------------------------------------------------
do $$
declare
  v_count integer;
  v_alpha_uptime numeric;
  v_alpha_state text;
  v_beta_avg numeric;
  v_beta_uptime numeric;
begin
  select count(*) into v_count from models_table_summary(now() - interval '2 hours');
  if v_count != 2 then
    raise exception 'models_table_summary FAILED: expected 2 rows (alpha, beta), got %', v_count;
  end if;

  select uptime_pct, state into v_alpha_uptime, v_alpha_state
  from models_table_summary(now() - interval '2 hours') where model_slug = 'test/alpha';
  if v_alpha_uptime != 50.0 then
    raise exception 'models_table_summary FAILED: expected alpha uptime_pct=50.0 (1 success / 2 tested), got %', v_alpha_uptime;
  end if;
  if v_alpha_state != 'degraded' then
    raise exception 'models_table_summary FAILED: expected alpha state=degraded (most recent result is a failure inside 24h), got %', v_alpha_state;
  end if;

  select avg_response_time_s, uptime_pct into v_beta_avg, v_beta_uptime
  from models_table_summary(now() - interval '2 hours') where model_slug = 'test/beta';
  if v_beta_avg is not null or v_beta_uptime is not null then
    raise exception 'models_table_summary FAILED: expected beta (seen all-time, zero in-window activity) to have null metrics, got avg=% uptime=%', v_beta_avg, v_beta_uptime;
  end if;

  raise notice 'anon EXECUTE models_table_summary: PASS (2 rows; alpha uptime=50.0/degraded; beta present with nulls; gamma correctly absent)';
end $$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from models_table_sparklines(now() - interval '2 hours');
  if v_count != 1 then
    raise exception 'models_table_sparklines FAILED: expected 1 successful in-window row, got %', v_count;
  end if;
  raise notice 'anon EXECUTE models_table_sparklines: PASS (1 row)';
end $$;

do $$
declare
  v_count integer;
begin
  -- window excludes beta's only success (10 days ago) -- beta must not
  -- be selectable in a window it has no activity in.
  select count(*) into v_count from model_selector_options(now() - interval '2 hours');
  if v_count != 1 then
    raise exception 'model_selector_options FAILED: expected 1 model (alpha only) in a 2h window, got %', v_count;
  end if;
  raise notice 'anon EXECUTE model_selector_options: PASS (1 row, alpha only)';
end $$;

do $$
declare
  v_tested bigint;
  v_success bigint;
  v_uptime numeric;
begin
  select tested_count, success_count, uptime_pct into v_tested, v_success, v_uptime
  from model_detail_kpis('test/alpha', now() - interval '2 hours');
  if v_tested != 2 or v_success != 1 or v_uptime != 50.0 then
    raise exception 'model_detail_kpis FAILED: expected tested=2 success=1 uptime=50.0, got tested=% success=% uptime=%', v_tested, v_success, v_uptime;
  end if;
  raise notice 'anon EXECUTE model_detail_kpis: PASS (tested=2, success=1, uptime=50.0)';
end $$;

do $$
declare
  v_row_count integer;
begin
  -- bare-aggregate function on a slug/window with zero matching rows
  -- must still return exactly one (all-null) row, never zero rows.
  select count(*) into v_row_count from model_detail_kpis('test/does-not-exist', now());
  if v_row_count != 1 then
    raise exception 'model_detail_kpis FAILED: expected exactly 1 row (nulls) for a slug/window with no data, got %', v_row_count;
  end if;
  raise notice 'model_detail_kpis always returns one row: PASS';
end $$;

do $$
declare
  v_avg_uptime numeric;
begin
  select avg_uptime_pct into v_avg_uptime from model_detail_global_avg(now() - interval '2 hours');
  if v_avg_uptime != 50.0 then
    raise exception 'model_detail_global_avg FAILED: expected 50.0 (only alpha has in-window data, its own uptime is 50.0), got %', v_avg_uptime;
  end if;
  raise notice 'anon EXECUTE model_detail_global_avg: PASS (avg_uptime_pct=50.0)';
end $$;

do $$
declare
  v_best_response numeric;
begin
  select best_avg_response_time_s into v_best_response from model_detail_radar_bounds(now() - interval '2 hours');
  if v_best_response != 2.0 then
    raise exception 'model_detail_radar_bounds FAILED: expected 2.0 (alpha only model with in-window data), got %', v_best_response;
  end if;
  raise notice 'anon EXECUTE model_detail_radar_bounds: PASS (best_avg_response_time_s=2.0)';
end $$;

do $$
declare
  v_category text;
  v_count bigint;
begin
  select error_category, error_count into v_category, v_count
  from model_detail_error_breakdown('test/alpha', now() - interval '2 hours');
  if v_category != 'timeout' or v_count != 1 then
    raise exception 'model_detail_error_breakdown FAILED: expected timeout/1, got %/%', v_category, v_count;
  end if;
  raise notice 'anon EXECUTE model_detail_error_breakdown: PASS (timeout=1)';
end $$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from model_detail_response_time_history('test/alpha', now() - interval '2 hours');
  if v_count != 1 then
    raise exception 'model_detail_response_time_history FAILED: expected 1 point, got %', v_count;
  end if;
  raise notice 'anon EXECUTE model_detail_response_time_history: PASS (1 point)';
end $$;

do $$
declare
  v_count integer;
begin
  -- deliberately no window arg -- run history ignores p_since entirely.
  select count(*) into v_count from model_detail_run_history('test/alpha');
  if v_count != 2 then
    raise exception 'model_detail_run_history FAILED: expected 2 rows (both alpha results, regardless of window), got %', v_count;
  end if;
  raise notice 'anon EXECUTE model_detail_run_history: PASS (2 rows)';
end $$;

do $$
declare
  v_count integer;
  v_state text;
begin
  select count(*) into v_count from model_detail_availability_heatmap('test/alpha', now() - interval '2 hours');
  if v_count != 2 then
    raise exception 'model_detail_availability_heatmap FAILED: expected 2 cells (one per execution alpha was tested in), got %', v_count;
  end if;
  select state into v_state from model_detail_availability_heatmap('test/alpha', now() - interval '2 hours') order by started_at desc limit 1;
  if v_state != 'degraded' then
    raise exception 'model_detail_availability_heatmap FAILED: expected most recent cell state=degraded, got %', v_state;
  end if;
  raise notice 'anon EXECUTE model_detail_availability_heatmap: PASS (2 cells, latest=degraded)';
end $$;

reset role;

-- ---------------------------------------------------------------------
-- REVOKE ... FROM PUBLIC actually restricts a role with no explicit
-- grant -- same check landing_functions_test.sql does, spot-checked on
-- one representative function here rather than repeated for all ten.
-- ---------------------------------------------------------------------
set role test_no_grants;

do $$
begin
  begin
    perform models_table_summary(null);
    raise exception 'test_no_grants EXECUTE models_table_summary FAILED: expected permission denied, call succeeded';
  exception
    when insufficient_privilege then
      raise notice 'test_no_grants EXECUTE models_table_summary: PASS (denied: %)', sqlerrm;
  end;
end $$;

reset role;

do $$
begin
  raise notice 'All Models-page/model-detail-page function scenarios passed.';
end $$;

rollback;
