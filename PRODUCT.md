# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary and effectively only user: Javier, the builder and sole operator. No auth, no accounts, no
multi-tenant concerns anywhere in the product — every design decision can assume exactly one user
context. The repo and the deployed GitHub Pages site are public, so strangers can find and judge it,
but no one else is expected to actually use it day-to-day; it exists for Javier's own monitoring.

## Product Purpose

NIMTracker discovers the current catalog of NVIDIA's free-tier NIM model endpoints once a day, then
probes every single one of them with a real chat-completions call once an hour. It turns that into a
small dashboard: which models are actually available right now, how their response time and
throughput compare, and — when something fails — exactly what kind of failure it was. Success means
Javier can answer "is this specific free model actually working today, and how fast" without
re-running probes by hand.

## Positioning

Built as a direct, evidence-driven fix to a reference tool (NIMStats) whose numbers were misleading.
Two mechanisms a copy that just re-skins the same approach could not truthfully claim:

- **No heuristic may ever prevent a model from being tested.** Every catalog-listed model gets a
  real hourly probe, unconditionally — never skipped because a tag or page layout heuristic guessed
  it wasn't a text model. Two such heuristics were tried and both were empirically disproven before
  this rule was adopted.
- **A real 7-value error taxonomy, never collapsed.** NIMStats blended everything into a single
  "success rate" that hid the difference between a model that has never once worked and one that's
  merely flaky. NIMTracker distinguishes `removed / rate_limited / degraded / timeout /
  server_error / empty_response / other`, and derives a model's Available/Removed/Degraded state
  live from real result history rather than a cached guess.

## Operating Context

Two scheduled backend jobs write directly to a Supabase Postgres database: a daily catalog-discovery
scrape (Playwright, against NVIDIA's live catalog page) and an hourly completions sweep (real API
calls to every tracked model, `httpx`, no in-run retries by design). Both are triggered by GitHub
Actions, now backed by an external Supabase pg_cron + pg_net trigger for reliability (GitHub's own
`schedule:` trigger proved unreliable in practice) with the original trigger kept as a redundant
backup. The frontend is a static React app on GitHub Pages that reads live data directly from
Supabase using the public anon key, secured by RLS rather than key secrecy.

Four pages today: an overview/landing dashboard, a Models list, a per-model detail page, and an
Executions log of every hourly sweep run (collapsed/expanded rows down to the individual model
result, including full raw response text).

## Capabilities and Constraints

- Zero auth, zero multi-tenancy — never design for a second user or a login state.
- Routing uses `HashRouter` (a deliberate GitHub Pages constraint, not an oversight) because no
  SPA-fallback routing exists yet for the site; `model.slug` values contain a literal `/`, so the
  model detail route is a splat, not a single param.
- Stack is pinned deliberately one version behind current: Tailwind v3 + Tremor 3.18.7, not the
  current majors, because Tremor's stable release requires React 18 and doesn't render correctly
  under Tailwind v4's engine. Don't "helpfully" upgrade without re-verifying Tremor has actually
  promoted a Tailwind-v4-compatible build to `latest`.
- **Known broken, not yet resolved:** the model detail page's Capability Radar chart
  (`recharts`' `RadarChart`) does not render in this project's toolchain — confirmed as an
  environment-level incompatibility, not a data or component-logic bug, after extensive isolated
  testing. Every other chart type in the app renders correctly. Don't attempt to "polish" this
  chart's current broken output; it needs a different chart implementation or a `recharts` version
  change before any visual work on it is meaningful.
- The 7-value error taxonomy is fixed and must never be collapsed or re-bucketed in any view — that
  collapse is the exact defect this project exists to correct.
- `excluded_non_text` (an intentional third resolution state) is currently unreachable in practice —
  every failure counts as a real error for v1. Don't design UI that assumes it's populated.

## Brand Commitments

"NIMTracker" is the final, binding name — not open for revisiting. No logo or established visual
identity exists yet; the deployed site's browser tab still shows the unedited Vite scaffold title
("frontend"), which is an oversight to fix, not a deliberate choice. Voice is purely functional and
utilitarian by design — no personality or character investment is wanted. That said, the project is
public-facing (public repo, public GitHub Pages URL, strangers may find and judge it), so the bar is
portfolio-quality craft and precision *within* a restrained, no-nonsense aesthetic — not an excuse
to under-invest in polish.

## Evidence on Hand

Real, live production data: dozens of tracked models across real providers (NVIDIA, Google, Meta,
Mistral AI, DeepSeek AI, Moonshotai, OpenAI, Poolside, and others), a genuine multi-day history of
hourly completions-sweep executions, and real success/failure/response-time data — no fabricated
testimonials, customers, pricing, or benchmarks apply; this isn't a commercial product and design
work must never invent any of those.

## Product Principles

- No heuristic ever gates testing — every tracked model gets probed every hour, unconditionally.
- The error taxonomy stays granular everywhere it's shown — never blend it back into a single
  pass/fail number, the mistake this project was built to fix.
- Availability state is always derived live from real result history, never cached or guessed.
- Public-facing portfolio-quality craft, delivered through precision and restraint rather than
  personality or decoration.
- Single-operator simplicity — no design decision needs to account for a second user or role.

## Accessibility & Inclusion

No specific personal need or compliance target confirmed. Build to a reasonable baseline (keyboard
navigation, sufficient contrast, semantic structure) rather than a named standard.
