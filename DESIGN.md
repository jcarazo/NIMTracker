---
name: NIMTracker
description: An instrument panel for NVIDIA's free NIM model endpoints — availability, latency, and throughput, read at a glance.
colors:
  primary: "#3b82f6"
  primary-active: "#2563eb"
  neutral-canvas: "#ffffff"
  neutral-border: "#e5e7eb"
  neutral-text-muted: "#6b7280"
  neutral-text-strong: "#111827"
  signal-emerald: "#10b981"
  signal-emerald-strong: "#059669"
  signal-rose: "#f43f5e"
  signal-rose-strong: "#e11d48"
  signal-amber: "#f59e0b"
  signal-amber-strong: "#d97706"
  signal-red: "#ef4444"
  signal-violet: "#8b5cf6"
  signal-sky: "#0ea5e9"
  signal-cyan: "#06b6d4"
  signal-orange: "#f97316"
  signal-pink: "#ec4899"
  signal-gray: "#9ca3af"
typography:
  metric:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "30px"
    fontWeight: 600
    lineHeight: "36px"
    letterSpacing: "normal"
  title:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 500
    lineHeight: "28px"
    letterSpacing: "normal"
  body:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "20px"
    letterSpacing: "normal"
  label:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: "20px"
    letterSpacing: "normal"
rounded:
  sm: "6px"
  md: "8px"
  full: "9999px"
spacing:
  gap-sm: "8px"
  gap-md: "16px"
  gap-lg: "24px"
  page-padding: "24px"
  card-padding: "24px"
components:
  card:
    backgroundColor: "{colors.neutral-canvas}"
    rounded: "{rounded.md}"
    padding: "24px"
  badge-positive:
    backgroundColor: "{colors.signal-emerald}"
    textColor: "{colors.signal-emerald-strong}"
    rounded: "{rounded.sm}"
    padding: "2px 10px"
  badge-caution:
    backgroundColor: "{colors.signal-amber}"
    textColor: "{colors.signal-amber-strong}"
    rounded: "{rounded.sm}"
    padding: "2px 10px"
  badge-critical:
    backgroundColor: "{colors.signal-rose}"
    textColor: "{colors.signal-rose-strong}"
    rounded: "{rounded.sm}"
    padding: "2px 10px"
  nav-link-active:
    textColor: "{colors.primary-active}"
    typography: "{typography.body}"
  nav-link-inactive:
    textColor: "{colors.neutral-text-muted}"
    typography: "{typography.body}"
---

# Design System: NIMTracker

## Overview

**Creative North Star: "The Instrument Panel"**

NIMTracker reads NVIDIA's free-tier model catalog once a day and probes every listed model with a
real completions call once an hour, then puts the results in front of one operator: dense,
legible readouts scanned at a glance, not a story told to a visitor. The visual system is Tremor's
stock component defaults, deliberately unadorned — white cards, a single restrained blue accent,
and a wide categorical palette that exists purely to encode data (which provider, which state,
which kind of failure), never for brand decoration. Nothing here performs; every color, weight, and
spacing value is load-bearing for reading the data faster.

This is a public repository and a public GitHub Pages site, so a stranger could find and judge it —
the bar is portfolio-quality precision, not portfolio-quality spectacle. Craft shows up in exact
alignment, a categorical palette engineered so no two adjacent series are confusable, and consistent
rhythm across four pages, not in flourish.

**Key Characteristics:**
- Flat white cards on a white canvas — depth is a single soft shadow plus a 1px border, never
  stacked layering.
- One brand accent (blue), used sparingly: the primary trend line and the active nav state. Every
  other color on screen is categorical data encoding, not brand expression.
- Numbers lead. The biggest, boldest text on every page is a metric value, not a heading.
- Uniform right-aligned numeric table columns and a repeated `max-w-6xl` page frame keep all four
  pages feeling like one instrument, not four separate screens.

## Colors

Two totally different color systems share this palette: a single restrained brand accent, and a
wide categorical set that exists only to distinguish data series (providers, health states, error
kinds) from one another at a glance.

### Primary
- **Signal Blue** (`#3b82f6`): the one brand accent. Used for the primary/aggregate trend line on
  the Overview chart and nowhere else as a "brand" color — this system doesn't reach for the accent
  to decorate; it reaches for it exactly once per view where an aggregate metric needs one line.
- **Signal Blue, Active** (`#2563eb`): the active-nav-item state (`text-blue-600`) — the one other
  place the brand color appears, always to mark "you are here," never as decoration.

### Neutral
- **Canvas White** (`#ffffff`): page and card background, uniformly, on every surface.
- **Hairline Gray** (`#e5e7eb`): the 1px card border and table row dividers. The system's only
  border color.
- **Muted Ink** (`#6b7280`): default body text, table values, subtitle counts — the resting text
  color for anything that isn't a headline number.
- **Strong Ink** (`#111827`): metric values, card/page titles, table header labels — reserved for
  what the operator should read first.

### Data Encoding (Categorical — not brand colors)

Ten hue families cover three independent categorical systems: **provider** (which company), **state**
(is this model working right now), and **error category** (what specifically went wrong). Verified
directly against the running app and live data, not assumed:

