import { Card, Title } from '@tremor/react'
import { PolarAngleAxis, PolarGrid, PolarRadiusAxis, Radar, RadarChart, ResponsiveContainer } from 'recharts'
import { EmptyState } from '../../components/EmptyState'
import type { ModelDetailKpis, ModelDetailRadarBounds } from '../../lib/queries'

// Tailwind blue-500, matching chartColors.ts's PRIMARY_COLOR ('blue') --
// recharts takes real CSS colors, not Tremor's named-color abstraction.
const PRIMARY_HEX = '#3b82f6'

// 3-axis v1 (Reliability / Avg Response / Avg Throughput) -- the other
// three NIMStats axes (Intelligence/Reasoning/Coding Index) are
// Artificial-Analysis-dependent and deferred, per the design doc's
// explicit "don't block the whole chart on AA" decision. No Tremor
// radar component exists, so this uses recharts directly (already a
// transitive dependency via Tremor, pinned to the same version here).
//
// Response/Throughput axes are normalized to a 0-100 scale relative to
// the best AVG value any tracked model achieves in the window (best in
// class = 100) -- approved during Phase 5 planning as the way to make
// three incompatible raw scales/directions (a percentage; seconds,
// lower-is-better; tok/s, higher-is-better) comparable on one radius
// axis. Reliability needs no normalization, already 0-100.
//
// *** KNOWN BROKEN as of this commit -- recharts' RadarChart does not
// render correctly in this project's toolchain (Vite 8 / React 18.3.1 /
// esbuild pre-bundling), independent of anything in this file. Verified
// exhaustively: not the manual `domain`+`allowDataOverflow` approach
// (removed below in favor of plain auto-domain, itself also affected);
// not a literal 0 data value; not the two-series anchor trick used to
// pin a fixed [0,100] scale (also collapsed); not sibling charts on the
// page; not React StrictMode. The conclusive test: a bare, textbook
// RadarChart copy-pasted from recharts' own docs, mounted standalone
// with zero app code and a fixed-pixel-size container, ALSO renders
// with every point collapsed to the chart's exact center -- so this is
// an environment-level incompatibility with recharts' polar-chart
// family specifically (AreaChart/DonutChart/BarChart elsewhere in this
// app all render correctly), not anything fixable by adjusting this
// component's props or data. Needs a decision (recharts version bump,
// or replace this chart type) before this can ship working -- flag to
// Javier rather than re-attempting prop tweaks blindly; a lot of those
// were already tried and each seemed to work once before failing again
// on a genuinely cold reload, so any claimed fix here needs verifying
// on a full cache-cleared restart + brand-new tab, more than once,
// before being trusted.
type Props = {
  kpis: ModelDetailKpis
  bounds: ModelDetailRadarBounds
}

function normalizeInverse(value: number | null, best: number | null): number {
  if (value == null || best == null || value <= 0) return 0
  return Math.min(100, Math.round((best / value) * 100))
}

function normalizeDirect(value: number | null, best: number | null): number {
  if (value == null || best == null || best <= 0) return 0
  return Math.min(100, Math.round((value / best) * 100))
}

export function CapabilityRadar({ kpis, bounds }: Props) {
  const hasData = kpis.uptime_pct != null || kpis.avg_response_time_s != null || kpis.avg_tokens_per_sec != null

  // `anchor: 0` / `anchor: 100` on two of the three rows is not real
  // data -- it's an attempted fix (see the file-level comment above) for
  // pinning a fixed 0-100 scale via a second, invisible <Radar> series
  // sharing this axis, instead of relying on PolarRadiusAxis's `domain`
  // prop (confirmed unreliable). Currently STILL broken along with
  // everything else tried -- kept as the best-reasoned attempt so far,
  // not because it's confirmed working.
  const data = [
    { axis: 'Reliability', value: kpis.uptime_pct ?? 0, anchor: 0 },
    { axis: 'Avg Response', value: normalizeInverse(kpis.avg_response_time_s, bounds.best_avg_response_time_s), anchor: 100 },
    { axis: 'Avg Throughput', value: normalizeDirect(kpis.avg_tokens_per_sec, bounds.best_avg_tokens_per_sec) },
  ]

  return (
    <Card>
      <Title>Capability Radar</Title>
      {hasData ? (
        <div className="mt-4 h-64">
          <ResponsiveContainer width="100%" height="100%">
            <RadarChart data={data}>
              <PolarGrid />
              <PolarAngleAxis dataKey="axis" tick={{ fontSize: 12 }} />
              <PolarRadiusAxis tick={false} axisLine={false} />
              <Radar
                dataKey="anchor"
                stroke="transparent"
                fill="transparent"
                isAnimationActive={false}
                dot={false}
                activeDot={false}
              />
              <Radar dataKey="value" stroke={PRIMARY_HEX} fill={PRIMARY_HEX} fillOpacity={0.4} />
            </RadarChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <EmptyState />
      )}
    </Card>
  )
}
