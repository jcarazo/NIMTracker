import { Badge, Card, Grid, Metric, Text } from '@tremor/react'
import { colorForProvider } from '../../lib/chartColors'
import type { LandingKpis, SubtitleCounts } from '../../lib/queries'

type Props = {
  subtitle: SubtitleCounts
  kpis: LandingKpis
}

// Same .toFixed(2)/.toFixed(1) convention as the Models page's
// formatSeconds/formatThroughput -- this row previously interpolated
// the raw RPC numeric straight into the Metric with no rounding, the
// one place on the site that could show an ugly long decimal where
// every other page shows a clean fixed-precision value.
function formatSeconds(value: number | null): string {
  return value != null ? `${value.toFixed(2)}s` : '—'
}

function formatThroughput(value: number | null): string {
  return value != null ? `${value.toFixed(1)} tok/s` : '—'
}

export function KpiRow({ subtitle, kpis }: Props) {
  return (
    <Grid numItemsSm={1} numItemsMd={3} className="gap-4">
      <Card>
        <Text>Models Available</Text>
        <Metric>{subtitle.working}</Metric>
      </Card>

      <Card>
        <Text>Best Response</Text>
        <Metric>{formatSeconds(kpis.best_response_time_s)}</Metric>
        {kpis.best_response_model_slug && (
          <Text className="mt-2 flex items-center gap-2">
            {kpis.best_response_model_slug}
            {kpis.best_response_provider && (
              <Badge color={colorForProvider(kpis.best_response_provider)}>{kpis.best_response_provider}</Badge>
            )}
          </Text>
        )}
      </Card>

      <Card>
        <Text>Best Throughput</Text>
        <Metric>{formatThroughput(kpis.best_throughput_tok_s)}</Metric>
        {kpis.best_throughput_model_slug && (
          <Text className="mt-2 flex items-center gap-2">
            {kpis.best_throughput_model_slug}
            {kpis.best_throughput_provider && (
              <Badge color={colorForProvider(kpis.best_throughput_provider)}>{kpis.best_throughput_provider}</Badge>
            )}
          </Text>
        )}
      </Card>
    </Grid>
  )
}
