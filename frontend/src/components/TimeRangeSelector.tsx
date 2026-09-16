import { Select, SelectItem } from '@tremor/react'
import { TIME_RANGE_OPTIONS, type TimeRangeOption } from '../lib/timeRange'

type Props = {
  selected: TimeRangeOption
  onChange: (option: TimeRangeOption) => void
}

export function TimeRangeSelector({ selected, onChange }: Props) {
  return (
    <Select
      value={selected.label}
      onValueChange={(label) => {
        const option = TIME_RANGE_OPTIONS.find((o) => o.label === label)
        if (option) onChange(option)
      }}
      className="max-w-xs"
      enableClear={false}
    >
      {TIME_RANGE_OPTIONS.map((option) => (
        <SelectItem key={option.label} value={option.label}>
          {option.label}
        </SelectItem>
      ))}
    </Select>
  )
}
