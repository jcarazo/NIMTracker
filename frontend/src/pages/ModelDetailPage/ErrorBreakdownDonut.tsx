import { Card, DonutChart, Title } from '@tremor/react'
import { EmptyState } from '../../components/EmptyState'
import { colorForErrorCategory } from '../../lib/chartColors'
import type { ErrorBreakdownRow } from '../../lib/queries'

// Failure-only slices using the full validated 7-value taxonomy -- the
// direct fix for NIMStats' 2-category collapse (Timeout / Connection
// Closed) that this whole project exists to correct. No "success" slice
// -- this chart is specifically about what kind of failure occurred.
export function ErrorBreakdownDonut({ rows }: { rows: ErrorBreakdownRow[] }) {
  return (
    <Card>
      <Title>Error Breakdown</Title>
      {rows.length === 0 ? (
        <EmptyState message="No failures in this time range." />
      ) : (
        <DonutChart
          className="mt-4 h-56"
          data={rows}
          category="error_count"
          index="error_category"
          colors={rows.map((row) => colorForErrorCategory(row.error_category))}
          valueFormatter={(v) => `${v} run(s)`}
        />
      )}
    </Card>
  )
}
