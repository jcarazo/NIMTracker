-- Phase 4: landing page aggregate RPC functions, plus a retroactive
-- grant-hygiene fix for model_state_as_of(). See db/schema.sql for the
-- full rationale comments -- this file mirrors that content exactly.

create or replace function model_state_as_of(p_slug text, p_as_of timestamptz)
returns text as $$
declare
  v_delisted_at        timestamptz;
  v_most_recent_at     timestamptz;
  v_most_recent_success boolean;
  v_last_success_at    timestamptz;
begin
  select delisted_at into v_delisted_at from model where slug = p_slug;

  if v_delisted_at is not null and v_delisted_at <= p_as_of then
    return 'removed';
  end if;

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
    return 'unknown';
  end if;

  if v_most_recent_success then
    return 'available';
  end if;

  select max(e.started_at) into v_last_success_at
  from result r
  join execution e on e.id = r.execution_id
  where r.model_slug = p_slug
    and r.success
    and r.resolution != 'excluded_non_text'
    and e.started_at <= p_as_of;

  if v_last_success_at is null or p_as_of - v_last_success_at >= interval '24 hours' then
    return 'removed';
  else
    return 'degraded';
  end if;
end;
$$ language plpgsql stable security invoker;

revoke execute on function model_state_as_of(text, timestamptz) from public;
grant execute on function model_state_as_of(text, timestamptz) to anon;

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
