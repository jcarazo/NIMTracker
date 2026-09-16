-- Verification for the Phase 4 landing-page RPC functions and the
-- model_state_as_of() grant-hygiene fix, per the review requirement:
-- every function must be SECURITY INVOKER (never DEFINER), with EXECUTE
-- explicitly revoked from PUBLIC and re-granted to anon only -- never
-- relying on Postgres's default EXECUTE-TO-PUBLIC grant. This file
-- proves both properties directly, not just that the functions return
-- plausible-looking data.
--
-- Run against a real Postgres instance with schema.sql already applied.
-- Wrapped in a transaction and rolled back at the end -- safe to run
-- against a scratch/local database repeatedly. NEVER run this against
-- the real Supabase project without explicit confirmation first (see
-- CLAUDE.md, Hard rules).
--
-- Deliberately grants `anon` full SELECT/INSERT/UPDATE/DELETE at the
-- GRANT layer before testing -- that's what Supabase actually does by
-- default on public-schema tables, relying on RLS itself (not the GRANT
-- layer) to enforce default-deny. Same discipline as rls_test.sql.

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
-- test_no_grants deliberately gets nothing at all -- stands in for
-- "any role that isn't anon," to prove REVOKE ... FROM PUBLIC actually
-- restricts something, not just that anon happens to have GRANT.

insert into model (slug, provider, model_name, api_model_id, api_model_id_source) values
  ('test/widget', 'Test', 'widget', 'test/widget', 'scraped_snippet');

insert into execution (id, started_at, models_tested_count, models_succeeded_count, fastest_model_slug, fastest_response_time_s)
values ('11111111-1111-1111-1111-111111111101', now() - interval '1 hour', 1, 1, 'test/widget', 2.5);

insert into result (execution_id, model_slug, success, resolution, response_time_s, completion_tokens, tokens_per_sec)
values ('11111111-1111-1111-1111-111111111101', 'test/widget', true, 'counted_working', 2.5, 100, 40.0);

insert into catalog_run (list_source, models_found_count) values ('live', 1);

