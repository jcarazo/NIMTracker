import {
  Badge,
  Button,
  Card,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeaderCell,
  TableRow,
  Title,
} from '@tremor/react'
import { useState } from 'react'
import { EmptyState } from '../../components/EmptyState'
import { ResponseModal } from '../../components/ResponseModal'
import { BADGE_CHIP_CLASSNAME, colorForErrorCategory } from '../../lib/chartColors'
import type { RunHistoryRow } from '../../lib/queries'

// Fixed "last 20", independent of the page's time-range filter (see
// db/schema.sql's model_detail_run_history comment / the Phase 5 plan
// discussion) -- never goes empty just because a short window is
// selected. Status column shows the real error taxonomy on failure
// rows, not a generic "failed" marker -- the direct fix for NIMStats'
// version doing the latter.
export function RunHistoryTable({ rows }: { rows: RunHistoryRow[] }) {
  const [selected, setSelected] = useState<RunHistoryRow | null>(null)

  return (
    <Card>
      <Title>Run History (Last 20)</Title>
      {rows.length === 0 ? (
        <EmptyState />
      ) : (
        <Table className="mt-4">
          <TableHead>
            <TableRow>
              <TableHeaderCell>Started At</TableHeaderCell>
              <TableHeaderCell>Status</TableHeaderCell>
              <TableHeaderCell className="text-right">Response Time</TableHeaderCell>
              <TableHeaderCell className="text-right">Throughput</TableHeaderCell>
              <TableHeaderCell />
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.execution_id}>
                <TableCell>{new Date(row.started_at).toLocaleString()}</TableCell>
                <TableCell>
                  {row.success ? (
                    <Badge color="emerald" size="xs" className={BADGE_CHIP_CLASSNAME}>
                      Success
                    </Badge>
                  ) : (
                    <Badge
                      color={colorForErrorCategory(row.error_category ?? 'other')}
                      size="xs"
                      className={BADGE_CHIP_CLASSNAME}
                    >
                      {row.error_category ?? 'other'}
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-right">
                  {row.response_time_s != null ? `${row.response_time_s.toFixed(2)}s` : '—'}
                </TableCell>
                <TableCell className="text-right">
                  {row.tokens_per_sec != null ? `${row.tokens_per_sec.toFixed(1)} tok/s` : '—'}
                </TableCell>
                <TableCell>
                  {(row.response_text || row.error_body) && (
                    <Button size="xs" variant="light" onClick={() => setSelected(row)}>
                      View
                    </Button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      <ResponseModal data={selected} onClose={() => setSelected(null)} />
    </Card>
  )
}
