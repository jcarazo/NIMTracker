import {
  Badge,
  Card,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeaderCell,
  TableRow,
  Title,
} from '@tremor/react'
import { EmptyState } from '../../components/EmptyState'
import { colorForProvider } from '../../lib/chartColors'

// Deliberately not clickable / no link-through to a model detail page
// yet -- that page is Phase 5 scope and doesn't exist. See
// NIMTracker-implementation-plan.md section 9 / CLAUDE.md.
type Row = {
  model_slug: string
  provider: string
  model_name: string
}

type Props<T extends Row> = {
  title: string
  rows: T[]
  metricLabel: string
  formatMetric: (row: T) => string
}

export function Top5Table<T extends Row>({ title, rows, metricLabel, formatMetric }: Props<T>) {
  return (
    <Card>
      <Title>{title}</Title>
      {rows.length === 0 ? (
        <EmptyState />
      ) : (
        <Table className="mt-4">
          <TableHead>
            <TableRow>
              <TableHeaderCell>Model</TableHeaderCell>
              <TableHeaderCell>Provider</TableHeaderCell>
              <TableHeaderCell className="text-right">{metricLabel}</TableHeaderCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.model_slug}>
                {/* Tremor's default column sizing gave the model name
                    column ~318px for a name as short as "gpt-oss-20b",
                    overflowing this two-column-per-row layout's ~500px
                    card width (confirmed by measuring the rendered
                    table in a real browser, not assumed) -- capped and
                    truncated with a title tooltip for the full name. */}
                <TableCell className="max-w-[140px] truncate" title={row.model_name}>
                  {row.model_name}
                </TableCell>
                <TableCell>
                  <Badge color={colorForProvider(row.provider)}>{row.provider}</Badge>
                </TableCell>
                <TableCell className="text-right">{formatMetric(row)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </Card>
  )
}
