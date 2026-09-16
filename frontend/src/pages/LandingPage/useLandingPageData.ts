import { useEffect, useState } from 'react'
import {
  fetchAvailabilityByProvider,
  fetchAvailabilityOverTime,
  fetchLandingKpis,
  fetchSubtitleCounts,
  fetchTop5Fastest,
  fetchTop5Throughput,
  type ExecutionPoint,
  type LandingKpis,
  type ProviderAvailabilityPoint,
  type SubtitleCounts,
  type Top5FastestRow,
  type Top5ThroughputRow,
} from '../../lib/queries'

type LandingPageData = {
  subtitle: SubtitleCounts
  kpis: LandingKpis
  availabilityOverTime: ExecutionPoint[]
  availabilityByProvider: ProviderAvailabilityPoint[]
  top5Fastest: Top5FastestRow[]
  top5Throughput: Top5ThroughputRow[]
}

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; data: LandingPageData }

// One fetch per time-range change, all six queries in parallel. The
// subtitle counts and the "Models Available" KPI use the exact same
// underlying query (design_decisions.md is explicit these two numbers
// share one definition) -- fetched once here, not duplicated per
// component.
export function useLandingPageData(since: string | null): State {
  const [state, setState] = useState<State>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    setState({ status: 'loading' })

    Promise.all([
      fetchSubtitleCounts(since),
      fetchLandingKpis(since),
      fetchAvailabilityOverTime(since),
      fetchAvailabilityByProvider(since),
      fetchTop5Fastest(since),
      fetchTop5Throughput(since),
    ])
      .then(([subtitle, kpis, availabilityOverTime, availabilityByProvider, top5Fastest, top5Throughput]) => {
        if (cancelled) return
        setState({
          status: 'ready',
          data: { subtitle, kpis, availabilityOverTime, availabilityByProvider, top5Fastest, top5Throughput },
        })
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
