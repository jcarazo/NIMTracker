-- NIM Availability Tracker — Row Level Security (v1)
--
-- Security model: RLS, not secrecy (see NIMTracker-implementation-plan.md,
-- "Architecture decisions"). The anon key ships in the built frontend
-- bundle -- that's expected. `anon` gets SELECT only, on every table that
-- has to be readable from the browser. No insert/update/delete policy
-- exists for `anon` at all -- default-deny -- so all writes must go
-- through the GitHub Actions jobs, authenticated with the Postgres
-- connection string / service role, never shipped to the client.
--
-- catalog_run gets RLS enabled with NO policy at all -- same
-- default-deny shape as insert/update/delete on the other three tables,
-- just applied to every operation including SELECT. Nothing in the
-- frontend spec (design_decisions.md) reads it directly; it exists
-- purely as an operational log for the daily catalog job. Enabling RLS
-- with zero policies is required to actually get that default-deny:
-- Supabase grants `anon` broad table-level privileges (SELECT included)
-- on public-schema tables by default and relies on RLS as the real
-- enforcement layer (verified directly -- see db/tests/rls_test.sql) --
-- so leaving RLS OFF here would leave catalog_run readable to anon via
-- the GRANT layer alone, the opposite of what an earlier version of
-- this comment claimed. Add a SELECT policy later only if a future view
-- actually needs to read it.

alter table model enable row level security;
alter table execution enable row level security;
alter table result enable row level security;
alter table catalog_run enable row level security;

create policy anon_select_model
  on model for select
  to anon
  using (true);

create policy anon_select_execution
  on execution for select
  to anon
  using (true);

create policy anon_select_result
  on result for select
  to anon
  using (true);
