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

// Compact "chip" treatment applied to every Badge in the app, matching
// the proportions of NIMStats' own provider-chip (the predecessor tool
// this project replaces) rather than Tremor's stock Badge size, which
// read as oversized once badges started appearing densely (the Top 5
// tables' Provider column in particular). Pair with Tremor's `size="xs"`
// prop, which already gives the right padding (px-2 py-0.5 = NIMStats'
// literal `2px 8px`) -- this constant only needs to override what `xs`
// doesn't cover: font-size down to 10px (below Tailwind's smallest
// preset, text-xs, which is 12px), weight, case, tracking, and a
// tighter 4px radius than Tremor's own 6px `rounded-tremor-small`.
// Every value here is a standard Tailwind utility group (font-size,
// font-weight, radius), which tailwind-merge already recognizes as
// conflicting with Tremor's own classes and overrides correctly without
// needing `!important` -- confirmed live, unlike the AvailabilityChart
// TabList fix, which needed `!` because that was a runtime-constructed
// `data-[selected]:` class Tailwind's JIT scanner can't see at all.
export const BADGE_CHIP_CLASSNAME = 'text-[10px] font-bold uppercase tracking-[0.5px] rounded-[4px]'

const FALLBACK_PROVIDER_COLOR: TremorColor = 'gray'

// A provider not in the map above (a new one the catalog job picked up
// since this list was written) still gets a color, just not a
// deliberately-chosen one -- never crashes, never silently drops a
// series.
export function colorForProvider(provider: string): TremorColor {
  return PROVIDER_COLORS[provider] ?? FALLBACK_PROVIDER_COLOR
}

// model_state_as_of()'s three possible return values, plus the
// frontend-only 'unknown' fallback for a null/never-computed state.
// Used by the Models table's UPTIME badge, the model detail page's
// state chip, and the Availability Heatmap -- one mapping so all three
// agree on what "removed" looks like (Phase 5: design doc calls for a
// visually distinct third state, not a binary up/down).
export type ModelState = 'available' | 'degraded' | 'removed' | 'unknown'

export const STATE_COLORS: Record<ModelState, TremorColor> = {
  available: 'emerald',
  degraded: 'amber',
  removed: 'rose',
  unknown: 'gray',
}

export const STATE_LABELS: Record<ModelState, string> = {
  available: 'Available',
  degraded: 'Degraded',
  removed: 'Removed',
  unknown: 'Unknown',
}

export function colorForState(state: string | null | undefined): TremorColor {
  return STATE_COLORS[(state as ModelState) ?? 'unknown'] ?? STATE_COLORS.unknown
}

export function labelForState(state: string | null | undefined): string {
  return STATE_LABELS[(state as ModelState) ?? 'unknown'] ?? STATE_LABELS.unknown
}

// The full validated error taxonomy (CLAUDE.md, "Error taxonomy") --
// fixed 7-value palette for the Error Breakdown donut, spread across
// distinct hues the same way PROVIDER_COLORS is, so no two slices read
// as "basically the same color" the way the first provider-palette pass
// didn't (see that fix above).
export const ERROR_CATEGORY_COLORS: Record<string, TremorColor> = {
  removed: 'rose',
  rate_limited: 'amber',
  degraded: 'orange',
  timeout: 'violet',
  server_error: 'red',
  empty_response: 'cyan',
  other: 'gray',
}

export function colorForErrorCategory(category: string): TremorColor {
  return ERROR_CATEGORY_COLORS[category] ?? 'gray'
}
