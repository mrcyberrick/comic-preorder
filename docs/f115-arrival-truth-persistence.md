# F115 — persist the reservation arrival outcome (Option B)

**STATUS:** NOT STARTED | staging=— | prod=— | findings=F115

**Decision record.** Decided 2026-08-18 in `docs/f92-policy-audit-and-f115-arrival-truth.md`
Part B (Rick, direct answers to the three scoping questions):

1. **Option B — persist the outcome.** Not A (an arrival check inside
   `auto_fulfill_past_on_sale()` that trades a visible wrong "arrived" for an
   invisible stuck "still coming"), not C (customer-copy-only, ships nothing
   structural).
2. **The 28 reservations / 23 titles already marked fulfilled on production
   get a one-time correction**, separate from whatever ships going forward.
3. **"Never arrived" is staff-only.** It must not surface to a customer.

This document is the owner and scope-holder for that decision. It is a
**scoping document, not a runbook** — Part B of the deciding session was
explicitly a decision interview, not a build, so no SQL or code lives here.
The next dedicated session turns this into an actual plan with gates,
verification, and completion criteria, following the standard planning →
execution split.

---

## 1. The mechanism this replaces

Full diagnosis lives in `docs/technical-reference.md` § 13 F115 — not
duplicated here. In one paragraph: `auto_fulfill_past_on_sale()` marks a
reservation `fulfilled = true` once its on-sale date passes, with no arrival
check. A title that was never ordered and never arrived is closed on schedule,
indistinguishable from one that arrived, and My List then tells the customer
"✓ Order placed." Nothing today records which case actually happened —
`reportUnverifiedFulfillments()` (shipped 2026-08-04) prints the at-risk
titles to the console at import time and nothing persists it.

## 2. What "persist the outcome" needs to cover

Scope for the next session to turn into an actual plan — **not decided here,
flagged here so it isn't lost:**

- **Schema.** A nullable arrival-outcome field, most likely **tri-state**
  (e.g. `arrived` / `not_arrived` / `unknown`) rather than boolean. This
  matters because F115's own measurement is an explicit **upper bound, not a
  confirmed failure count** — a missing `weekly_shipment` row is not proof of
  non-arrival (F84's label-inversion history, invoices that miss a line,
  books handed over the counter). A boolean forces a false-confidence answer
  where "unknown" is the honest one. Column vs. a small side table is an open
  question for that session.
- **Import script.** `import.js` / `import-staging.js` Step 9's
  `reportUnverifiedFulfillments()` needs to **write**, not just print — this
  is the core of "persist." Whether it writes `unknown` for every unverified
  case, or something more specific, follows from the schema decision above.
- **Admin surface.** `admin.html` already has a **staff-facing** "Never
  arrived" state (F116, `computeBackorderRisk()`) — determine whether this
  reuses that surface/label or needs its own. Staff-only is already the
  existing precedent here, which is consistent with Rick's answer to Q3.
- **Customer surface.** `mylist.html`'s `isOrdered` rendering currently reads
  only `fulfilled`. Per Rick's answer, the raw "never arrived" state must
  **never** reach the customer. What the customer sees instead for an
  `unknown`/`not_arrived` row — still "✓ Order placed" (i.e., customer-facing
  behavior is genuinely unchanged and only the internal record improves), or
  something softer — is an **open product question for that session**, not
  resolved here.
- **One-time production correction (in scope, per Rick's answer to Q2).**
  The 28 reservations / 23 titles F115 already measured need a one-time
  backfill. **Flagged, not decided:** backfilling them as `not_arrived` would
  assert something the evidence doesn't actually prove (same upper-bound
  caveat as above) — `unknown` is the more defensible default unless that
  session does the legwork to actually confirm arrival/non-arrival
  title-by-title. This is exactly the kind of call the next session should
  make deliberately, not inherit silently from this doc.

## 3. Scope

### IN (for the next session to plan and execute)
- Schema change (migration, both environments)
- Import script change (`reportUnverifiedFulfillments()` → a real write)
- Admin panel surfacing (staff-only)
- My List rendering — decide and implement customer-facing behavior
- One-time production backfill for the 28/23, with an explicit, stated value
  choice and rationale
- Playwright coverage for the new state(s)

### OUT (not this document, not the deciding session)
- Any SQL or schema change — this doc contains none
- Any client code change
- Any production write

## 4. Owner and next step

**Owner:** this document. **Next step:** a dedicated planning session that
turns § 2 above into an actual plan with gates and completion criteria, then
a separate execution session, per the project's planning/execution split.
**Date:** not yet scheduled — Rick's call.

## 5. References

- `docs/technical-reference.md` § 13 **F115** (full diagnosis, measurement,
  mitigation history) — this document does not restate it.
- **F108** — the finding F115's residual was previously (wrongly) delegated
  to; that delegation is void. This document is the actual owner now.
- **F116** — shipped the staff-facing "Never arrived" admin state this
  document's schema work will likely feed.
- **F84** — why absent shipment evidence is not proof of non-arrival; the
  reasoning behind the tri-state recommendation in § 2.
- `docs/f92-policy-audit-and-f115-arrival-truth.md` § 3 — the decision
  interview this document's § "Decision record" resolves.
