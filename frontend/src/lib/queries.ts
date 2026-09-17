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

// ---------------------------------------------------------------------
// Models page (Phase 5)
// ---------------------------------------------------------------------

export type ModelState = 'available' | 'degraded' | 'removed' | 'unknown'

export type ModelsTableRow = {
  model_slug: string
  provider: string
  model_name: string
  state: ModelState
  avg_response_time_s: number | null
  best_response_time_s: number | null
  best_tokens_per_sec: number | null
  uptime_pct: number | null
}

export type SparklinePoint = {
  model_slug: string
  started_at: string
  response_time_s: number
}

export async function fetchModelsTableSummary(since: string | null): Promise<ModelsTableRow[]> {
  const { data, error } = await supabase.rpc('models_table_summary', { p_since: since })
  if (error) throw error
  return data ?? []
}

export async function fetchModelsTableSparklines(since: string | null): Promise<SparklinePoint[]> {
  const { data, error } = await supabase.rpc('models_table_sparklines', { p_since: since })
  if (error) throw error
  return data ?? []
}

// ---------------------------------------------------------------------
// Model detail page (Phase 5)
// ---------------------------------------------------------------------

export type ModelSelectorOption = {
  model_slug: string
  provider: string
  model_name: string
}

export type ModelDetailKpis = {
  state: ModelState
  tested_count: number
  success_count: number
  uptime_pct: number | null
  avg_response_time_s: number | null
  best_response_time_s: number | null
  avg_tokens_per_sec: number | null
}

export type ModelDetailGlobalAvg = {
  avg_uptime_pct: number | null
  avg_response_time_s: number | null
  avg_tokens_per_sec: number | null
}

export type ModelDetailRadarBounds = {
  best_avg_response_time_s: number | null
  best_avg_tokens_per_sec: number | null
}

export type ErrorBreakdownRow = {
  error_category: string
  error_count: number
}

export type ResponseTimePoint = {
  started_at: string
  response_time_s: number
}

export type RunHistoryRow = {
  execution_id: string
  started_at: string
  success: boolean
  error_category: string | null
  response_time_s: number | null
  tokens_per_sec: number | null
  response_text: string | null
  error_body: string | null
}

export type HeatmapCell = {
  started_at: string
  state: ModelState
}

export async function fetchModelSelectorOptions(since: string | null): Promise<ModelSelectorOption[]> {
  const { data, error } = await supabase.rpc('model_selector_options', { p_since: since })
  if (error) throw error
  return data ?? []
}

export async function fetchModelDetailKpis(slug: string, since: string | null): Promise<ModelDetailKpis> {
  const { data, error } = await supabase.rpc('model_detail_kpis', { p_slug: slug, p_since: since })
  if (error) throw error
  return (
    data?.[0] ?? {
      state: 'unknown',
      tested_count: 0,
      success_count: 0,
      uptime_pct: null,
      avg_response_time_s: null,
      best_response_time_s: null,
      avg_tokens_per_sec: null,
    }
  )
}

export async function fetchModelDetailGlobalAvg(since: string | null): Promise<ModelDetailGlobalAvg> {
  const { data, error } = await supabase.rpc('model_detail_global_avg', { p_since: since })
  if (error) throw error
  return data?.[0] ?? { avg_uptime_pct: null, avg_response_time_s: null, avg_tokens_per_sec: null }
}

export async function fetchModelDetailRadarBounds(since: string | null): Promise<ModelDetailRadarBounds> {
  const { data, error } = await supabase.rpc('model_detail_radar_bounds', { p_since: since })
  if (error) throw error
  return data?.[0] ?? { best_avg_response_time_s: null, best_avg_tokens_per_sec: null }
}

export async function fetchModelDetailErrorBreakdown(
  slug: string,
  since: string | null,
): Promise<ErrorBreakdownRow[]> {
  const { data, error } = await supabase.rpc('model_detail_error_breakdown', { p_slug: slug, p_since: since })
  if (error) throw error
  return data ?? []
}

export async function fetchModelDetailResponseTimeHistory(
  slug: string,
  since: string | null,
): Promise<ResponseTimePoint[]> {
  const { data, error } = await supabase.rpc('model_detail_response_time_history', {
    p_slug: slug,
    p_since: since,
  })
  if (error) throw error
  return data ?? []
}

// Deliberately no `since` argument -- Run History's "last 20" is
// independent of the page's time-range filter (see db/schema.sql's
// model_detail_run_history comment).
export async function fetchModelDetailRunHistory(slug: string): Promise<RunHistoryRow[]> {
  const { data, error } = await supabase.rpc('model_detail_run_history', { p_slug: slug })
  if (error) throw error
  return data ?? []
}

export async function fetchModelDetailAvailabilityHeatmap(
  slug: string,
  since: string | null,
): Promise<HeatmapCell[]> {
  const { data, error } = await supabase.rpc('model_detail_availability_heatmap', {
    p_slug: slug,
    p_since: since,
  })
  if (error) throw error
  return data ?? []
}
