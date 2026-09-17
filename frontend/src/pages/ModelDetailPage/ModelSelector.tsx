import { Select, SelectItem } from '@tremor/react'
import { useNavigate } from 'react-router-dom'
import type { ModelSelectorOption } from '../../lib/queries'

// Lists only models satisfying "seen at least once" WITHIN the current
// time window (model_selector_options), not all-time -- deliberately
// different from the Models table's all-time rule, per the design doc:
// a model with no in-window activity would just show empty charts here.
type Props = {
  options: ModelSelectorOption[]
  currentSlug: string
}

export function ModelSelector({ options, currentSlug }: Props) {
  const navigate = useNavigate()

  return (
    <Select value={currentSlug} onValueChange={(slug) => navigate(`/models/${slug}`)} className="max-w-sm">
      {options.map((option) => (
        <SelectItem key={option.model_slug} value={option.model_slug}>
          {option.model_name} ({option.provider})
        </SelectItem>
      ))}
    </Select>
  )
}
