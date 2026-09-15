-- Unit-test-style scenarios for model_state_as_of(), per Phase 1 of
-- NIMTracker-implementation-plan.md ("Harden model_state_as_of()").
--
-- Run against a real Postgres instance with schema.sql already applied.
-- Wrapped in a transaction and rolled back at the end -- safe to run
-- against a scratch/local database repeatedly. NEVER run this against
-- the real Supabase project without explicit confirmation first (see
-- CLAUDE.md, Hard rules) -- it's a verification tool, not something
-- that needs to touch production data, and rollback is not a substitute
-- for that confirmation if it's ever pointed at a live connection string.

begin;

-- Fixed reference point instead of now() -- keeps every scenario
-- deterministic regardless of when this is actually run.

-- ---------------------------------------------------------------------
-- Scenario 1: model with only successes, most recent result a success
-- even though an earlier failure exists -- expect 'available'.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name) values
  ('test/only-successes', 'Test', 'only-successes');

insert into execution (id, started_at, models_tested_count, models_succeeded_count)
values
  ('11111111-1111-1111-1111-111111111101', '2026-09-15 12:00:00+00'::timestamptz - interval '3 hours', 1, 0),
  ('11111111-1111-1111-1111-111111111102', '2026-09-15 12:00:00+00'::timestamptz - interval '1 hour',  1, 1);

insert into result (execution_id, model_slug, success, resolution, error_category) values
  ('11111111-1111-1111-1111-111111111101', 'test/only-successes', false, 'counted_error', 'timeout'),
  ('11111111-1111-1111-1111-111111111102', 'test/only-successes', true,  'counted_working', null);

do $$
declare v_state text;
begin
  select model_state_as_of('test/only-successes', '2026-09-15 12:00:00+00'::timestamptz) into v_state;
  if v_state != 'available' then
    raise exception 'Scenario 1 (only-successes) FAILED: expected available, got %', v_state;
  end if;
  raise notice 'Scenario 1 (only-successes): PASS (available)';
end $$;

-- ---------------------------------------------------------------------
-- Scenario 2: explicit 410 -- delisted_at set, before p_as_of. Overrides
-- everything else regardless of result history.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name, delisted_at, delisted_reason) values
  ('test/explicit-410', 'Test', 'explicit-410', '2026-09-15 12:00:00+00'::timestamptz - interval '1 hour', 'NVIDIA end-of-life notice');

insert into execution (id, started_at, models_tested_count, models_succeeded_count)
values ('11111111-1111-1111-1111-111111111103', '2026-09-15 12:00:00+00'::timestamptz - interval '2 hours', 1, 1);

insert into result (execution_id, model_slug, success, resolution, error_category) values
  ('11111111-1111-1111-1111-111111111103', 'test/explicit-410', true, 'counted_working', null);

do $$
declare v_state text;
begin
  select model_state_as_of('test/explicit-410', '2026-09-15 12:00:00+00'::timestamptz) into v_state;
  if v_state != 'removed' then
    raise exception 'Scenario 2 (explicit-410) FAILED: expected removed, got %', v_state;
  end if;
  raise notice 'Scenario 2 (explicit-410): PASS (removed)';
end $$;

-- ---------------------------------------------------------------------
-- Scenario 3: intermittent failures, last success INSIDE the 24h window
-- (20h before p_as_of) -- expect 'degraded', not 'removed'.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name) values
  ('test/degraded-inside-24h', 'Test', 'degraded-inside-24h');

insert into execution (id, started_at, models_tested_count, models_succeeded_count)
values
  ('11111111-1111-1111-1111-111111111104', '2026-09-15 12:00:00+00'::timestamptz - interval '20 hours', 1, 1),
  ('11111111-1111-1111-1111-111111111105', '2026-09-15 12:00:00+00'::timestamptz - interval '10 hours', 1, 0),
  ('11111111-1111-1111-1111-111111111106', '2026-09-15 12:00:00+00'::timestamptz - interval '1 hour',   1, 0);

insert into result (execution_id, model_slug, success, resolution, error_category) values
  ('11111111-1111-1111-1111-111111111104', 'test/degraded-inside-24h', true,  'counted_working', null),
  ('11111111-1111-1111-1111-111111111105', 'test/degraded-inside-24h', false, 'counted_error', 'server_error'),
  ('11111111-1111-1111-1111-111111111106', 'test/degraded-inside-24h', false, 'counted_error', 'timeout');

do $$
declare v_state text;
begin
  select model_state_as_of('test/degraded-inside-24h', '2026-09-15 12:00:00+00'::timestamptz) into v_state;
  if v_state != 'degraded' then
    raise exception 'Scenario 3 (degraded-inside-24h) FAILED: expected degraded, got %', v_state;
  end if;
  raise notice 'Scenario 3 (degraded-inside-24h): PASS (degraded)';
end $$;

-- ---------------------------------------------------------------------
-- Scenario 4: intermittent failures, last success OUTSIDE the 24h window
-- (30h before p_as_of) -- expect 'removed', not 'degraded'.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name) values
  ('test/removed-outside-24h', 'Test', 'removed-outside-24h');

