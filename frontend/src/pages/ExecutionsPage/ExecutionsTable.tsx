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
  Text,
} from '@tremor/react'
import { Fragment, useState } from 'react'
import { EmptyState } from '../../components/EmptyState'
import { ResponseModal, type ResponseModalData } from '../../components/ResponseModal'
import { colorForErrorCategory, colorForProvider } from '../../lib/chartColors'
import { fetchExecutionDetail, type ExecutionDetailRow, type ExecutionListRow } from '../../lib/queries'

type DetailState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; rows: ExecutionDetailRow[] }

// `onView` is passed down rather than each row owning its own modal
// state -- the modal itself must render OUTSIDE <Table>/<TableBody>
// (see ExecutionsTable below for why: Tremor's Dialog renders a <span>,
// which is invalid directly inside <tbody> and silently corrupts the
// DOM, confirmed via a real `validateDOMNesting` console warning during
// testing -- not a click-targeting issue, an actual invalid-HTML bug).
// `startedAt` is the PARENT execution's timestamp -- ExecutionDetailRow
// has no timestamp of its own (every model row within one execution
// shares the same run), so it has to be threaded through explicitly
// for the response modal to show anything but "Invalid Date".
function ExpandedDetail({
  state,
  startedAt,
  onView,
}: {
  state: DetailState
  startedAt: string
  onView: (row: ResponseModalData) => void
}) {
  if (state.status === 'loading') {
    return (
      <TableRow>
        <TableCell colSpan={4}>
          <Text>Loading…</Text>
        </TableCell>
      </TableRow>
    )
  }
  if (state.status === 'error') {
    return (
      <TableRow>
        <TableCell colSpan={4}>
          <Text className="text-red-600">Failed to load: {state.message}</Text>
        </TableCell>
      </TableRow>
    )
  }
  if (state.rows.length === 0) {
    return (
      <TableRow>
        <TableCell colSpan={4}>
          <EmptyState message="No tested models in this execution." />
        </TableCell>
      </TableRow>
    )
  }

  return (
    <>
      {state.rows.map((row) => (
        <TableRow key={row.model_slug} className="bg-gray-50">
          <TableCell>
            <div className="flex items-center gap-2 pl-6">
              <span>{row.model?.model_name ?? row.model_slug}</span>
              {row.model?.provider && <Badge color={colorForProvider(row.model.provider)}>{row.model.provider}</Badge>}
            </div>
          </TableCell>
          <TableCell>
            {row.success ? (
              <Badge color="emerald">Success</Badge>
            ) : (
              <Badge color={colorForErrorCategory(row.error_category ?? 'other')}>{row.error_category ?? 'other'}</Badge>
            )}
          </TableCell>
          <TableCell className="text-right">
            {row.response_time_s != null ? `${row.response_time_s.toFixed(2)}s` : '—'}
          </TableCell>
          <TableCell className="text-right">
            {row.tokens_per_sec != null ? `${row.tokens_per_sec.toFixed(1)} tok/s` : '—'}
            {(row.response_text || row.error_body) && (
              <Button size="xs" variant="light" className="ml-2" onClick={() => onView({ ...row, started_at: startedAt })}>
                View
              </Button>
            )}
          </TableCell>
        </TableRow>
      ))}
    </>
  )
}

export function ExecutionsTable({ rows }: { rows: ExecutionListRow[] }) {
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [detailById, setDetailById] = useState<Record<string, DetailState>>({})
  const [selected, setSelected] = useState<ResponseModalData | null>(null)

  function toggle(id: string) {
    if (expandedId === id) {
      setExpandedId(null)
      return
    }
    setExpandedId(id)
    if (!detailById[id]) {
      setDetailById((prev) => ({ ...prev, [id]: { status: 'loading' } }))
      fetchExecutionDetail(id)
        .then((detailRows) => setDetailById((prev) => ({ ...prev, [id]: { status: 'ready', rows: detailRows } })))
        .catch((err: unknown) =>
          setDetailById((prev) => ({
            ...prev,
            [id]: { status: 'error', message: err instanceof Error ? err.message : String(err) },
          })),
        )
    }
  }

  return (
    <Card>
      {rows.length === 0 ? (
        <EmptyState />
      ) : (
        <Table>
          <TableHead>
            <TableRow>
              <TableHeaderCell>Started At</TableHeaderCell>
              <TableHeaderCell className="text-right">Tested</TableHeaderCell>
              <TableHeaderCell className="text-right">OK</TableHeaderCell>
              <TableHeaderCell>Fastest</TableHeaderCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row) => (
              <Fragment key={row.id}>
                <TableRow className="cursor-pointer hover:bg-gray-50" onClick={() => toggle(row.id)}>
                  <TableCell>{new Date(row.started_at).toLocaleString()}</TableCell>
                  <TableCell className="text-right">{row.models_tested_count}</TableCell>
                  <TableCell className="text-right">{row.models_succeeded_count}</TableCell>
                  <TableCell>
                    {row.fastest_model_slug ? (
                      <span>
                        {row.fastest_model_slug} · {row.fastest_response_time_s}s
                      </span>
                    ) : (
                      '—'
                    )}
                  </TableCell>
                </TableRow>
                {expandedId === row.id && (
                  <ExpandedDetail
                    state={detailById[row.id] ?? { status: 'loading' }}
                    startedAt={row.started_at}
                    onView={setSelected}
                  />
                )}
              </Fragment>
            ))}
          </TableBody>
        </Table>
      )}
      <ResponseModal data={selected} onClose={() => setSelected(null)} />
    </Card>
  )
}
