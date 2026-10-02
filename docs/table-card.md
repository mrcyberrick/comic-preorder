# Table card — a surface for My List's main table

**STATUS:** IN PROGRESS | staging=BUILT 2026-10-01, awaiting Rick's review | prod=NOT PROMOTED | findings=— (a formatting change Rick asked for, not a defect; **F169 is the next free finding ID**)

**Last verified against live: 2026-10-01** (staging; production untouched).

## 1. The ask and the cause

Rick, 2026-10-01: *"more definition between the background and the main table"*, pointing at the weekly
newsletter's table borders and colours as the model.

My List's main table was injected as a bare `<table class="list-table">` straight onto the `#0f0f0f` page
background, with half-transparent row rules (`rgba(46,46,46,0.5)`), no surface and no border. The
collapsible sections directly above it (Upcoming Arrivals, My Subscriptions) are bordered `#181818`
cards, so the table was the least defined element on the page.

## 2. The recipe (read from the newsletter's live computed styles)

The newsletter (`mrcyberrick.us/weekly-pull-feed/newsletter.html`) already uses this app's tokens, so
nothing new is introduced:

| Newsletter | Token | Now on `.table-card` |
|---|---|---|
| page `#0f0f0f` | `--bg` | unchanged |
| card `#181818` | `--bg-card` | card surface |
| `1px solid #2e2e2e` | `--border` | card edge and **full-strength** row rules (was 50% alpha) |
| `border-radius: 8px` | `--radius-lg` | card corners |
| `box-shadow: 0 4px 24px rgba(0,0,0,.5)` | `--shadow` | card lift |
| `#222222` section band | `--bg-elevated` | header row band |

The header text moves from `--text-muted` to `--text-secondary` because muted is too faint on the `#222` band.

## 3. Scope, and why it is narrow

- **Desktop, screen only** (`@media screen and (min-width: 641px)`). At <=640px the table is `display:none`
  and the page shows `.mobile-card` items, which are already bordered cards; print keeps the plain
  black-on-white table. In both cases the wrapper is left unstyled, so no empty bordered box appears.
- **`overflow-x: auto`, not hidden.** The card still clips to its rounded corners, but a table wider than
  the card scrolls instead of being cut off (measured: a 747px table in a 652px card at a 700px viewport).
- **My List only.** The shared `.list-table` is also used by four admin tables, which are left alone; the
  rules are scoped to the new wrapper. `style.css` carries the reusable `.table-card` class.

**Not done, offered:** Subscriptions' own `.sub-table` ("Your subscriptions") has the same bare look and
could take the same wrapper; This Week's lists were not looked at.

## 4. Files

| File | Change |
|---|---|
| `style.css` | `.table-card` rules (screen + min-width 641px) after the `.list-table` block. |
| `mylist.html` | `<div class="table-card">` around the table in the render template. No data or behaviour change. |

## 5. Verification

`playwright/table-shots.mjs` (local-only): a throwaway customer with 6 reservations (made through the real
catalog UI) and 3 subscriptions; teardown re-read clean. Computed-style checks, all passing: surface
`rgb(24,24,24)`, edge `1px rgb(46,46,46)`, 8px corners, the `0 4px 24px` shadow, header `rgb(34,34,34)`,
`#2e2e2e` row rules with none under the last row, table fits the card at 1350px, scrolls inside it at
700px, **wrapper unstyled at 393px and in print**. Before/after screenshots inspected. Layout shift on the
same data: **0.0577 / 0.0517 before, 0.0561 / 0.0561 after** (unthrottled).