insert into execution (id, started_at, models_tested_count, models_succeeded_count)
values
  ('11111111-1111-1111-1111-111111111107', '2026-09-15 12:00:00+00'::timestamptz - interval '30 hours', 1, 1),
  ('11111111-1111-1111-1111-111111111108', '2026-09-15 12:00:00+00'::timestamptz - interval '10 hours', 1, 0),
  ('11111111-1111-1111-1111-111111111109', '2026-09-15 12:00:00+00'::timestamptz - interval '1 hour',   1, 0);

insert into result (execution_id, model_slug, success, resolution, error_category) values
  ('11111111-1111-1111-1111-111111111107', 'test/removed-outside-24h', true,  'counted_working', null),
  ('11111111-1111-1111-1111-111111111108', 'test/removed-outside-24h', false, 'counted_error', 'server_error'),
  ('11111111-1111-1111-1111-111111111109', 'test/removed-outside-24h', false, 'counted_error', 'timeout');

do $$
declare v_state text;
begin
  select model_state_as_of('test/removed-outside-24h', '2026-09-15 12:00:00+00'::timestamptz) into v_state;
  if v_state != 'removed' then
    raise exception 'Scenario 4 (removed-outside-24h) FAILED: expected removed, got %', v_state;
  end if;
  raise notice 'Scenario 4 (removed-outside-24h): PASS (removed)';
end $$;

-- ---------------------------------------------------------------------
-- Scenario 5: no results at all -- expect 'unknown'.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name) values
  ('test/no-results', 'Test', 'no-results');

do $$
declare v_state text;
begin
  select model_state_as_of('test/no-results', '2026-09-15 12:00:00+00'::timestamptz) into v_state;
  if v_state != 'unknown' then
    raise exception 'Scenario 5 (no-results) FAILED: expected unknown, got %', v_state;
  end if;
  raise notice 'Scenario 5 (no-results): PASS (unknown)';
end $$;

-- ---------------------------------------------------------------------
-- Scenario 6 (bonus, not in the original plan list but implied by the
-- function body): a model whose only result is excluded_non_text must
-- be treated the same as no results at all -- expect 'unknown', not
-- 'available' or 'removed'. Verifies the resolution filter actually
-- takes effect, not just that it's present in the WHERE clause.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name) values
  ('test/only-excluded-non-text', 'Test', 'only-excluded-non-text');

insert into execution (id, started_at, models_tested_count, models_succeeded_count)
values ('11111111-1111-1111-1111-111111111110', '2026-09-15 12:00:00+00'::timestamptz - interval '1 hour', 0, 0);

insert into result (execution_id, model_slug, success, resolution, error_category) values
  ('11111111-1111-1111-1111-111111111110', 'test/only-excluded-non-text', false, 'excluded_non_text', null);

do $$
declare v_state text;
begin
  select model_state_as_of('test/only-excluded-non-text', '2026-09-15 12:00:00+00'::timestamptz) into v_state;
  if v_state != 'unknown' then
    raise exception 'Scenario 6 (only-excluded-non-text) FAILED: expected unknown, got %', v_state;
  end if;
  raise notice 'Scenario 6 (only-excluded-non-text): PASS (unknown)';
end $$;

-- ---------------------------------------------------------------------
-- Scenario 7 (bonus): "as of" a point in time BEFORE a model's only
-- success -- exercises the heatmap's actual requirement (state as of an
-- arbitrary past timestamp, not just "now"). Expect 'unknown' at a point
-- before any result exists, then 'available' afterward.
-- ---------------------------------------------------------------------
insert into model (slug, provider, model_name) values
  ('test/as-of-point-in-time', 'Test', 'as-of-point-in-time');

insert into execution (id, started_at, models_tested_count, models_succeeded_count)
values ('11111111-1111-1111-1111-111111111111', '2026-09-15 12:00:00+00'::timestamptz - interval '5 hours', 1, 1);

insert into result (execution_id, model_slug, success, resolution, error_category) values
  ('11111111-1111-1111-1111-111111111111', 'test/as-of-point-in-time', true, 'counted_working', null);

do $$
declare v_state_before text;
declare v_state_after text;
begin
  select model_state_as_of('test/as-of-point-in-time', '2026-09-15 12:00:00+00'::timestamptz - interval '10 hours') into v_state_before;
  select model_state_as_of('test/as-of-point-in-time', '2026-09-15 12:00:00+00'::timestamptz) into v_state_after;
  if v_state_before != 'unknown' then
    raise exception 'Scenario 7 (as-of-point-in-time, before) FAILED: expected unknown, got %', v_state_before;
  end if;
  if v_state_after != 'available' then
    raise exception 'Scenario 7 (as-of-point-in-time, after) FAILED: expected available, got %', v_state_after;
  end if;
  raise notice 'Scenario 7 (as-of-point-in-time): PASS (unknown before, available after)';
end $$;

do $$
begin
  raise notice 'All model_state_as_of() scenarios passed.';
end $$;

rollback;
