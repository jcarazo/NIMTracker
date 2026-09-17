import { Callout, Flex, Title } from '@tremor/react'
import { PageSubtitle } from '../../components/PageSubtitle'
import { TimeRangeSelector } from '../../components/TimeRangeSelector'
import { useTimeRange } from '../../hooks/useTimeRange'
import { ModelsTable } from './ModelsTable'
import { useModelsPageData } from './useModelsPageData'

export function ModelsPage() {
  const { selected, setSelected, since } = useTimeRange()
  const state = useModelsPageData(since)

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6">
      <Flex justifyContent="between" alignItems="start" flexDirection="col" className="gap-2 sm:flex-row">
        <div>
          <Title>Models</Title>
          <PageSubtitle
            counts={state.status === 'ready' ? state.data.subtitle : null}
            loading={state.status === 'loading'}
          />
        </div>
        <TimeRangeSelector selected={selected} onChange={setSelected} />
      </Flex>

      {state.status === 'error' && (
        <Callout title="Failed to load models" color="red">
          {state.message}
        </Callout>
      )}

      {state.status === 'ready' && (
        <ModelsTable rows={state.data.rows} sparklinesByModel={state.data.sparklinesByModel} />
      )}
    </main>
  )
}
