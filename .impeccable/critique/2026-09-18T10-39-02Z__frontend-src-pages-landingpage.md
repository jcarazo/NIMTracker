---
target: Landing page
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 1
target_identity: "file:/Users/javier/Development/NIMTracker/frontend/src/pages/LandingPage"
timestamp: 2026-09-18T10-39-02Z
slug: frontend-src-pages-landingpage
---
Method: dual-agent (Assessment A and B run as separate isolated subagents)

## Design Health Score (Operate mode — all 10 heuristics applicable)

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Loading state + subtitle counts present; no explicit data-freshness stamp beyond chart timestamps |
| 2 | Match System / Real World | 4 | Real domain vocabulary throughout, no invented jargon |
| 3 | User Control and Freedom | 2 | Top 5 table row click-through is mouse-only — no tabIndex, role, or keydown handler |
| 4 | Consistency and Standards | 4 | Badge padding/radius/font-size measured identical everywhere |
| 5 | Error Prevention | 3 | Read-only page; Callout covers fetch failure |
| 6 | Recognition Rather Than Recall | 2 | Truncated model names force hover-and-recall instead of at-a-glance recognition |
| 7 | Flexibility and Efficiency | 1 | No sort/filter; fixed top-5 only; the one efficiency affordance (row click) is keyboard-unreachable |
| 8 | Aesthetic and Minimalist Design | 4 | Genuinely restrained, matches the Instrument Panel brief |
| 9 | Error Recovery | 2 | Fetch failure surfaces a raw JS error string, not operator-facing copy |
| 10 | Help and Documentation | 2 | Only affordance is a keyboard-inaccessible native title tooltip |
| Total | | 27/40 | Acceptable — solid foundation, real gaps in keyboard access and table layout |

## Design Specificity Verdict

Top5Table.tsx's own code comment shows the team already diagnosed this exact problem once ("Tremor's default column sizing gave the model name column ~318px... capped and truncated"), but the fix (max-w-[140px] truncate on a <td> under table-layout: auto) doesn't actually constrain the rendered column — live DOM measurement shows it renders at 206px and 177px in the two tables, both still wider than the coded cap and both still overflowing their own rendered width. Good intent, undone by a CSS mechanism that doesn't behave the way it looks like it should. Everything else — badge tokens, card shape, color palette — reads as genuinely authored for this product, not template-interchangeable.

Deterministic scan (Assessment B): impeccable detect --json on the 5 target files returned clean ([], exit 0) — static source analysis alone can't see this, since the bug only exists in the rendered DOM under Tremor's runtime table layout. The live browser-injected detector (separate from the CLI) caught 11 anti-patterns invisible to the static scanner: one likely false positive (buried-raster on the time-range selector's intentionally opacity-0 native <select> — standard accessible-custom-dropdown pattern) and 10 real cramped-padding flags on every badge instance (2px 10px, a ~1:5 vertical:horizontal ratio) — confirmed uniform everywhere, so it's a systemic Tremor default, not a page-specific defect.

## Overall Impression

The page opens strong — three KPI cards read as headline facts within a second — then loses composure exactly where the product's core promise lives: identifying which model is fastest. Both assessments independently converge on the same root cause (the Top 5 tables' column-width allocation) from different angles — Assessment A from source/comment archaeology, Assessment B from raw pixel measurement — which is a strong signal this is real, not a nitpick.

## What's Working

1. Badge consistency is real, not assumed — measured via getComputedStyle: 2px 10px padding, 6px radius, 14px text, 23.98px height, identical in every context (KPI inline text vs. table cell). DESIGN.md's spec is honored exactly.
2. KPI card height parity is real, via sound CSS — Grid's default align-items: stretch makes all three cards exactly 135.97px, not a hardcoded coincidence.
3. Provider palette reads as genuinely distinct in the live render — no two adjacent hues collide, confirmed by direct screenshot inspection, not just token math.

## Priority Issues

[P0] Top 5 table rows are click-to-navigate but keyboard-unreachable
- Why it matters: This is the only interactive path from "fastest model" to its detail page, and it's a hard functional exclusion for any keyboard-only operator — confirmed in the live DOM (tabIndex="-1", no role, no onKeyDown), not a style nitpick.
- Fix: Make the row a real interactive control (tabIndex={0}, role="link" or a real link/button wrapper, onKeyDown for Enter/Space, a visible focus ring — none currently exists on any interactive element tested).
- Suggested command: /impeccable harden

[P1] Model-name column doesn't actually cap at its intended width, starving the one identifying label (confirms Q2 and Q3)
- What: max-w-[140px] truncate on the <td> doesn't constrain rendering under table-layout: auto — measured live at 206px (Fastest) / 177px (Throughput), inconsistent between the two side-by-side tables and still overflowing its own rendered width. Meanwhile the Provider column (135–144px) and metric column (146–184px) sit with unused space relative to their actual content (a badge ~46–66px wide; "146.2 tok/s" ~50–70px wide). Real slugs run 16–31 characters; only the single 16-char slug survives untruncated — 9 of 10 visible rows truncate.
- Why it matters: the model name is the single piece of information the operator needs most to identify the row, and it's the starved column while two low-information columns hold unused width.
- Fix: table-layout: fixed with explicit width percentages skewed toward Model (~55/20/25), or move the cap to the inner text node instead of the <td>; widen the cap given real 25–31 char slugs (140px at 14px system-sans shows ~16-18 chars before ellipsis).
- Suggested command: /impeccable layout

