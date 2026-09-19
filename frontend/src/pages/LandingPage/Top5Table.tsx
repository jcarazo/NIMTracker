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
import { useNavigate } from 'react-router-dom'
import { EmptyState } from '../../components/EmptyState'
import { BADGE_CHIP_CLASSNAME, colorForProvider } from '../../lib/chartColors'

// Row click-through to the model detail page -- design doc: the detail
// page is "reached by clicking a row in the Models table (or the
// landing page's Top 5 tables)". Added in Phase 5 once that page
// actually exists (until then this table had no link-through target).
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
  const navigate = useNavigate()

  return (
    <Card>
      <Title>{title}</Title>
      {rows.length === 0 ? (
        <EmptyState />
      ) : (
        // table-fixed (set via style, since Tremor's Table forwards
        // `className` to the scroll wrapper div, not the <table> itself
        // -- confirmed by reading its source) makes the header row's
        // width classes actually govern column width, unlike the
        // previous table-layout: auto default, which silently ignored
        // the model-name cell's max-w-[140px] cap (measured live:
        // rendered at 206px/177px, both still overflowing their own
        // content) and gave the short Provider/metric columns more
        // width than their content ever used.
        //
        // Provider is a fixed px width, not a %, sized to the widest
        // real provider badge ("DeepSeek AI", measured live at ~135px
        // including cell padding) -- a % column would grow/shrink with
        // every provider's badge width, which is exactly what produces
        // ragged-width badges; every provider's actual content need is
        // small and constant, so it doesn't need to scale with the
        // card. Model/Metric stay percentages (calculated against this
        // card's live ~496px width so Model keeps a real safety margin
        // over the longest real slug seen, 246px) so they still scale
        // with the card at other viewport widths, same as before.
        <Table className="mt-4" style={{ tableLayout: 'fixed' }}>
          <TableHead>
            <TableRow>
              <TableHeaderCell className="w-[51%]">Model</TableHeaderCell>
              <TableHeaderCell className="w-[140px]">Provider</TableHeaderCell>
              <TableHeaderCell className="w-[20%] text-right">{metricLabel}</TableHeaderCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row) => (
              <TableRow
                key={row.model_slug}
                tabIndex={0}
                role="link"
                aria-label={`View details for ${row.model_name}`}
                className="cursor-pointer hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-blue-500"
                onClick={() => navigate(`/models/${row.model_slug}`)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault()
                    navigate(`/models/${row.model_slug}`)
                  }
                }}
              >
                {/* 55% of the table's ~500px card width is still not
                    guaranteed to fit every real slug (up to 31 chars
                    seen live) -- truncate stays as a safety net, but
                    now against a column width driven by the header's
                    w-[55%], not an unenforced max-w on the cell. */}
                <TableCell className="truncate" title={row.model_name}>
                  {row.model_name}
                </TableCell>
                <TableCell>
                  {/* w-full fills the Provider column's fixed 140px
                      width (minus this cell's own padding) regardless
                      of provider-name length, and justify-center keeps
                      the label centered inside that fixed shape -- so
                      every badge reads as one aligned strip down the
                      column instead of ragged, text-length-sized pills. */}
                  <Badge
                    color={colorForProvider(row.provider)}
                    size="xs"
                    className={`${BADGE_CHIP_CLASSNAME} w-full justify-center`}
                  >
                    {row.provider}
                  </Badge>
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
