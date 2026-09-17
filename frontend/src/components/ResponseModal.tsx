import { Dialog, DialogPanel, Text, Title } from '@tremor/react'

// Shared "view full response" modal -- used by the model detail page's
// Run History and the Executions page's expanded row, both of which
// need to show the exact same shape (a timestamp, a success/error
// title, and the raw response_text or error_body). Pulled out once
// both call sites needed the identical structure, not just a couple
// similar lines.
export type ResponseModalData = {
  started_at: string
  success: boolean
  error_category: string | null
  response_text: string | null
  error_body: string | null
}

type Props = {
  data: ResponseModalData | null
  onClose: () => void
}

export function ResponseModal({ data, onClose }: Props) {
  return (
    <Dialog open={data != null} onClose={onClose}>
      <DialogPanel>
        <Title>{data?.success ? 'Response' : `Error (${data?.error_category ?? 'other'})`}</Title>
        <Text className="mt-1">{data && new Date(data.started_at).toLocaleString()}</Text>
        <pre className="mt-4 max-h-96 overflow-auto whitespace-pre-wrap rounded bg-gray-50 p-3 text-sm">
          {data?.response_text || data?.error_body || '(empty)'}
        </pre>
      </DialogPanel>
    </Dialog>
  )
}
