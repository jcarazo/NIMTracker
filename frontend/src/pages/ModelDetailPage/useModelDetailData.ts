import { useEffect, useState } from 'react'
import {
  fetchModelDetailAvailabilityHeatmap,
  fetchModelDetailErrorBreakdown,
  fetchModelDetailGlobalAvg,
  fetchModelDetailKpis,
  fetchModelDetailRadarBounds,
  fetchModelDetailResponseTimeHistory,
  fetchModelDetailRunHistory,
  fetchModelSelectorOptions,
  fetchSubtitleCounts,
  type ErrorBreakdownRow,
  type HeatmapCell,
  type ModelDetailGlobalAvg,
  type ModelDetailKpis,
  type ModelDetailRadarBounds,
  type ModelSelectorOption,
  type ResponseTimePoint,
  type RunHistoryRow,
  type SubtitleCounts,
} from '../../lib/queries'

type ModelDetailData = {
  subtitle: SubtitleCounts
  selectorOptions: ModelSelectorOption[]
  kpis: ModelDetailKpis
  globalAvg: ModelDetailGlobalAvg
  radarBounds: ModelDetailRadarBounds
  errorBreakdown: ErrorBreakdownRow[]
  responseTimeHistory: ResponseTimePoint[]
  runHistory: RunHistoryRow[]
  heatmap: HeatmapCell[]
}

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; data: ModelDetailData }

// Run History deliberately omits `since` from its own fetch (see
// fetchModelDetailRunHistory) -- everything else here is scoped to the
// selected window, same as every other page.
export function useModelDetailData(slug: string, since: string | null): State {
  const [state, setState] = useState<State>({ status: 'loading' })

  useEffect(() => {
    if (!slug) return
    let cancelled = false
    setState({ status: 'loading' })

    Promise.all([
      fetchSubtitleCounts(since),
      fetchModelSelectorOptions(since),
      fetchModelDetailKpis(slug, since),
      fetchModelDetailGlobalAvg(since),
      fetchModelDetailRadarBounds(since),
      fetchModelDetailErrorBreakdown(slug, since),
      fetchModelDetailResponseTimeHistory(slug, since),
      fetchModelDetailRunHistory(slug),
      fetchModelDetailAvailabilityHeatmap(slug, since),
    ])
      .then(
        ([
          subtitle,
          selectorOptions,
          kpis,
          globalAvg,
          radarBounds,
          errorBreakdown,
          responseTimeHistory,
          runHistory,
          heatmap,
        ]) => {
          if (cancelled) return
          setState({
            status: 'ready',
            data: {
              subtitle,
              selectorOptions,
              kpis,
              globalAvg,
              radarBounds,
              errorBreakdown,
              responseTimeHistory,
              runHistory,
              heatmap,
            },
          })
        },
      )
      .catch((err: unknown) => {
        if (cancelled) return
        setState({ status: 'error', message: err instanceof Error ? err.message : String(err) })
      })

    return () => {
      cancelled = true
    }
  }, [slug, since])

  return state
}
