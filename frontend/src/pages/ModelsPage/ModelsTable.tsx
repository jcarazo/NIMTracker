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

// Same "removed models don't get a real uptime number" rule as
// formatUptime, kept separate since the sort needs the raw number
// (or null) rather than a formatted string.
function uptimeSortValue(row: ModelsTableRow): number | null {
  return row.state === 'removed' ? null : row.uptime_pct
}

type SortKey = 'provider' | 'avg_response_time_s' | 'best_response_time_s' | 'best_tokens_per_sec' | 'uptime_pct'
type SortDirection = 'asc' | 'desc'
type Sort = { key: SortKey; direction: SortDirection }

function sortValue(row: ModelsTableRow, key: SortKey): string | number | null {
  switch (key) {
    case 'provider':
      return row.provider
    case 'avg_response_time_s':
      return row.avg_response_time_s
    case 'best_response_time_s':
      return row.best_response_time_s
    case 'best_tokens_per_sec':
      return row.best_tokens_per_sec
    case 'uptime_pct':
      return uptimeSortValue(row)
  }
}

// A small up/down caret pair -- the inactive direction stays a faint
// gray (still visible enough to signal "this column is sortable"
// without a hover), the active direction switches to the header's own
// text color via currentColor, so it darkens/lightens consistently
// with the header itself.
function SortIcon({ direction }: { direction: SortDirection | null }) {
  return (
    <svg viewBox="0 0 20 20" fill="none" className="h-3 w-3 shrink-0">
      <path
        d="M6 8l4-4 4 4"
        stroke={direction === 'asc' ? 'currentColor' : '#d1d5db'}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M6 12l4 4 4-4"
        stroke={direction === 'desc' ? 'currentColor' : '#d1d5db'}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function SortableHeaderCell({
  label,
  sortKey,
  sort,
  onSort,
  align = 'left',
}: {
  label: string
  sortKey: SortKey
  sort: Sort | null
  onSort: (key: SortKey) => void
  align?: 'left' | 'right'
}) {
  const active = sort?.key === sortKey
  return (
    <TableHeaderCell className={align === 'right' ? 'text-right' : ''}>
      <button
        type="button"
        onClick={() => onSort(sortKey)}
        className={`inline-flex items-center gap-1 hover:text-tremor-brand ${align === 'right' ? 'flex-row-reverse' : ''}`}
      >
        {label}
        <SortIcon direction={active ? sort.direction : null} />
      </button>
    </TableHeaderCell>
  )
}

type Props = {
  rows: ModelsTableRow[]
  sparklinesByModel: Record<string, SparklinePoint[]>
}

export function ModelsTable({ rows, sparklinesByModel }: Props) {
  const [nameFilter, setNameFilter] = useState('')
  const [sort, setSort] = useState<Sort | null>(null)
  const navigate = useNavigate()

  function handleSort(key: SortKey) {
    setSort((prev) => (prev?.key === key ? { key, direction: prev.direction === 'asc' ? 'desc' : 'asc' } : { key, direction: 'asc' }))
  }

  const filteredRows = useMemo(() => {
    const q = nameFilter.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((row) => row.model_name.toLowerCase().includes(q) || row.provider.toLowerCase().includes(q))
  }, [rows, nameFilter])

  // Missing data (a model with no results yet, or a Removed model's
  // uptime) sorts to the bottom regardless of direction -- "no data"
  // isn't meaningfully high or low, and burying it under real numbers
  // either way keeps flipping the sort direction from constantly
  // shuffling those rows to the opposite end.
  const sortedRows = useMemo(() => {
    if (!sort) return filteredRows
    const { key, direction } = sort
    const factor = direction === 'asc' ? 1 : -1
    return [...filteredRows].sort((a, b) => {
      const av = sortValue(a, key)
      const bv = sortValue(b, key)
      if (av == null && bv == null) return 0
      if (av == null) return 1
      if (bv == null) return -1
      if (typeof av === 'string' && typeof bv === 'string') return av.localeCompare(bv) * factor
      return ((av as number) - (bv as number)) * factor
    })
  }, [filteredRows, sort])

  return (
    <div className="space-y-4">
      <TextInput
        placeholder="Filter by model name..."
        value={nameFilter}
        onValueChange={setNameFilter}
        className="max-w-sm"
      />

      <Card>
        {sortedRows.length === 0 ? (
          <EmptyState message={rows.length === 0 ? 'No models seen yet.' : 'No models match this filter.'} />
        ) : (
          <Table>
            {/* Distinct from the body rows -- a tinted background plus
                a slightly heavier bottom border, not just the
                weight/color contrast DESIGN.md's Label style already
                gives header text. */}
            <TableHead>
              <TableRow className="border-b-2 border-tremor-border bg-gray-50">
                <TableHeaderCell>Model</TableHeaderCell>
                <SortableHeaderCell label="Provider" sortKey="provider" sort={sort} onSort={handleSort} />
                <SortableHeaderCell label="Avg Time" sortKey="avg_response_time_s" sort={sort} onSort={handleSort} align="right" />
                <SortableHeaderCell label="Best Time" sortKey="best_response_time_s" sort={sort} onSort={handleSort} align="right" />
                <SortableHeaderCell label="Throughput" sortKey="best_tokens_per_sec" sort={sort} onSort={handleSort} align="right" />
                <TableHeaderCell>Trend</TableHeaderCell>
                <SortableHeaderCell label="Uptime" sortKey="uptime_pct" sort={sort} onSort={handleSort} />
              </TableRow>
            </TableHead>
            <TableBody>
              {sortedRows.map((row) => {
                const sparkline = sparklinesByModel[row.model_slug] ?? []
                return (
                  <TableRow
                    key={row.model_slug}
                    className="cursor-pointer hover:bg-gray-50"
                    onClick={() => navigate(`/models/${row.model_slug}`)}
                  >
                    <TableCell>
                      <span className="max-w-[160px] truncate" title={row.model_name}>
                        {row.model_name}
                      </span>
                    </TableCell>
                    <TableCell>
                      {/* Fixed width (not just size="xs") so every
                          provider badge renders identically sized
                          regardless of name length ("Z.AI" vs "DEEPSEEK
                          AI") -- justify-center keeps the label centered
                          inside that fixed shape, same technique as the
                          Top 5 tables' Provider column. */}
                      <Badge
                        color={colorForProvider(row.provider)}
                        size="xs"
                        className={`${BADGE_CHIP_CLASSNAME} w-[110px] justify-center`}
                      >
                        {row.provider}
                      </Badge>
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
                      <Text>{formatUptime(row)}</Text>
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        )}
      </Card>
    </div>
  )
}
