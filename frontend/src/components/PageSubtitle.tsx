import { Text } from '@tremor/react'
import type { SubtitleCounts } from '../lib/queries'

// "<N> models tracked, <M> models working" -- shared across every page
// (design_decisions.md, "Global page subtitle"). N is unfiltered; M is
// the same window-based distinct-count the landing page's "Models
// Available" KPI uses -- deliberately the same query result, passed
// down from the page rather than fetched twice.
type Props = {
  counts: SubtitleCounts | null
  loading: boolean
}

export function PageSubtitle({ counts, loading }: Props) {
  if (loading || !counts) {
    return <Text>Loading…</Text>
  }
  return (
    <Text>
      {counts.tracked} models tracked, {counts.working} models working
    </Text>
  )
}
