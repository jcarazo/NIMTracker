-- pg_cron + pg_net infra: replaces reliance on GitHub Actions' own
-- `schedule:` trigger with an external caller hitting `workflow_dispatch`
-- on a schedule instead.
--
-- WHY: confirmed by inspecting NIMStats' actual production workflow --
-- it has NO `schedule:` trigger at all, only `workflow_dispatch`;
-- something external calls that API hourly. GitHub's own `schedule:`
-- cron trigger is known to be unreliable in practice (silently skipped
-- or delayed runs, especially on free-tier repos) -- this validates
-- replacing it with a more reliable external trigger, the same
-- approach NIMStats already uses in production.
--
-- DELIBERATELY A SEPARATE FILE FROM db/schema.sql, not folded in:
-- pg_cron requires `shared_preload_libraries` configured at the
-- Postgres SERVER level, which Supabase's managed platform provides but
-- a vanilla `postgres:16` Docker container (used throughout this
-- project's "verify locally" workflow -- see CLAUDE.md, Setup/commands)
-- does not. `create extension pg_cron` would fail there. This file is
-- live-project-only; it cannot be verified via the throwaway-container
-- pattern the rest of db/schema.sql uses. Supabase's own local CLI
-- stack (`supabase start`) DOES bundle pg_cron, so `supabase db diff
-- --linked` can still compute a diff against this, but there is no
-- local Docker-container test for it the way db/tests/*.sql work for
-- schema.sql.
--
-- Both extensions confirmed available on this project (Postgres 17.6)
-- before enabling: pg_cron 1.6.4, pg_net 0.20.4.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- The one deliberate SECURITY DEFINER exception in this codebase --
-- every other function here is SECURITY INVOKER, no exceptions (see
-- db/schema.sql's landing-functions comment for why that's the default
-- posture). DEFINER is required here specifically because reading
-- vault.decrypted_secrets needs elevated privilege that `postgres`
-- (the role pg_cron actually calls this as) doesn't have under INVOKER
-- semantics -- not a shortcut, a narrow necessity.
--
-- Safe because EXECUTE is granted ONLY to postgres (verified via
-- pg_proc.proacl, not assumed) -- never reachable from the frontend's
-- anon key. This matters concretely here, not just in principle: this
-- function can trigger arbitrary GitHub Actions runs and touches a
-- live secret, so the ALTER DEFAULT PRIVILEGES gap documented in
-- db/schema.sql (which silently gave `anon` EXECUTE on every new
-- function, including this one, until explicitly revoked) was a real
-- risk here, caught by reading pg_proc.proacl directly after creation,
-- not by trusting the grant statements below to be sufficient on
-- their own -- always re-verify the ACL after creating a
-- SECURITY DEFINER function, the same discipline applies to any future
-- one.
--
-- net.http_post is ASYNC -- queues the request and returns a
-- request_id immediately; the actual call to GitHub happens via a
-- pg_net background worker. This function succeeding means "the
-- dispatch was queued," not "GitHub definitely received it" -- check
-- `select * from net._http_response where id = <request_id>` to see
-- the real response if ever debugging a missed run (status 204 =
-- success, matching GitHub's documented workflow_dispatch response).
create or replace function public.trigger_github_workflow(p_workflow_file text)
returns bigint
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
declare
  v_pat text;
  v_request_id bigint;
begin
  select decrypted_secret into v_pat
  from vault.decrypted_secrets
  where name = 'github_actions_pat';

  if v_pat is null then
    raise exception 'Vault secret "github_actions_pat" not found -- run vault.create_secret(...) first';
  end if;

  select net.http_post(
    url := 'https://api.github.com/repos/jcarazo/NIMTracker/actions/workflows/' || p_workflow_file || '/dispatches',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_pat,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'Content-Type', 'application/json',
      'User-Agent', 'nimtracker-pg-cron'
    ),
    body := jsonb_build_object('ref', 'main')
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke execute on function public.trigger_github_workflow(text) from public, anon, authenticated, service_role;
grant execute on function public.trigger_github_workflow(text) to postgres;

-- Same cron expressions already used in both workflow YAMLs' `schedule:`
-- triggers -- the "offset from the top of the hour" reasoning documented
-- there carries over unchanged. The `schedule:` trigger is deliberately
-- LEFT IN both YAML files as a redundant backup for now (see CLAUDE.md)
-- -- not removed until the pg_cron path has proven itself reliable over
-- real days of operation.
--
-- cron.schedule() upserts by job name on pg_cron 1.4+ (confirmed on
-- this project's 1.6.4) -- safe to re-run this file; it will not create
-- duplicate jobs.
select cron.schedule(
  'trigger-completions-sweep-hourly',
  '7 * * * *',
  $$select public.trigger_github_workflow('completions-sweep.yml')$$
);

select cron.schedule(
  'trigger-catalog-discovery-daily',
  '17 3 * * *',
  $$select public.trigger_github_workflow('catalog-discovery.yml')$$
);
