import {
  Badge,
  Card,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeaderCell,
  TableRow,
  Text,
} from '@tremor/react'
import { useState } from 'react'
import { EmptyState } from '../../components/EmptyState'
import { ResponseModal, type ResponseModalData } from '../../components/ResponseModal'
import { BADGE_CHIP_CLASSNAME, colorForErrorCategory, colorForProvider, type TremorColor } from '../../lib/chartColors'
import { fetchExecutionDetail, type ExecutionDetailRow, type ExecutionListRow } from '../../lib/queries'

// The hourly completions sweep always sends this exact prompt to every
// model (backend/nimtracker/completions_probe.py's DEFAULT_PROMPT) --
// a single fixed constant, not stored per-execution in the DB, so it's
// safe (and the only option) to mirror it here rather than fetch it.
const PROBE_PROMPT = 'Write a Python function that checks if a number is prime and returns True or False'

function ChevronIcon({ expanded }: { expanded: boolean }) {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={`h-4 w-4 shrink-0 text-tremor-content transition-transform ${expanded ? 'rotate-180' : ''}`}
    >
      <path d="M5 7.5l5 5 5-5" />
    </svg>
  )
}

function LightningIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" className="h-3.5 w-3.5 shrink-0 text-amber-500">
      <path d="M11 2 3 12h5l-1 6 8-10h-5l1-6Z" />
    </svg>
  )
}

// A "view raw output" action, replacing the old text Button -- compact
// enough to sit as its own trailing table column without widening it.
function MonitorIcon() {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.6}
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-4 w-4"
    >
      <rect x="2.5" y="3.5" width="15" height="10" rx="1.5" />
      <path d="M7 17h6M10 13.5V17" />
    </svg>
  )
}

// "9/19/2026, 11:07" -- same date format .toLocaleString() already
// used (locale-aware M/D/YYYY), but time truncated to 24h HH:MM: no
// seconds (irrelevant at hourly-sweep granularity) and no AM/PM
// (ambiguous at a glance against the reference's 24h "21:00" style).
function formatExecutionTimestamp(iso: string): string {
  const d = new Date(iso)
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return `${d.toLocaleDateString()}, ${hh}:${mm}`
}

// Reuses the same three-tier semantic coloring as model state
// (Available/Degraded/Removed -- emerald/amber/rose) rather than
// inventing a new color rule, so a run's health reads consistently
// with how health is colored everywhere else in the app.
function ratioColor(succeeded: number, tested: number): TremorColor {
  if (tested === 0) return 'gray'
  const rate = succeeded / tested
  if (rate >= 0.7) return 'emerald'
  if (rate >= 0.4) return 'amber'
  return 'rose'
}

type DetailState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; rows: ExecutionDetailRow[] }

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
  if (state.status === 'loading') return <Text>Loading…</Text>
  if (state.status === 'error') return <Text className="text-red-600">Failed to load: {state.message}</Text>
  if (state.rows.length === 0) return <EmptyState message="No tested models in this execution." />

  return (
    <Table>
      <TableHead>
        <TableRow>
          <TableHeaderCell>Model</TableHeaderCell>
          <TableHeaderCell>Provider</TableHeaderCell>
          <TableHeaderCell>Status</TableHeaderCell>
          <TableHeaderCell className="text-right">Response Time</TableHeaderCell>
          <TableHeaderCell className="text-right">Tok/s</TableHeaderCell>
          <TableHeaderCell />
        </TableRow>
      </TableHead>
      <TableBody>
        {state.rows.map((row) => (
          <TableRow key={row.model_slug}>
            <TableCell>{row.model?.model_name ?? row.model_slug}</TableCell>
            <TableCell>
              {row.model?.provider && (
                <Badge color={colorForProvider(row.model.provider)} size="xs" className={BADGE_CHIP_CLASSNAME}>
                  {row.model.provider}
                </Badge>
              )}
            </TableCell>
            <TableCell>
              {row.success ? (
                <Badge color="emerald" size="xs" className={BADGE_CHIP_CLASSNAME}>
                  Success
                </Badge>
              ) : (
                <Badge color={colorForErrorCategory(row.error_category ?? 'other')} size="xs" className={BADGE_CHIP_CLASSNAME}>
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
                <button
                  type="button"
                  aria-label={`View ${row.success ? 'response' : 'error'} for ${row.model?.model_name ?? row.model_slug}`}
                  onClick={() => onView({ ...row, started_at: startedAt })}
                  className="text-tremor-content hover:text-tremor-brand"
                >
                  <MonitorIcon />
                </button>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

// One Card per execution -- "individual entities per row, clearly
// delimited" -- rather than the previous single Table where every run
// was just a thin, easy-to-miss row. Only the summary bar's button is
// the toggle; the expanded detail (prompt + per-model table) renders
// below it inside the same Card.
function ExecutionRow({
  row,
  expanded,
  detail,
  onToggle,
  onView,
}: {
  row: ExecutionListRow
  expanded: boolean
  detail: DetailState | undefined
  onToggle: () => void
  onView: (row: ResponseModalData) => void
}) {
  return (
    <Card className="p-4">
      <button type="button" onClick={onToggle} className="flex w-full items-center justify-between gap-4 text-left">
        <div className="flex shrink-0 items-center gap-3">
          <span className="text-sm font-semibold text-tremor-content-strong">
            {formatExecutionTimestamp(row.started_at)}
          </span>
          <Badge
            color={ratioColor(row.models_succeeded_count, row.models_tested_count)}
            size="xs"
            className={BADGE_CHIP_CLASSNAME}
          >
            {row.models_succeeded_count}/{row.models_tested_count}
          </Badge>
        </div>
        <div className="flex min-w-0 items-center gap-3">
          {row.fastest_model_slug && (
            <span className="flex min-w-0 items-center gap-1.5 text-sm text-tremor-content">
              <LightningIcon />
              <span className="truncate font-medium text-tremor-content-strong">{row.fastest_model_slug}</span>
              <span className="shrink-0">· {row.fastest_response_time_s}s</span>
            </span>
          )}
          <ChevronIcon expanded={expanded} />
        </div>
      </button>

      {expanded && (
        <div className="mt-4 border-t border-tremor-border pt-4">
          <Text>
            <span className="font-semibold text-tremor-content-strong">Prompt: </span>
            {PROBE_PROMPT}
          </Text>
          <div className="mt-4">
            <ExpandedDetail state={detail ?? { status: 'loading' }} startedAt={row.started_at} onView={onView} />
          </div>
        </div>
      )}
    </Card>
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

  if (rows.length === 0) {
    return (
      <Card>
        <EmptyState />
      </Card>
    )
  }

  return (
    <div className="space-y-3">
      {rows.map((row) => (
        <ExecutionRow
          key={row.id}
          row={row}
          expanded={expandedId === row.id}
          detail={detailById[row.id]}
          onToggle={() => toggle(row.id)}
          onView={setSelected}
        />
      ))}
      <ResponseModal data={selected} onClose={() => setSelected(null)} />
    </div>
  )
}
