import { useEffect, useState } from 'react'
import {
  fetchModelsTableSparklines,
  fetchModelsTableSummary,
  fetchSubtitleCounts,
  type ModelsTableRow,
  type SparklinePoint,
  type SubtitleCounts,
} from '../../lib/queries'

type ModelsPageData = {
  subtitle: SubtitleCounts
  rows: ModelsTableRow[]
  sparklinesByModel: Record<string, SparklinePoint[]>
}

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; data: ModelsPageData }

// Same "one grouped query, not N+1" shape as the landing page --
// models_table_sparklines returns every model's points in one round
// trip, grouped client-side into each row's own small array here.
export function useModelsPageData(since: string | null): State {
  const [state, setState] = useState<State>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    setState({ status: 'loading' })

    Promise.all([fetchSubtitleCounts(since), fetchModelsTableSummary(since), fetchModelsTableSparklines(since)])
      .then(([subtitle, rows, sparklines]) => {
        if (cancelled) return
        const sparklinesByModel: Record<string, SparklinePoint[]> = {}
        for (const point of sparklines) {
          ;(sparklinesByModel[point.model_slug] ??= []).push(point)
        }
        setState({ status: 'ready', data: { subtitle, rows, sparklinesByModel } })
      })
      .catch((err: unknown) => {
        if (cancelled) return
        setState({ status: 'error', message: err instanceof Error ? err.message : String(err) })
      })

    return () => {
      cancelled = true
    }
  }, [since])

  return state
}
