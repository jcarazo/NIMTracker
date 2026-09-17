import { Card, Grid, Metric, Text } from '@tremor/react'
import { StateBadge } from '../../components/StateBadge'
import type { ModelDetailKpis } from '../../lib/queries'

function formatSeconds(value: number | null): string {
  return value != null ? `${value.toFixed(2)}s` : '—'
}

function formatThroughput(value: number | null): string {
  return value != null ? `${value.toFixed(1)} tok/s` : '—'
}

// AA-dependent metrics (AVG TTFT, INTEL INDEX) deliberately dropped, not
// just hidden -- see design doc, "Model detail page" / CLAUDE.md's
// out-of-scope-for-v1 list. Only the 4 boxes buildable from our own data.
export function KpiBoxes({ kpis }: { kpis: ModelDetailKpis }) {
  return (
    <Grid numItemsSm={2} numItemsLg={4} className="gap-4">
      <Card>
        <Text>Uptime</Text>
        <Metric>{kpis.uptime_pct != null ? `${kpis.uptime_pct.toFixed(1)}%` : '—'}</Metric>
        <Text className="mt-2">
          {kpis.success_count}/{kpis.tested_count} runs
        </Text>
        <div className="mt-2">
          <StateBadge state={kpis.state} />
        </div>
      </Card>
      <Card>
        <Text>Avg Response</Text>
        <Metric>{formatSeconds(kpis.avg_response_time_s)}</Metric>
      </Card>
      <Card>
        <Text>Best Response</Text>
        <Metric>{formatSeconds(kpis.best_response_time_s)}</Metric>
      </Card>
      <Card>
        <Text>Avg Throughput</Text>
        <Metric>{formatThroughput(kpis.avg_tokens_per_sec)}</Metric>
      </Card>
    </Grid>
  )
}
