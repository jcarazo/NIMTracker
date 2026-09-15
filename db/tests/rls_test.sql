-- RLS verification for db/rls_policies.sql, per the review comment on
-- catalog_run: it must have RLS ENABLED with NO policy (default-deny on
-- every operation, including SELECT), not simply left with RLS off.
--
-- Run against a real Postgres instance with schema.sql AND
-- rls_policies.sql already applied. Wrapped in a transaction and rolled
-- back at the end -- safe to run against a scratch/local database
-- repeatedly. NEVER run this against the real Supabase project without
-- explicit confirmation first (see CLAUDE.md, Hard rules).
--
-- Deliberately grants `anon` full SELECT/INSERT/UPDATE/DELETE at the
-- GRANT layer before testing -- that's what Supabase actually does by
-- default on public-schema tables, relying on RLS itself (not the GRANT
-- layer) to enforce default-deny. Testing against a weaker "anon has no
-- grants at all" setup would pass for the wrong reason.

begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
end $$;

grant usage on schema public to anon;
grant select, insert, update, delete on model, execution, result, catalog_run to anon;

insert into model (slug, provider, model_name) values ('test/rls-check', 'Test', 'rls-check');
insert into execution (started_at) values (now());
insert into catalog_run (list_source, models_found_count) values ('live', 35);
insert into result (execution_id, model_slug, success, resolution)
select id, 'test/rls-check', true, 'counted_working' from execution limit 1;

set role anon;

-- ---------------------------------------------------------------------
-- anon can read model / execution / result (the three tables with a
-- SELECT policy).
-- ---------------------------------------------------------------------
do $$
declare v_count integer;
begin
  select count(*) into v_count from model;
  if v_count < 1 then
    raise exception 'anon SELECT on model FAILED: expected >=1 row, got %', v_count;
  end if;
  raise notice 'anon SELECT on model: PASS (% row(s))', v_count;
end $$;

do $$
declare v_count integer;
begin
  select count(*) into v_count from execution;
  if v_count < 1 then
    raise exception 'anon SELECT on execution FAILED: expected >=1 row, got %', v_count;
  end if;
  raise notice 'anon SELECT on execution: PASS (% row(s))', v_count;
end $$;

do $$
declare v_count integer;
begin
  select count(*) into v_count from result;
  if v_count < 1 then
    raise exception 'anon SELECT on result FAILED: expected >=1 row, got %', v_count;
  end if;
  raise notice 'anon SELECT on result: PASS (% row(s))', v_count;
end $$;

-- ---------------------------------------------------------------------
-- anon gets ZERO access to catalog_run -- RLS enabled, no policy at
-- all, so even SELECT returns no rows despite the GRANT-layer
-- permission and despite a real row existing (inserted above as
-- postgres). This is the specific behavior the review comment asked to
-- confirm.
-- ---------------------------------------------------------------------
do $$
declare v_count integer;
begin
  select count(*) into v_count from catalog_run;
  if v_count != 0 then
    raise exception 'anon SELECT on catalog_run FAILED: expected 0 rows (RLS default-deny), got %', v_count;
  end if;
  raise notice 'anon SELECT on catalog_run: PASS (0 rows, despite a real row existing)';
end $$;

-- ---------------------------------------------------------------------
-- anon writes are denied by RLS itself (not just by GRANT) on every
-- table, including catalog_run.
-- ---------------------------------------------------------------------
do $$
begin
  begin
    insert into model (slug, provider, model_name) values ('test/anon-write-attempt', 'Test', 'should fail');
    raise exception 'anon INSERT on model FAILED: expected RLS violation, insert succeeded';
  exception
    when insufficient_privilege then
      raise notice 'anon INSERT on model: PASS (denied: %)', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    insert into catalog_run (list_source, models_found_count) values ('live', 99);
    raise exception 'anon INSERT on catalog_run FAILED: expected RLS violation, insert succeeded';
  exception
    when insufficient_privilege then
      raise notice 'anon INSERT on catalog_run: PASS (denied: %)', sqlerrm;
  end;
end $$;

do $$
declare v_rowcount integer;
begin
  update model set model_name = 'hacked' where slug = 'test/rls-check';
  get diagnostics v_rowcount = row_count;
  if v_rowcount != 0 then
    raise exception 'anon UPDATE on model FAILED: expected 0 rows updated, got %', v_rowcount;
  end if;
  raise notice 'anon UPDATE on model: PASS (0 rows updated)';
end $$;

do $$
declare v_rowcount integer;
begin
  update catalog_run set models_found_count = 0;
  get diagnostics v_rowcount = row_count;
  if v_rowcount != 0 then
    raise exception 'anon UPDATE on catalog_run FAILED: expected 0 rows updated, got %', v_rowcount;
  end if;
  raise notice 'anon UPDATE on catalog_run: PASS (0 rows updated)';
end $$;

reset role;

do $$
begin
  raise notice 'All RLS scenarios passed.';
end $$;

rollback;
