-- Phase 5 follow-up: retroactive grant-hygiene fix, plus a standing fix
-- so it stops recurring. See db/schema.sql's long comment above the
-- landing functions and its "GRANT HYGIENE FIX" block for the full
-- mechanism writeup -- this file mirrors that content exactly.
--
-- Supabase sets its own per-role ALTER DEFAULT PRIVILEGES that
-- auto-grant EXECUTE directly to anon, authenticated, AND service_role
-- individually on every new public-schema function -- a separate
-- mechanism from the Postgres built-in PUBLIC pseudo-role default that
-- `revoke ... from public` does not touch. Every RPC function in this
-- project had authenticated/service_role silently holding EXECUTE
-- despite each one's own `revoke ... from public` line.

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
-- (a genuinely different mechanism) is untouched by this statement --
-- the per-function `revoke ... from public` pattern is still required
-- for every new function.
alter default privileges for role postgres in schema public
  revoke execute on functions from authenticated, service_role;
