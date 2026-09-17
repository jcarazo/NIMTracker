import { Callout, Flex } from '@tremor/react'
import { useMemo } from 'react'
import { Link, useParams } from 'react-router-dom'
import { PageSubtitle } from '../../components/PageSubtitle'
import { TimeRangeSelector } from '../../components/TimeRangeSelector'
import { useTimeRange } from '../../hooks/useTimeRange'
import { AvailabilityHeatmap } from './AvailabilityHeatmap'
import { CapabilityRadar } from './CapabilityRadar'
import { ErrorBreakdownDonut } from './ErrorBreakdownDonut'
import { KpiBoxes } from './KpiBoxes'
import { ModelSelector } from './ModelSelector'
import { PerformanceVsGlobalAverage } from './PerformanceVsGlobalAverage'
import { ResponseTimeHistory } from './ResponseTimeHistory'
import { RunHistoryTable } from './RunHistoryTable'
import { useModelDetailData } from './useModelDetailData'

// No route param named ':slug' -- model.slug contains a literal '/'
// (e.g. 'moonshotai/kimi-k3'), so App.tsx uses a splat route
// ('models/*') and the full trailing path is read here via
// useParams()['*'], verbatim, no decoding needed.
export function ModelDetailPage() {
  const params = useParams()
  const slug = params['*'] ?? ''
  const { selected, setSelected, since } = useTimeRange()
  const state = useModelDetailData(slug, since)

  // The selector's option list is scoped to the current window (see
  // ModelSelector's comment) and may not include the model actually
  // being viewed -- e.g. reached via the Models table's all-time "seen
  // at least once" rule while a narrow window is selected. Ensure the
  // current model is always selectable, even without a window-scoped
  // name/provider to show for it yet.
  const selectorOptions = useMemo(() => {
    if (state.status !== 'ready') return []
    const { selectorOptions } = state.data
    if (selectorOptions.some((o) => o.model_slug === slug)) return selectorOptions
    return [...selectorOptions, { model_slug: slug, provider: '', model_name: slug }]
  }, [state, slug])

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6">
      <Flex justifyContent="between" alignItems="start" flexDirection="col" className="gap-2 sm:flex-row">
        <div>
          <Link to="/models" className="text-sm text-blue-600 hover:underline">
            ← Back to Models
          </Link>
          <PageSubtitle
            counts={state.status === 'ready' ? state.data.subtitle : null}
            loading={state.status === 'loading'}
          />
        </div>
        <div className="flex flex-col gap-2 sm:flex-row">
          <ModelSelector options={selectorOptions} currentSlug={slug} />
          <TimeRangeSelector selected={selected} onChange={setSelected} />
        </div>
      </Flex>

      {state.status === 'error' && (
        <Callout title="Failed to load model detail" color="red">
          {state.message}
        </Callout>
      )}

      {state.status === 'ready' && (
        <>
          <KpiBoxes kpis={state.data.kpis} />

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <CapabilityRadar kpis={state.data.kpis} bounds={state.data.radarBounds} />
            <PerformanceVsGlobalAverage kpis={state.data.kpis} globalAvg={state.data.globalAvg} />
          </div>

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <ErrorBreakdownDonut rows={state.data.errorBreakdown} />
            <AvailabilityHeatmap cells={state.data.heatmap} />
          </div>

          <ResponseTimeHistory points={state.data.responseTimeHistory} />

          <RunHistoryTable rows={state.data.runHistory} />
        </>
      )}
    </main>
  )
}
