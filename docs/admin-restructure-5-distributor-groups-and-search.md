# Admin Restructure — Session 5: By Distributor grouping, and search across months

**Parent:** `docs/admin-dashboard-process-map.md` (F121) § 5.7.4.
**Origin:** Rick's suggestions 2026-08-08 after using the session-4 build.

**Status:** Planned 2026-08-08, not started.
**Target:** **staging only.**
**Last verified against live code:** `admin.html` @ `8d4099e`.

---

## 1. What Rick asked for

1. By Distributor should collapse into groups with a summary line, the way By
   Customer does (`16 items · Est. $135.84 · Lunar: 12 · PRH: 4`).
2. A search box on By Distributor.
3. **Search should work across catalog months.**

And the constraint that decides the design: *"First maintain the Printed
Report, if this means prioritize publisher — do it."*

---

## 2. Decisions taken

### 2.1 Group by PUBLISHER — because the print is the priority

FOC cycle was the other candidate (it is already the sort order and matches the
Order Builder's unit). **Publisher wins on Rick's constraint:** the By
Distributor report is printed for the store, and the store scans it by
publisher.

### 2.2 The printed report is grouped by publisher too

Today it is a **flat list of titles with a Distributor column** — no grouping.
Grouping the screen but not the print would leave two views of the same data
organised differently, which is F121 in miniature. **Both get publisher
grouping, with per-publisher subtotals.**

This is a real change to a report Rick relies on, so it ships behind a gate
(V4) that compares row counts and totals before and after: **the same titles
and the same totals, reordered — nothing added, nothing dropped.**

### 2.3 Units are named, not inherited

By Customer's header says *"16 items"*, which does not state whether that is
titles or copies. On By Distributor they differ materially — 42 titles can be
58 copies. So:

    Marvel · 18 titles · 24 copies · Est. $143.20

Copying By Customer's wording would import the exact ambiguity F121 exists to
remove. (By Customer's own label is left alone here — changing it is a separate
call.)

### 2.4 Default view is unchanged

Rick: *"I expect that the current month is shown as it is today in By
Distributor (when expanded)."* With no search active, the tab shows the
selected catalog month exactly as now — the cycle selector keeps working, and
`distributorRows()` is untouched.

### 2.5 Search is cross-month, and says so

Data is already in memory: `allPreordersAllMonths` (~2,000 rows on production,
fetched by the paged read since F113). No new query.

**Three rules, and they are the whole risk of this session:**

1. **Every result row shows its catalog month.** Without it, cross-month
   results are unattributable — the original F121 complaint.
2. **The group header describes what is beneath it.** With a search active it
   reads `showing 3 of 16 · 2 from other months`. Rick accepted either this or
   switching the header entirely to describing the result set; this shape is
   used because it keeps the month total he is used to. **What is not
   acceptable is a header still describing one month while rows from three sit
   under it** — that is F121 reappearing inside its own fix.
3. **On By Distributor, a search visibly overrides the cycle selector.** The
   two contradict each other by construction. An inline note states it:
   *"Searching all months — cycle selector ignored."*

**No toggle.** Search is always cross-month. A toggle is another piece of state
to remember, and session 4 removed one of those for good reason.

---

## 3. Scope

### IN
1. Publisher grouping + collapse on By Distributor, both distributors.
2. Search box on By Distributor, reusing `matchesSearch()`.
3. Cross-month search on **both** By Distributor and By Customer, under § 2.5.
4. Printed reserved report grouped by publisher with subtotals.

### OUT — stop and ask
| Not touched | Why |
|---|---|
| `distributorRows()` / the cycle selector | Unchanged. Search overrides it at read time; the selector itself keeps its meaning. |
| `allPreorders` | **Not widened.** F111 § 4.4 is explicit — 15+ month-scoped consumers. Search reads `allPreordersAllMonths` directly. |
| By Customer's `"16 items"` label | Ambiguous, but changing it is a separate decision. |
| Order Builder, ledger, Mark Ordered | Untouched. |

---

## 4. Gates

| Gate | Check | Pass condition |
|---|---|---|
| **V1** | Publisher groups render, collapsed, both distributors | Header shows `N titles · M copies · Est. $X`; expanding shows that publisher's titles |
| **V2** | Default view unchanged | With no search, the tab shows exactly the selected month's titles — same set as today |
| **V3** | Search filters and auto-expands | Matching publisher groups open; non-matching absent |
| **V4** | **Printed report parity** | Same titles and same totals as before the change, only reordered. Row count and copy total compared against the pre-change build. |
| **V5** | **Cross-month search is attributable** | Every result row shows its catalog month; header reads `showing N of M · K from other months`; the cycle-selector override notice is visible |
| **V6** | Cycle selector still works | With search cleared, switching months behaves as today |
| **V7** | Full suite | Green, with `PLAYWRIGHT_EXIT` and the declared/passed counts both checked |

**V4 and V5 are the ones that matter.** V4 protects a report Rick depends on;
V5 is the only thing standing between cross-month search and reintroducing the
defect this workstream exists to remove.

---

## 5. Completion criteria

- [ ] § 3 IN applied, ranges re-verified against disk first
- [ ] V1–V7 green
- [ ] **Suite helpers checked for selectors this session moves** — session 4's
      lesson: a UI restructure invalidates spec helpers by construction, and
      that grep belongs in the session that moves the UI
- [ ] Fixtures torn down, confirmed by live SELECT
- [ ] Real-browser check by Rick, including a print preview
- [ ] Parent § 5.7.4 index updated

---

## 6. Rollback

Client-only, no DB change. `git revert` the merge. The printed report is the
only externally-visible artifact; V4 exists so a regression there is caught
before Rick prints it rather than after.

---

## 7. Deploy log

*(empty — not started)*