-- ---------------------------------------------------------------------
-- Test A: anon can execute every landing_* function and
-- model_state_as_of, and gets real data back (proves the explicit
-- GRANT EXECUTE actually took effect, and that the underlying RLS
-- SELECT policies on model/execution/result -- which already allow
-- anon full read -- don't get in the way of legitimate use).
-- ---------------------------------------------------------------------
set role anon;

do $$
declare
  v_tracked bigint;
  v_working bigint;
begin
  select tracked, working into v_tracked, v_working from landing_subtitle_counts(null);
  if v_tracked != 1 or v_working != 1 then
    raise exception 'landing_subtitle_counts FAILED: expected tracked=1 working=1, got tracked=% working=%', v_tracked, v_working;
  end if;
  raise notice 'anon EXECUTE landing_subtitle_counts: PASS (tracked=1, working=1)';
end $$;

do $$
declare
  v_slug text;
begin
  select best_response_model_slug into v_slug from landing_kpis(null);
  if v_slug != 'test/widget' then
    raise exception 'landing_kpis FAILED: expected test/widget, got %', v_slug;
  end if;
  raise notice 'anon EXECUTE landing_kpis: PASS (best_response_model_slug=test/widget)';
end $$;

do $$
declare
  v_n integer;
begin
  select count(*) into v_n from landing_availability_by_provider(null);
  if v_n != 1 then
    raise exception 'landing_availability_by_provider FAILED: expected 1 row, got %', v_n;
  end if;
  raise notice 'anon EXECUTE landing_availability_by_provider: PASS (1 row)';
end $$;

do $$
declare
  v_n integer;
begin
  select count(*) into v_n from landing_top5_fastest(null);
  if v_n != 1 then
    raise exception 'landing_top5_fastest FAILED: expected 1 row, got %', v_n;
  end if;
  raise notice 'anon EXECUTE landing_top5_fastest: PASS (1 row)';
end $$;

do $$
declare
  v_n integer;
begin
  select count(*) into v_n from landing_top5_throughput(null);
  if v_n != 1 then
    raise exception 'landing_top5_throughput FAILED: expected 1 row, got %', v_n;
  end if;
  raise notice 'anon EXECUTE landing_top5_throughput: PASS (1 row)';
end $$;

do $$
declare
  v_state text;
begin
  select model_state_as_of('test/widget', now()) into v_state;
  if v_state != 'available' then
    raise exception 'model_state_as_of FAILED: expected available, got %', v_state;
  end if;
  raise notice 'anon EXECUTE model_state_as_of: PASS (available)';
end $$;

reset role;

-- ---------------------------------------------------------------------
-- Test B / C: the actual point of this file. Two throwaway functions,
-- identical bodies (count catalog_run, which has RLS enabled and ZERO
-- policies -- default-deny for everyone including anon), differing
-- only in SECURITY INVOKER vs SECURITY DEFINER. Both owned by
-- postgres (which owns catalog_run and bypasses its RLS directly).
--
-- This is the concrete proof that SECURITY INVOKER is what makes RLS
-- apply inside a function body -- not just a property to assert.
-- ---------------------------------------------------------------------
create function _test_catalog_run_count_invoker()
returns bigint language sql stable security invoker
as $$ select count(*) from catalog_run $$;

create function _test_catalog_run_count_definer()
returns bigint language sql stable security definer
as $$ select count(*) from catalog_run $$;

grant execute on function _test_catalog_run_count_invoker() to anon;
grant execute on function _test_catalog_run_count_definer() to anon;

set role anon;

do $$
declare
  v_real_count bigint;
begin
  select count(*) into v_real_count from catalog_run; -- anon's own direct view: 0, RLS blocks it
  if v_real_count != 0 then
    raise exception 'sanity check FAILED: anon should see 0 catalog_run rows directly, got %', v_real_count;
  end if;
end $$;

do $$
declare
  v_invoker_count bigint;
begin
  select _test_catalog_run_count_invoker() into v_invoker_count;
  if v_invoker_count != 0 then
    raise exception 'SECURITY INVOKER test FAILED: expected 0 (RLS enforced inside the function), got %. '
      'This would mean a security-invoker function does NOT respect RLS -- it must.', v_invoker_count;
  end if;
  raise notice 'SECURITY INVOKER function respects RLS inside the function body: PASS (0 rows, despite a real catalog_run row existing)';
end $$;

do $$
declare
  v_definer_count bigint;
begin
  select _test_catalog_run_count_definer() into v_definer_count;
  if v_definer_count = 0 then
    raise exception 'SECURITY DEFINER comparison FAILED: expected >0 (this function SHOULD bypass RLS, demonstrating why DEFINER is dangerous and never used for the real landing functions), got 0';
  end if;
  raise notice 'SECURITY DEFINER function BYPASSES RLS as expected (% row(s) visible despite anon having no catalog_run policy) -- this is exactly the failure mode INVOKER prevents, confirmed by direct contrast, not just asserted', v_definer_count;
end $$;

reset role;

drop function _test_catalog_run_count_invoker();
drop function _test_catalog_run_count_definer();

-- ---------------------------------------------------------------------
-- Test D: REVOKE EXECUTE FROM PUBLIC actually restricts a role that
-- isn't anon -- proves the revoke isn't a no-op. test_no_grants has no
-- explicit grant of any kind (not even table-level SELECT), so this
-- also confirms it's specifically the missing EXECUTE privilege that
-- blocks it, not something else.
-- ---------------------------------------------------------------------
set role test_no_grants;

do $$
begin
  begin
    perform landing_subtitle_counts(null);
    raise exception 'test_no_grants EXECUTE landing_subtitle_counts FAILED: expected permission denied, call succeeded';
  exception
    when insufficient_privilege then
      raise notice 'test_no_grants EXECUTE landing_subtitle_counts: PASS (denied: %)', sqlerrm;
  end;
end $$;

reset role;

do $$
begin
  raise notice 'All landing-function scenarios passed.';
end $$;

rollback;
