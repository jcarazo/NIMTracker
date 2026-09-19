---
target: Landing page
total_score: 29
max_score: 36
na_heuristics: 10
p0_count: 0
p1_count: 1
target_identity: "file:/Users/javier/Development/NIMTracker/frontend/src/pages/LandingPage"
timestamp: 2026-09-18T12-53-31Z
slug: frontend-src-pages-landingpage
---
Method: dual-agent (Assessment A and B run as separate isolated subagents, each blind to the prior critique and to each other's output)

## Design Health Score (Operate mode — heuristic 10 marked n/a: no help system, by design, for a single-operator dashboard)

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | By-Provider tab briefly renders blank (recharts 0x0-container warning) before self-correcting |
| 2 | Match System / Real World | 3 | NVIDIA's dominant scale compresses the other six providers into an unreadable band |
| 3 | User Control and Freedom | 4 | Time range, tab toggle, row click-through, and detail-page back-nav all work |
| 4 | Consistency and Standards | 4 | Nav colors verified to match DESIGN.md tokens exactly (#2563eb/#6b7280 computed) |
| 5 | Error Prevention | 3 | No messaging distinguishes "sparse data" from "possibly broken" on thin time ranges |
| 6 | Recognition Rather Than Recall | 3 | Time Range selector has no aria-label — reads as just a value, not obviously a filter |
| 7 | Flexibility and Efficiency | 3 | Full keyboard path verified working; no way to isolate one provider's line in the tangle |
| 8 | Aesthetic and Minimalist Design | 3 | Restrained everywhere except the By-Provider chart's visual noise |
| 9 | Error Recovery | 3 | Callout/EmptyState both actionable; not tested against a live network failure |
| 10 | Help and Documentation | n/a | No help system needed for a single-operator instrument panel — correctly out of scope |
| Total | | 29/36 | 80.6% — Good. Up from 27/40 (67.5%) last run — a real, evidence-backed improvement, not just a rescoring artifact |

## Design Specificity Verdict

The prior pass's fixes hold up under adversarial re-testing, not just casual re-inspection. Assessment A forced two edge cases the original fixes weren't explicitly tuned for: selecting "Last hour" (sparse real data) wrapped a model slug to two lines, and all three KPI cards stayed pixel-identical (152/152/152px) — the Grid-stretch fix is robust, not lucky. A synthetic 73-character model name injected into a live cell correctly triggered scrollWidth (535px) > clientWidth (273px) and ellipsized — the truncation safety net works even though no real current data exercises it. Keyboard navigation was re-verified end-to-end via actual Tab/Enter keypresses and document.activeElement checks, landing on the same real route change as the first pass.

Deterministic scan (Assessment B): impeccable detect --json on the Landing page returned clean ([], exit 0) — unchanged from the first run. The live browser-injected detector again found the same 11 anti-patterns as before (1 buried-raster, 10 cramped-padding), both assessed as the same false-positive/systemic-Tremor-default calls made last time — nothing new, nothing regressed.

## Overall Impression

The three fixed issues (keyboard access, column truncation, KPI whitespace) are genuinely fixed, confirmed independently by both assessments with real measurements, not just re-reading the diff. The page's weak point has moved: it's no longer the Top 5 tables, it's the "By Provider" trend view, which neither the original critique nor the fix pass touched.

## What's Working

1. Keyboard accessibility is real and complete, re-verified from scratch. Both assessments independently walked the full Tab order via real keypresses and document.activeElement checks and got the same result: visible focus ring, correct role="link"/aria-label, and a real location.href change on Enter.
2. The KPI-card and table fixes survive real edge cases, not just the exact data snapshot they were built against — two-line metric wrap, a synthetic long name, and live data all independently confirmed stable.
3. Design-system fidelity is measurably real, not just documented — nav link colors match DESIGN.md's hex values down to the computed rgb().

## Priority Issues

[P1] "By Provider" trend chart is unreadable for six of seven providers
- Why it matters: NVIDIA sits at 6-7 succeeded-models while the other six providers cluster at 0-2 and constantly cross each other on the same unstacked, semi-transparent-fill axis — confirmed via a zoomed crop of the 0-2 band. This is the one place on the page that breaks the "Instrument Panel" brief's core promise (legible at a glance); an operator cannot currently tell whether e.g. DeepSeek AI is trending down.
- Fix: Drop the area fill for this tab specifically (keep it on Overall, which is single-series), or split into small multiples, or add legend-click isolation.
- Suggested command: /impeccable clarify (or /impeccable audit first if a broader dataviz-form review is wanted before committing to a fix)

[P2] Transient blank-chart flash when switching to "By Provider"
- Why it matters: Two recharts "width(0) and height(0)" console warnings fire and the chart visibly paints empty for about a second before filling — in a product whose entire premise is fixing a tool that gave misleading signals, a chart that looks broken for a second (even self-correcting) undercuts exactly the trust this product exists to build.
- Fix: Give the AreaChart a fixed pixel minHeight instead of relying purely on ResponsiveContainer's measured parent, or mount both tab panels eagerly.
- Suggested command: /impeccable harden

[P3] Time Range selector has no accessible or visible label
- Why it matters: Confirmed via DOM inspection (ariaLabel: null, ariaLabelledby: null) — a keyboard/screen-reader user tabbing to it hears only the current value ("Last 24 hours, button"), with no indication it's a page-wide filter.
- Fix: Add aria-label="Time range" at minimum.
- Suggested command: /impeccable polish

[P3] Page subtitle and "Models Available" KPI card restate the identical two numbers
- Why it matters: Not a bug (same shared query, by design), but a first-time reader has to notice they're the same fact stated twice rather than two different metrics.
- Fix: Consider whether the subtitle's "models working" clause is still needed once the KPI row restates it one row below.
- Suggested command: /impeccable distill

## Persona Red Flags

The Anxious Operator (checking if something's broken, wants instant reassurance): The blank-chart flash (P2) is exactly the kind of moment this persona misreads as "the tracker itself is down." The By-Provider tangle (P1) actively blocks a fast per-provider read for anyone but NVIDIA.

The Keyboard-Only User: No red flags — full tab order re-verified end-to-end, visible focus ring confirmed, Enter-to-navigate confirmed via URL change.

## Minor Observations

- A single-data-point time range (e.g. "Last hour") renders one floating dot with no connecting line — not broken, but visually thin; worth a deliberate call on whether that deserves different treatment than the current EmptyState/normal binary.
- The browser tab still shows the unedited Vite "frontend" title — a pre-existing, already-documented site-wide item (not Landing-page-specific), but it's literally the first thing a stranger sees before the page loads.
- Muted Ink body text measures 4.83:1 contrast against white — clears WCAG AA's 4.5:1 threshold but not by much; worth knowing if any future palette tweak nudges it.

## Questions to Consider

1. Given NVIDIA dominates the current provider mix, will the By-Provider chart's value-range mismatch get worse or better as the catalog grows — should the chart form be chosen for the data's shape at scale, not just today?
2. Does the subtitle/KPI-card redundancy serve a real "confirm I'm not misreading it" function for the sole operator, or is it the first thing to cut if vertical space is ever needed?
