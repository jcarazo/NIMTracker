// Minimal shared color config -- a sensible fixed palette, not a design
// pass. Used everywhere a provider is shown: the By-Provider trend
// chart, and every provider Badge (KPI cards, Top 5 tables) -- applying
// it to only the chart and leaving Badges on Tremor's default color was
// a real gap caught in browser testing, not a deliberate scope choice.
// Provider names confirmed against the live `model` table (not
// guessed): 'DeepSeek AI' and 'Mistral AI' in particular don't match
// their slug prefixes ("deepseek-ai", "mistralai"), so this list is
// only trustworthy because it was queried, not assumed.
//
// Tremor's `color` prop (Badge, AreaChart `colors`, etc.) only accepts
// this fixed set of Tailwind-ish color names (see tailwind.config.js's
// safelist, which exists specifically so these actually render).

export type TremorColor =
  | 'slate' | 'gray' | 'zinc' | 'neutral' | 'stone'
  | 'red' | 'orange' | 'amber' | 'yellow' | 'lime' | 'green' | 'emerald'
  | 'teal' | 'cyan' | 'sky' | 'blue' | 'indigo' | 'violet' | 'purple'
  | 'fuchsia' | 'pink' | 'rose'

// The single-series "Models Available Over Time" aggregate line --
// deliberately not reused below, even though the two views are never
// shown at once, so the palette reads as consistent if that ever changes.
export const PRIMARY_COLOR: TremorColor = 'blue'

// Revised after real-browser feedback: the first pass (sky/teal/emerald
// for Google/OpenAI/NVIDIA) clustered three providers in the same
// blue-green hue range and was hard to tell apart at a glance -- fixed
// by picking one clearly-different color *family* per provider instead
// of nearby shades of the same family. The 5 providers that actually
// co-occur in the current live data (Google, Meta, Moonshotai, NVIDIA,
// OpenAI) are deliberately the most spread-out: red, violet, sky,
// emerald, amber -- none adjacent on the color wheel.
export const PROVIDER_COLORS: Record<string, TremorColor> = {
  NVIDIA: 'emerald',
  Google: 'red',
  Meta: 'violet',
  OpenAI: 'amber',
  Moonshotai: 'sky',
  'DeepSeek AI': 'cyan',
  Poolside: 'orange',
  'Mistral AI': 'pink',
}

const FALLBACK_PROVIDER_COLOR: TremorColor = 'gray'

// A provider not in the map above (a new one the catalog job picked up
// since this list was written) still gets a color, just not a
// deliberately-chosen one -- never crashes, never silently drops a
// series.
export function colorForProvider(provider: string): TremorColor {
  return PROVIDER_COLORS[provider] ?? FALLBACK_PROVIDER_COLOR
}
