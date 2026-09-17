import { Callout, Flex, Title } from '@tremor/react'
import { PageSubtitle } from '../../components/PageSubtitle'
import { TimeRangeSelector } from '../../components/TimeRangeSelector'
import { useTimeRange } from '../../hooks/useTimeRange'
import { ExecutionsTable } from './ExecutionsTable'
import { useExecutionsPageData } from './useExecutionsPageData'

// Shows only hourly completions-testing runs, never the daily
// catalog-discovery refresh -- those are two separate activities (see
// CLAUDE.md, catalog_run vs execution).
export function ExecutionsPage() {
  const { selected, setSelected, since } = useTimeRange()
  const state = useExecutionsPageData(since)

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6">
      <Flex justifyContent="between" alignItems="start" flexDirection="col" className="gap-2 sm:flex-row">
        <div>
          <Title>Executions</Title>
          <PageSubtitle
            counts={state.status === 'ready' ? state.data.subtitle : null}
            loading={state.status === 'loading'}
          />
        </div>
        <TimeRangeSelector selected={selected} onChange={setSelected} />
      </Flex>

      {state.status === 'error' && (
        <Callout title="Failed to load executions" color="red">
          {state.message}
        </Callout>
      )}

      {state.status === 'ready' && <ExecutionsTable rows={state.data.rows} />}
    </main>
  )
}