- **Provider never collides with state or error category on screen — confirmed structural
  separation, not luck.** Provider badges render only on the Models table and Top 5 tables;
  the state badge and Error Breakdown donut render only on the model detail page. No page shows a
  provider badge next to either of the other two.
- **State and error category are a different story: they share the model detail page, and two
  pairs reuse the literal same hex, not just a similar one.** `Degraded` (state) and `rate_limited`
  (error category) are both exactly `#f59e0b`; `Removed` (state) and `removed` (error category) are
  both exactly `#f43f5e`. Confirmed by direct swatch comparison, not color-distance reasoning.
  **Neither collision has actually been observed** — as of this writing, no tracked model is
  currently in `Removed` state, and `rate_limited` has never once fired in this project's history —
  but that's a data coincidence, not a design guarantee: a model that's `Degraded` right now and
  then hits `rate_limited`, or one whose `removed`-category failures push it into `Removed` state
  (the most likely real path there, since that's literally what sets a model's `Removed` state),
  would show its state badge and a donut slice in the identical color, on the identical page. Real,
  latent, not yet triggered — see Do's and Don'ts.

- **Signal Emerald** (`#10b981` / text `#059669`): NVIDIA (provider) · Available (state).
- **Signal Rose** (`#f43f5e` / text `#e11d48`): Removed (state) · `removed` (error category) — see
  the same-hex collision note above.
- **Signal Amber** (`#f59e0b` / text `#d97706`): Degraded (state) · OpenAI (provider) ·
  `rate_limited` (error category) — see the same-hex collision note above.
- **Signal Red** (`#ef4444`): Google (provider) · `server_error` (error category).
- **Signal Violet** (`#8b5cf6`): Meta (provider) · `timeout` (error category).
- **Signal Sky** (`#0ea5e9`): Moonshotai (provider).
- **Signal Cyan** (`#06b6d4`): DeepSeek AI (provider) · `empty_response` (error category).
- **Signal Orange** (`#f97316`): Poolside (provider) · `degraded` (error category) — visually
  distinct from Signal Amber's state/error use, confirmed by direct adjacent-swatch comparison
  (amber `#f59e0b` vs. orange `#f97316` read as clearly different hues side by side).
- **Signal Pink** (`#ec4899`): Mistral AI (provider).
- **Signal Gray** (`#9ca3af`): fallback for any provider not yet in the palette, and `other` /
  `unknown` everywhere — never a crash, never a dropped series, always a color.

### Named Rules

**The Data-Only Rule.** Every color outside Primary and Neutral exists to encode a specific data
value (a provider, a state, an error category). None of them are available for decoration,
emphasis, or a new UI affordance — introducing a new hue means introducing a new *data category*,
not a new visual accent.

**The Sparse Accent Rule.** Signal Blue appears in at most two places on any given screen: one
aggregate trend line, one active-nav indicator. If a screen needs the brand color a third time,
that's a sign something should be a Neutral or a Data Encoding color instead.

## Typography

**Body Font:** `ui-sans-serif, system-ui, sans-serif` (the system font stack — no custom webfont is
loaded anywhere in the app).

**Character:** One typeface, four weights, doing all the work through size and color rather than
font choice — consistent with an instrument panel that has no room for typographic personality.

### Hierarchy
- **Metric** (600, 30px/36px, Strong Ink): the single biggest text on any page — a KPI number
  ("19", "0.11s", "82.8%"). This is the true visual headline of every view, not a page `<h1>`.