[P2] "Models Available" KPI card has ~40px of unused space its siblings fill with real content
- What: Box heights match exactly (Grid stretch), but that's a side effect, not a composition choice — "Models Available" has nothing to say below its Metric where its siblings show a model-slug + badge line.
- Why it matters: one of three same-height cards visibly having "nothing else to say" next to two that do reads as an incomplete card, not a deliberately spare one.
- Fix: either give it a comparable secondary line (delta vs. previous window, "of 37 tracked") or intentionally redesign it as a distinct single-stat card so the emptiness reads as a choice.
- Suggested command: /impeccable polish

[P2] Fetch-failure Callout surfaces a raw JS error string
- What: useLandingPageData.ts:60 passes err.message straight through to the Callout, verbatim.
- Why it matters: violates heuristic #9 — not diagnosable or actionable for the one thing this page needs on failure.
- Fix: map known failure classes to short operator-facing copy with a manual retry action; keep the raw message available for debugging (e.g. a title attribute).
- Suggested command: /impeccable clarify

[P3] No sort/filter on Top 5 tables; fixed top-5 only
- Why it matters: minor efficiency gap for a power-user wanting e.g. "top 5 NVIDIA models specifically" — low severity, likely already covered by the Models page.
- Fix: none needed unless usage shows it's wanted.
- Suggested command: /impeccable optimize (only if ever prioritized)

## Confirm/Refute Verdicts

1. "Models Available" KPI height mismatch — REFUTED as a box-height bug. Both assessments independently measured all three cards at an identical height (Assessment A: 135.97px via getBoundingClientRect(); Assessment B: 136px via the same method) — Tremor's Grid stretches all three to match, so there is no visibly shorter card. What is real: ~32-40px more unused whitespace beneath "Models Available"'s content than its siblings have (P2 above) — a composition issue, not a layout bug.

2. Top 5 tables' model-name truncation given actual column width — CONFIRMED, worse than a cosmetic issue. 9 of 10 visible rows truncate with an ellipsis; only the one 16-character slug survives. Rendered column widths (206px / 177px) are both narrower than the median real slug needs (~26 characters).

3. Table column-width allocation not matching content needs — CONFIRMED. The Provider and metric columns hold real content 46–70px wide inside 135–184px-wide columns, while the Model column — needing the most room — is both under-provisioned and, on top of that, the max-w-[140px] cap meant to control it doesn't actually take effect under table-layout: auto (rendered wider than coded, and still overflowing its own rendered width).

4. Badge sizing consistency — REFUTED; no inconsistency found. Both assessments measured identical padding (2px 10px), radius (6px), font-size (14px), and rendered height (23.98px) across every badge instance, in both the KPI-card inline context and the table-cell context. The only badge-related finding is the detector's cramped-padding flag on the padding ratio itself — real, but uniform everywhere, not an inconsistency between contexts.

## Persona Red Flags

Alex (Power User): Cannot reach a Top 5 row via keyboard at all (tabIndex="-1", confirmed in DOM). Must hover-and-wait on 9 of 10 rows just to read the actual model name — breaks the "at a glance" promise the page exists to deliver. No way to see beyond the fixed top-5 without leaving the page.

Sam (Accessibility): The P0 keyboard trap is a hard WCAG 2.1.1 (Keyboard) failure. The only fallback for truncated names — the native title tooltip — is itself inaccessible (no reliable keyboard trigger, inconsistent screen-reader announcement). No visible focus ring observed anywhere tested.

## Minor Observations

- AvailabilityChart's tab-indicator override renders correctly live — no issue, the earlier fix holds up.
- Chart x-axis timestamps are precise/dense for a glance-read instrument; a coarser relative label ("6h ago") might fit the "at a glance" goal better, though this wasn't asked about directly.
- PageSubtitle's "37 models tracked, 18 models working" is a strong, terse status line — the Metric-Leads/restraint principle working as intended.
- Detector's buried-raster flag on the time-range selector's native <select> is very likely a false positive (standard accessible-custom-dropdown pattern), not a real defect.

## Questions to Consider

1. If the whole reason for a title-tooltip fallback is that names don't fit — why keep the top-5-of-everything scope at all, instead of a wider single-column top-10 that doesn't need to truncate?
2. Given the KPI row's height-equality is a CSS Grid side effect rather than a deliberate choice, should "Models Available" carry a second line so its content — not the grid — earns that height?
3. This page is explicitly public and portfolio-judged — is a mouse-only Top 5 table an acceptable trade, or exactly the kind of gap a technical reviewer notices first?
