import { useMemo, useState } from 'react'
import { DEFAULT_TIME_RANGE, sinceTimestamp, type TimeRangeOption } from '../lib/timeRange'

// Shared time-range state -- every page that adopts this hook reads
// from the same selection, per design_decisions.md's "Time filter"
// section ("applies to landing page and likely others").
//
// `since` MUST be memoized on selected.hours, not recomputed on every
// render -- sinceTimestamp() calls Date.now() internally, so an
// unmemoized version produces a new (millisecond-different) string on
// every render. That new value fails the useEffect dependency check in
// useLandingPageData on the NEXT render too, re-triggering the fetch,
// which sets loading state, which re-renders, which produces yet
// another new `since` -- a real infinite refetch loop, caught by
// actually loading the page in a browser (requests never resolved to
// 'ready', stuck on "Loading..." indefinitely).
export function useTimeRange() {
  const [selected, setSelected] = useState<TimeRangeOption>(DEFAULT_TIME_RANGE)
  const since = useMemo(() => sinceTimestamp(selected.hours), [selected.hours])

  return { selected, setSelected, since }
}
