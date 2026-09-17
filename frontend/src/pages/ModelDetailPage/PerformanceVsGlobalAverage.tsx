import { Card, Flex, Text, Title } from '@tremor/react'
import type { ModelDetailGlobalAvg, ModelDetailKpis } from '../../lib/queries'

// 3-metric v1, same AA-deferral reasoning as the Capability Radar. Three
// separate rows rather than one combined bar chart -- the three metrics
// (a percentage, seconds, tok/s) don't share a unit or an axis, so
// putting them on one chart would visually imply a comparison that
// isn't there. A plain side-by-side number pair per metric is honest
// about that instead.
type Props = {
  kpis: ModelDetailKpis
  globalAvg: ModelDetailGlobalAvg
}

type Row = {
  label: string
  thisModel: number | null
  average: number | null
  format: (v: number) => string
}

function ComparisonRow({ row }: { row: Row }) {
  return (
    <div>
      <Text>{row.label}</Text>
      <Flex justifyContent="between" className="mt-1">
        <Text className="font-medium text-gray-900">
          This model: {row.thisModel != null ? row.format(row.thisModel) : '—'}
        </Text>
        <Text>Global average: {row.average != null ? row.format(row.average) : '—'}</Text>
      </Flex>
    </div>
  )
}

export function PerformanceVsGlobalAverage({ kpis, globalAvg }: Props) {
  const rows: Row[] = [
    {
      label: 'Reliability',
      thisModel: kpis.uptime_pct,
      average: globalAvg.avg_uptime_pct,
      format: (v) => `${v.toFixed(1)}%`,
    },
    {
      label: 'Avg Response',
      thisModel: kpis.avg_response_time_s,
      average: globalAvg.avg_response_time_s,
      format: (v) => `${v.toFixed(2)}s`,
    },
    {
      label: 'Avg Throughput',
      thisModel: kpis.avg_tokens_per_sec,
      average: globalAvg.avg_tokens_per_sec,
      format: (v) => `${v.toFixed(1)} tok/s`,
    },
  ]

  return (
    <Card>
      <Title>Performance vs Global Average</Title>
      <div className="mt-4 space-y-4">
        {rows.map((row) => (
          <ComparisonRow key={row.label} row={row} />
        ))}
      </div>
    </Card>
  )
}
