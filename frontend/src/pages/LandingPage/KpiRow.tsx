import { Badge, Card, Metric, Title } from '@tremor/react'
import { BADGE_CHIP_CLASSNAME, colorForProvider } from '../../lib/chartColors'
import type { LandingKpis, SubtitleCounts } from '../../lib/queries'

type Props = {
  subtitle: SubtitleCounts
  kpis: LandingKpis
}

// Value and unit rendered as two separate lines now (big value, small
// italic unit underneath) rather than one combined string -- split
// into a pair so the JSX doesn't have to re-parse a formatted string.
function splitSeconds(value: number | null): { value: string; unit: string } {
  return value != null ? { value: value.toFixed(2), unit: 'seconds' } : { value: '—', unit: '' }
}

function splitThroughput(value: number | null): { value: string; unit: string } {
  return value != null ? { value: value.toFixed(1), unit: 'tok/s' } : { value: '—', unit: '' }
}

// Smaller than Tremor's stock Title (text-tremor-title, 18px) so
// "Models Available" fits on one line in its narrower column instead
// of wrapping to two -- confirmed live the 18px default wrapped there.
// -mt-[10px] pulls the header up against Tremor's Card's own 24px
// (p-6) top padding -- exact offset supplied directly against the
// reference layout, not derived, since Card's padding is a shared
// token every card in the app relies on and isn't something to change
// globally just for this row.
const HEADER_CLASSNAME = 'text-sm font-bold -mt-[10px]'

// All three headline numbers share this exact size (62px -- bigger
// than Tailwind's text-5xl/48px, matching the reference precisely)
// and weight so "17", "0.11", and "335.9" read as one consistent
// scale regardless of which element (Metric vs. a plain span) renders
// them.
const VALUE_CLASSNAME = 'text-[62px] font-semibold text-tremor-content-strong leading-none'
const UNIT_CLASSNAME = 'mt-[5px] text-center text-xs italic text-tremor-content'

export function KpiRow({ subtitle, kpis }: Props) {
  const bestResponse = splitSeconds(kpis.best_response_time_s)
  const bestThroughput = splitThroughput(kpis.best_throughput_tok_s)

  return (
    // Models Available at half its equal-thirds share (2fr of 12
    // total = 1/6, vs. the 4fr/12 = 1/3 each column got before), with
    // Best Response/Throughput splitting the freed-up space evenly
    // between them (5fr each). Same md breakpoint as every other
    // responsive grid in this app (see index.tsx's Top 5 tables), so
    // it still stacks to one full-width column below that.
    <div className="grid grid-cols-1 gap-4 md:grid-cols-[2fr_5fr_5fr]">
      <Card>
        <Title className={`${HEADER_CLASSNAME} text-center`}>Models Available</Title>
        <Metric className={`${VALUE_CLASSNAME} mt-2 text-center`}>{subtitle.working}</Metric>
        <p className={UNIT_CLASSNAME}>{subtitle.tracked} models tested</p>
      </Card>

      <Card>
        <Title className={HEADER_CLASSNAME}>Best Response</Title>
        <div className="mt-2 flex items-center justify-between gap-4">
          <div className="flex shrink-0 flex-col">
            <span className={VALUE_CLASSNAME}>{bestResponse.value}</span>
            {bestResponse.unit && <span className={UNIT_CLASSNAME}>{bestResponse.unit}</span>}
          </div>
          {kpis.best_response_model_slug && (
            // Name above, badge(s) below, both left-aligned -- badge
            // moved from beside the name to under it. The badge row is
            // its own flex-wrap container (not just the one Badge)
            // since more tags are expected here later; wrapping now
            // means a second/third tag won't need this restructured
            // again.
            <div className="flex min-w-0 flex-col items-start gap-1">
              {/* truncate (not wrap) -- a long unbroken segment like
                  "diffusiongemma" has no space/hyphen for the browser
                  to wrap at within the space this row actually has,
                  so normal wrapping just overflowed the card instead
                  of shrinking, confirmed live. min-w-0 lets this flex
                  item actually shrink; title keeps the full slug
                  available on hover, same pattern as the Top 5
                  tables' model-name column. */}
              <span
                className="min-w-0 max-w-full truncate text-sm font-bold text-tremor-content-strong"
                title={kpis.best_response_model_slug}
              >
                {kpis.best_response_model_slug}
              </span>
              {kpis.best_response_provider && (
                <div className="flex flex-wrap items-center gap-1">
                  <Badge
                    color={colorForProvider(kpis.best_response_provider)}
                    size="xs"
                    className={BADGE_CHIP_CLASSNAME}
                  >
                    {kpis.best_response_provider}
                  </Badge>
                </div>
              )}
            </div>
          )}
        </div>
      </Card>

      <Card>
        <Title className={HEADER_CLASSNAME}>Best Throughput</Title>
        <div className="mt-2 flex items-center justify-between gap-4">
          <div className="flex shrink-0 flex-col">
            <span className={VALUE_CLASSNAME}>{bestThroughput.value}</span>
            {bestThroughput.unit && <span className={UNIT_CLASSNAME}>{bestThroughput.unit}</span>}
          </div>
          {kpis.best_throughput_model_slug && (
            <div className="flex min-w-0 flex-col items-start gap-1">
              <span
                className="min-w-0 max-w-full truncate text-sm font-bold text-tremor-content-strong"
                title={kpis.best_throughput_model_slug}
              >
                {kpis.best_throughput_model_slug}
              </span>
              {kpis.best_throughput_provider && (
                <div className="flex flex-wrap items-center gap-1">
                  <Badge
                    color={colorForProvider(kpis.best_throughput_provider)}
                    size="xs"
                    className={BADGE_CHIP_CLASSNAME}
                  >
                    {kpis.best_throughput_provider}
                  </Badge>
                </div>
              )}
            </div>
          )}
        </div>
      </Card>
    </div>
  )
}
