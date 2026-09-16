// Grafana-style time-range selector, shared across every page (Phase 4
// plan, per NIMTracker-implementation-plan.md section 9 and
// design_decisions.md's "Time filter" section). hours: null means "All
// time" -- no lower bound on the window.

export type TimeRangeOption = {
  label: string
  hours: number | null
}

export const TIME_RANGE_OPTIONS: TimeRangeOption[] = [
  { label: 'Last hour', hours: 1 },
  { label: 'Last 3 hours', hours: 3 },
  { label: 'Last 6 hours', hours: 6 },
  { label: 'Last 12 hours', hours: 12 },
  { label: 'Last 24 hours', hours: 24 },
  { label: 'Last 7 days', hours: 24 * 7 },
  { label: 'Last 30 days', hours: 24 * 30 },
  { label: 'All time', hours: null },
]

export const DEFAULT_TIME_RANGE = TIME_RANGE_OPTIONS.find((o) => o.label === 'Last 24 hours')!

// Returns an ISO timestamp for the window's lower bound, or null for
// "All time" -- matches the landing_* RPC functions' p_since parameter
// (NULL there means unbounded, same convention).
export function sinceTimestamp(hours: number | null): string | null {
  if (hours === null) return null
  return new Date(Date.now() - hours * 60 * 60 * 1000).toISOString()
}
