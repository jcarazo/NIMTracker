import { Badge } from '@tremor/react'
import { BADGE_CHIP_CLASSNAME, colorForState, labelForState } from '../lib/chartColors'

// Shared Available/Degraded/Removed(/Unknown) indicator -- the Models
// table's reworked UPTIME column and the model detail page's state chip
// both render the exact same three-state badge (design doc: replaces
// NIMStats' binary uptime number, which hid the distinction between
// "never worked" and "flaky but still alive").
export function StateBadge({ state }: { state: string | null | undefined }) {
  return (
    <Badge color={colorForState(state)} size="xs" className={BADGE_CHIP_CLASSNAME}>
      {labelForState(state)}
    </Badge>
  )
}
