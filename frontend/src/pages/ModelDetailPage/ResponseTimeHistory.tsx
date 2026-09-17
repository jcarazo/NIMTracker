import { AreaChart, Card, Title } from '@tremor/react'
import { EmptyState } from '../../components/EmptyState'
import { PRIMARY_COLOR } from '../../lib/chartColors'
import type { ResponseTimePoint } from '../../lib/queries'

// Same per-point shape as the Models table's TREND sparkline, just
// full-size and single-model -- higher resolution of the same signal.
export function ResponseTimeHistory({ points }: { points: ResponseTimePoint[] }) {
  return (
    <Card>
      <Title>Response Time History</Title>
      {points.length === 0 ? (
        <EmptyState />
      ) : (
        <AreaChart
          className="mt-4 h-72"
          data={points.map((p) => ({
            date: new Date(p.started_at).toLocaleString(),
            'Response Time (s)': p.response_time_s,
          }))}
          index="date"
          categories={['Response Time (s)']}
          colors={[PRIMARY_COLOR]}
          showAnimation
        />
      )}
    </Card>
  )
}
