import { useEffect, useState } from 'react'
import {
  fetchExecutionsList,
  fetchSubtitleCounts,
  type ExecutionListRow,
  type SubtitleCounts,
} from '../../lib/queries'

type ExecutionsPageData = {
  subtitle: SubtitleCounts
  rows: ExecutionListRow[]
}

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; data: ExecutionsPageData }

export function useExecutionsPageData(since: string | null): State {
  const [state, setState] = useState<State>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    setState({ status: 'loading' })

    Promise.all([fetchSubtitleCounts(since), fetchExecutionsList(since)])
      .then(([subtitle, rows]) => {
        if (cancelled) return
        setState({ status: 'ready', data: { subtitle, rows } })
      })
      .catch((err: unknown) => {
        if (cancelled) return
        setState({ status: 'error', message: err instanceof Error ? err.message : String(err) })
      })

    return () => {
      cancelled = true
    }
  }, [since])

  return state
}
