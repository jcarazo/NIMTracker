import { Card, Title, Tracker } from '@tremor/react'
import { EmptyState } from '../../components/EmptyState'
import { colorForState, labelForState } from '../../lib/chartColors'
import type { HeatmapCell } from '../../lib/queries'

// One cell per execution this model was actually tested in, colored by
// its state *as of that execution's timestamp* -- the one consumer that
// needs model_state_as_of()'s "state at time T" shape, not just "state
// right now". Third color for Removed, distinct from Available/Degraded
// -- the design doc's explicit fix for NIMStats' binary up/down heatmap.
// Tremor's Tracker (a strip of colored blocks with per-cell tooltips) is
// built for exactly this and handles long windows (hundreds of cells)
// fine without any bucketing/downsampling.
export function AvailabilityHeatmap({ cells }: { cells: HeatmapCell[] }) {
  return (
    <Card>
      <Title>Availability Heatmap</Title>
      {cells.length === 0 ? (
        <EmptyState />
      ) : (
        <Tracker
          className="mt-4"
          data={cells.map((cell) => ({
            color: colorForState(cell.state),
            tooltip: `${new Date(cell.started_at).toLocaleString()}: ${labelForState(cell.state)}`,
          }))}
        />
      )}
    </Card>
  )
}
