// Typed query functions. Every query that needs a caller-supplied time
// window goes through the landing_* RPC functions (see db/schema.sql --
// PostgREST can't express arbitrary GROUP BY / parameterized filters
// directly). The one exception is availabilityOverTime, which is a
// direct, unaggregated read PostgREST handles natively.

import { supabase } from './supabase'

export type SubtitleCounts = {
  tracked: number
  working: number
}

export type LandingKpis = {
  best_response_model_slug: string | null
  best_response_provider: string | null
  best_response_time_s: number | null
  best_throughput_model_slug: string | null
  best_throughput_provider: string | null
  best_throughput_tok_s: number | null
}

export type ExecutionPoint = {
  started_at: string
  models_succeeded_count: number
}

export type ProviderAvailabilityPoint = {
  started_at: string
  provider: string
  succeeded_count: number
}

export type Top5FastestRow = {
  model_slug: string
  provider: string
  model_name: string
  best_response_time_s: number
}

export type Top5ThroughputRow = {
  model_slug: string
  provider: string
  model_name: string
  best_tokens_per_sec: number
}

export async function fetchSubtitleCounts(since: string | null): Promise<SubtitleCounts> {
  const { data, error } = await supabase.rpc('landing_subtitle_counts', { p_since: since })
  if (error) throw error
  return data?.[0] ?? { tracked: 0, working: 0 }
}

export async function fetchLandingKpis(since: string | null): Promise<LandingKpis> {
  const { data, error } = await supabase.rpc('landing_kpis', { p_since: since })
  if (error) throw error
  return (
    data?.[0] ?? {
      best_response_model_slug: null,
      best_response_provider: null,
      best_response_time_s: null,
      best_throughput_model_slug: null,
      best_throughput_provider: null,
      best_throughput_tok_s: null,
    }
  )
}

export async function fetchAvailabilityOverTime(since: string | null): Promise<ExecutionPoint[]> {
  let query = supabase
    .from('execution')
    .select('started_at, models_succeeded_count')
    .order('started_at', { ascending: true })
  if (since) query = query.gte('started_at', since)
  const { data, error } = await query
  if (error) throw error
  return data ?? []
}

export async function fetchAvailabilityByProvider(since: string | null): Promise<ProviderAvailabilityPoint[]> {
  const { data, error } = await supabase.rpc('landing_availability_by_provider', { p_since: since })
  if (error) throw error
  return data ?? []
}

export async function fetchTop5Fastest(since: string | null): Promise<Top5FastestRow[]> {
  const { data, error } = await supabase.rpc('landing_top5_fastest', { p_since: since })
  if (error) throw error
  return data ?? []
}

export async function fetchTop5Throughput(since: string | null): Promise<Top5ThroughputRow[]> {
  const { data, error } = await supabase.rpc('landing_top5_throughput', { p_since: since })
  if (error) throw error
  return data ?? []
}
