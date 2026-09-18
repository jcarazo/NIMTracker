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
        {/* DESIGN.md's Sparse Accent Rule: Signal Blue is reserved for at
            most two uses per screen (the nav's active-route indicator and
            one aggregate trend line). Tremor's TabList defaults its
            selected-tab indicator to the brand blue too, which put THREE
            concurrent blues on this screen at once (nav + this chart's own
            "Overall" line + the active tab) -- confirmed by inspecting the
            rendered page, not assumed.

            Tremor's own `color` prop (TabList color="gray") is the
            documented way to do this, but doesn't actually render here:
            it makes Tremor construct `data-[selected]:border-gray-500` at
            runtime via a template string inside Tremor's own bundle, which
            Tailwind's JIT content-scanner can't see as a literal class
            anywhere -- confirmed via computed styles showing a fully
            transparent border despite the prop being set, not assumed
            working from the prop alone. This project's tailwind.config.js
            safelist already exists for exactly this class of problem
            (chartColors.ts's Badge/chart colors), but its `variants` list
            doesn't cover this pattern, and extending shared config for one
            local use isn't warranted here (see polish.md: don't build a
            system abstraction for one exception). Writing the override
            classes directly below, in this file, sidesteps the problem
            entirely -- Tailwind's content scan already covers every .tsx
            file under src/, no safelist entry needed. !border-gray-900 also reads
            more clearly as Strong Ink (the "you are here" signal) than
            Tremor's own gray-500 would have, which is identical to the
            already-muted resting-tab color. */}
        <TabList className="mt-2">
          <Tab className="data-[selected]:!border-b-gray-900 data-[selected]:!text-gray-900">Overall</Tab>
          <Tab className="data-[selected]:!border-b-gray-900 data-[selected]:!text-gray-900">By Provider</Tab>
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
