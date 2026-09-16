import { Callout, Flex, Title } from '@tremor/react'
import { PageSubtitle } from '../../components/PageSubtitle'
import { TimeRangeSelector } from '../../components/TimeRangeSelector'
import { useTimeRange } from '../../hooks/useTimeRange'
import { AvailabilityChart } from './AvailabilityChart'
import { KpiRow } from './KpiRow'
import { Top5Table } from './Top5Table'
import { useLandingPageData } from './useLandingPageData'

export function LandingPage() {
  const { selected, setSelected, since } = useTimeRange()
  const state = useLandingPageData(since)

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6">
      <Flex justifyContent="between" alignItems="start" flexDirection="col" className="gap-2 sm:flex-row">
        <div>
          <Title>NIMTracker</Title>
          <PageSubtitle
            counts={state.status === 'ready' ? state.data.subtitle : null}
            loading={state.status === 'loading'}
          />
        </div>
        <TimeRangeSelector selected={selected} onChange={setSelected} />
      </Flex>

      {state.status === 'error' && (
        <Callout title="Failed to load dashboard data" color="red">
          {state.message}
        </Callout>
      )}

      {state.status === 'ready' && (
        <>
          <KpiRow subtitle={state.data.subtitle} kpis={state.data.kpis} />

          <AvailabilityChart
            overallPoints={state.data.availabilityOverTime}
            providerPoints={state.data.availabilityByProvider}
          />

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <Top5Table
              title="Top 5 Fastest Models"
              rows={state.data.top5Fastest}
              metricLabel="Best Time"
              formatMetric={(row) => `${row.best_response_time_s}s`}
            />
            <Top5Table
              title="Top 5 Throughput"
              rows={state.data.top5Throughput}
              metricLabel="Best Throughput"
              formatMetric={(row) => `${row.best_tokens_per_sec} tok/s`}
            />
          </div>
        </>
      )}
    </main>
  )
}
