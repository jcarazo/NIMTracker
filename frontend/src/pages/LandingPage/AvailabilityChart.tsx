import { AreaChart, Card, Tab, TabGroup, TabList, TabPanel, TabPanels, Title } from '@tremor/react'
import { EmptyState } from '../../components/EmptyState'
import { colorForProvider, PRIMARY_COLOR } from '../../lib/chartColors'
import type { ExecutionPoint, ProviderAvailabilityPoint } from '../../lib/queries'

type Props = {
  overallPoints: ExecutionPoint[]
  providerPoints: ProviderAvailabilityPoint[]
}

// Long-format rows (one per started_at/provider pair) pivoted to wide
// format -- Tremor's AreaChart needs one column per series.
function pivotByProvider(points: ProviderAvailabilityPoint[]) {
  const providers = Array.from(new Set(points.map((p) => p.provider))).sort()
  const byTimestamp = new Map<string, Record<string, string | number>>()

  for (const point of points) {
    let row = byTimestamp.get(point.started_at)
    if (!row) {
      row = { date: new Date(point.started_at).toLocaleString() }
      for (const provider of providers) row[provider] = 0
      byTimestamp.set(point.started_at, row)
    }
    row[point.provider] = point.succeeded_count
  }

  const rows = Array.from(byTimestamp.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([, row]) => row)

  return { rows, providers }
}

// Merged "Models Available Over Time" -- overall and by-provider are
// the same underlying signal at two granularities, not two different
// facts, so one card with a tab toggle rather than two separate cards.
// Defaults to the aggregate view.
export function AvailabilityChart({ overallPoints, providerPoints }: Props) {
  const { rows, providers } = pivotByProvider(providerPoints)

  return (
    <Card>
      <Title>Models Available Over Time</Title>
      <TabGroup>
        <TabList className="mt-2">
          <Tab>Overall</Tab>
          <Tab>By Provider</Tab>
        </TabList>
        <TabPanels>
          <TabPanel>
            {overallPoints.length === 0 ? (
              <EmptyState />
            ) : (
              <AreaChart
                className="mt-4 h-72"
                data={overallPoints.map((p) => ({
                  date: new Date(p.started_at).toLocaleString(),
                  'Models Succeeded': p.models_succeeded_count,
                }))}
                index="date"
                categories={['Models Succeeded']}
                colors={[PRIMARY_COLOR]}
                showAnimation
              />
            )}
          </TabPanel>
          <TabPanel>
            {rows.length === 0 ? (
              <EmptyState />
            ) : (
              <AreaChart
                className="mt-4 h-72"
                data={rows}
                index="date"
                categories={providers}
                colors={providers.map(colorForProvider)}
                showAnimation
              />
            )}
          </TabPanel>
        </TabPanels>
      </TabGroup>
    </Card>
  )
}
