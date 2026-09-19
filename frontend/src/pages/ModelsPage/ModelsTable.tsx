import {
  Badge,
  Card,
  SparkAreaChart,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeaderCell,
  TableRow,
  Text,
  TextInput,
} from '@tremor/react'
import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { EmptyState } from '../../components/EmptyState'
import { StateBadge } from '../../components/StateBadge'
import { BADGE_CHIP_CLASSNAME, colorForProvider } from '../../lib/chartColors'
import type { ModelsTableRow, SparklinePoint } from '../../lib/queries'

function formatSeconds(value: number | null): string {
  return value != null ? `${value.toFixed(2)}s` : '—'
}

function formatThroughput(value: number | null): string {
  return value != null ? `${value.toFixed(1)} tok/s` : '—'
}

// Uptime % only shown for Available/Degraded -- a Removed model showing
// a stale percentage is the exact "misleading number" problem this
// column exists to fix (design doc: the percentage "only applies to
// currently-available models"). Degraded still gets one since it's
// still actively tracked/tested, just currently failing.
function formatUptime(row: ModelsTableRow): string {
  if (row.state === 'removed' || row.uptime_pct == null) return '—'
  return `${row.uptime_pct.toFixed(1)}%`
}

type Props = {
  rows: ModelsTableRow[]
  sparklinesByModel: Record<string, SparklinePoint[]>
}

export function ModelsTable({ rows, sparklinesByModel }: Props) {
  const [nameFilter, setNameFilter] = useState('')
  const navigate = useNavigate()

  const filteredRows = useMemo(() => {
    const q = nameFilter.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((row) => row.model_name.toLowerCase().includes(q) || row.provider.toLowerCase().includes(q))
  }, [rows, nameFilter])

  return (
    <Card>
      <TextInput
        placeholder="Filter by model name..."
        value={nameFilter}
        onValueChange={setNameFilter}
        className="max-w-sm"
      />

      {filteredRows.length === 0 ? (
        <EmptyState message={rows.length === 0 ? 'No models seen yet.' : 'No models match this filter.'} />
      ) : (
        <Table className="mt-4">
          <TableHead>
            <TableRow>
              <TableHeaderCell>Model</TableHeaderCell>
              <TableHeaderCell className="text-right">Avg Time</TableHeaderCell>
              <TableHeaderCell className="text-right">Best Time</TableHeaderCell>
              <TableHeaderCell className="text-right">Throughput</TableHeaderCell>
              <TableHeaderCell>Trend</TableHeaderCell>
              <TableHeaderCell>Uptime</TableHeaderCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {filteredRows.map((row) => {
              const sparkline = sparklinesByModel[row.model_slug] ?? []
              return (
                <TableRow
                  key={row.model_slug}
                  className="cursor-pointer hover:bg-gray-50"
                  onClick={() => navigate(`/models/${row.model_slug}`)}
                >
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span className="max-w-[160px] truncate" title={row.model_name}>
                        {row.model_name}
                      </span>
                      <Badge color={colorForProvider(row.provider)} size="xs" className={BADGE_CHIP_CLASSNAME}>
                        {row.provider}
                      </Badge>
                    </div>
                  </TableCell>
                  <TableCell className="text-right">{formatSeconds(row.avg_response_time_s)}</TableCell>
                  <TableCell className="text-right">{formatSeconds(row.best_response_time_s)}</TableCell>
                  <TableCell className="text-right">{formatThroughput(row.best_tokens_per_sec)}</TableCell>
                  <TableCell>
                    {sparkline.length > 1 ? (
                      <SparkAreaChart
                        data={sparkline}
                        index="started_at"
                        categories={['response_time_s']}
                        colors={[colorForProvider(row.provider)]}
                        className="h-8 w-24"
                      />
                    ) : (
                      <Text className="text-xs text-gray-400">Not enough data</Text>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <StateBadge state={row.state} />
                      <Text>{formatUptime(row)}</Text>
                    </div>
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      )}
    </Card>
  )
}
