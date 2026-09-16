import { Badge, Card, Grid, Metric, Text } from '@tremor/react'
import { colorForProvider } from '../../lib/chartColors'
import type { LandingKpis, SubtitleCounts } from '../../lib/queries'

type Props = {
  subtitle: SubtitleCounts
  kpis: LandingKpis
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
        <Metric>{kpis.best_response_time_s != null ? `${kpis.best_response_time_s}s` : '—'}</Metric>
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
        <Metric>{kpis.best_throughput_tok_s != null ? `${kpis.best_throughput_tok_s} tok/s` : '—'}</Metric>
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
