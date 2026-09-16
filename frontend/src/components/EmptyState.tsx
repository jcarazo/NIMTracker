import { Text } from '@tremor/react'

// Distinguishes "genuinely no data in this window" from a broken chart
// -- worth being explicit about given how little live data exists
// right now (the completions sweep isn't on a schedule yet -- see
// CLAUDE.md, "Current state"). Widening the time range is the real fix,
// not a bug report.
export function EmptyState({ message = 'No data in this time range.' }: { message?: string }) {
  return (
    <div className="flex h-40 items-center justify-center">
      <Text>{message} Try a wider time range.</Text>
    </div>
  )
}