- **Title** (500, 18px/28px, Strong Ink): card titles ("Capability Radar", "Performance vs Global
  Average") and page titles ("Models", "Executions"). The wordmark "NIMTracker" in the nav bar uses
  this same weight/size.
- **Body** (400, 14px/20px, Muted Ink): the default for everything else — subtitle counts, table
  cell values, chart labels.
- **Label** (600, 14px/20px, Strong Ink): table column headers only — same size as Body, distinguished
  by weight, not size, so headers stay part of the reading flow instead of shouting.

### Named Rules

**The Metric-Leads Rule.** The largest, boldest text on a page is always the number the operator
came to check, never a section headline. A card's `Title` is always smaller and lighter than the
`Metric` it introduces.

## Layout

Every page shares one frame: `mx-auto max-w-6xl` (1152px content width) with `24px` side padding
and `24px` vertical rhythm between major sections (`space-y-6`). The nav bar uses the identical
`max-w-6xl` frame at `24px`/`16px` padding, so its wordmark and links line up exactly with the page
content below on every route — the single strongest visual signal that all four pages are one
instrument, not four separate builds.

Multi-card sections use a `1`-column mobile / `2`-column desktop grid (`grid-cols-1 md:grid-cols-2`)
at a `16px` gap. Cards stack to full width below the `md` breakpoint; nothing in the system currently
addresses a breakpoint narrower than that beyond the grid collapsing to one column.

Tables are the densest layout element: numeric columns are uniformly right-aligned, label columns
left-aligned, and interactive rows (Models table, Executions collapsed rows) get a `hover:bg-gray-50`
tint plus `cursor-pointer` — the only hover feedback in the entire system besides link-underline.

## Elevation & Depth

Almost flat. A card is distinguished from the canvas by exactly two things: a 1px Hairline Gray
border and one soft, barely-there shadow (`0 1px 3px rgba(0,0,0,.1), 0 1px 2px -1px rgba(0,0,0,.1)`)
— Tremor's stock `tremor-card` shadow, unmodified. Nothing else in the system elevates: table rows,
badges, and the nav bar are all perfectly flat, differentiated by color and hairline borders alone.

### Shadow Vocabulary
- **Card** (`0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)`): the only shadow in the
  system, applied uniformly to every `Card` regardless of content.

### Named Rules

**The One-Shadow Rule.** There is exactly one elevation level. A design that reaches for a second,
heavier shadow to signal "more important" should reach for typography (Metric vs. Title) instead —
this system separates importance by size and color, never by stacking depth.

## Shapes

Two radii cover the whole system: `8px` on cards and containers, `6px` on badges — both noticeably
soft but never a full pill except where `9999px` is defined for a future circular affordance not yet
in use. No sharp corners anywhere; no shape is used to convey brand personality, only to soften a
dense grid of numbers.

## Components

### Cards
- **Shape:** `8px` radius, `1px` Hairline Gray border, uniform `24px` internal padding.
- **Background:** Canvas White, always — no tonal card-on-card layering exists in the system.
- **Shadow:** the single Card shadow (see Elevation), applied identically everywhere.

### Badges
- **Shape:** `6px` radius, `2px 10px` padding, `14px` text.
- **Color assignment:** always a Data Encoding color — background at the base hue's ~10% opacity
  tint, text at that hue's `-600` (strong) shade. Never a flat opaque fill; the soft tint is what
  keeps a row of ten different categorical badges from turning into visual noise.
- **Usage:** provider identity (Models table, Top 5 tables), model state (Uptime column, model
  detail state chip), error category (Error Breakdown, Run History status).

### Tables
- **Header:** `14px`/`600` Strong Ink, no uppercase transform, no visible rule beneath — separation
  comes from the header/body spacing alone, not a heavy border.
- **Rows:** Body-weight text, `1px` Hairline Gray divider between rows, numeric columns right-aligned.
- **Interactive rows:** `hover:bg-gray-50` + `cursor-pointer` on any row that expands or navigates
  (Models table → model detail, Executions collapsed → expanded detail).
- **Sparklines:** an inline `SparkAreaChart`, `96px × 32px`, colored to match that row's provider —
  the one place a Data Encoding color extends from a badge into a chart within the same row.

### Navigation
- **Style:** a single horizontal bar, `1px` Hairline Gray bottom border, sharing the page's
  `max-w-6xl` frame. Wordmark at Title weight/size; links at Body size, `500` weight.
- **States:** inactive links are Muted Ink with a `hover:text-gray-700` nudge; the active route is
  Signal Blue Active, with no underline or background — color alone marks "you are here."
- **Scope:** only top-level pages get a nav entry (Overview, Models, Executions). The model detail
  page is deliberately unlisted — it's reached only by clicking a row, never a nav item, which keeps
  the bar itself short and stable as the product grows.

### Time Range Selector
- **Style:** a standard Tremor `Select`, `max-w-xs`, shared verbatim across every page that filters
  by time. Never restyled per page — one control, one behavior, everywhere it appears.

## Do's and Don'ts

### Do:
- **Do** treat every non-Primary, non-Neutral color as data encoding first. Before introducing a new
  hue, ask what data value it represents.
- **Do** keep the `max-w-6xl` page frame and `24px`/`16px` spacing rhythm identical across every
  page, including any new one — it's the main thing making four independent pages read as one tool.
- **Do** let the Metric (30px/600) stay the largest text on a page. A new page's headline number
  belongs at Metric weight even if there's no room for a separate `<h1>`.
- **Do** use the soft-tint-background + strong-text badge pattern for any new categorical value
  (a new provider, a new state) — never a flat opaque badge fill.
- **Do** treat the state/error-category same-hex overlaps (`Degraded`↔`rate_limited`,
  `Removed`↔`removed`, both literally identical hex, see Colors) as an open item, not a closed
  question — the next time either combination shows up in real data, give the state badge and the
  donut a distinguishing cue (an icon, a border, a different shade) rather than letting two
  identical-colored elements sit on the same page unexamined.

### Don't:
- **Don't** add a second shadow depth, a gradient, or a decorative illustration anywhere — this is
  explicitly not meant to read as a marketing/SaaS landing surface (confirmed anti-reference); it's
  an operator's instrument, not a pitch.
- **Don't** spend the Primary blue on more than an aggregate trend line and the active-nav state in
  any single view. A third use of blue on one screen is a sign it should be a Neutral or Data
  Encoding color instead.
- **Don't** design around the model detail page's Capability Radar chart as if it renders — it is a
  confirmed, currently-broken `recharts` component (see PRODUCT.md); treat its current on-screen
  output as a defect to eventually replace, not a shape to match or polish.
- **Don't** give the model detail page its own nav entry — it stays reachable only via row
  click-through by product decision, not an oversight to "fix."
