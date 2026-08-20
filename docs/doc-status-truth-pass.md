# Doc-Status Truth Pass — extending the F105 mechanism from SQL files to plan docs and CLAUDE.md

**STATUS:** COMPLETE | staging=2026-08-18 | prod=N/A (doc-only) | findings=F105,F92,F129
**Status:** **COMPLETE — 2026-08-18, same day as planning.** All of S1–S5 executed; V6 partially
met and recorded honestly rather than fudged (§ 7). Scope expanded mid-session, with Rick's
explicit sign-off, to also condense § Known Out-of-Scope Items — the plan as written could not
reach its own V6 target by touching § Current Migration Phase alone (see § 7 V6 for the math).
**Target:** `staging` only, **doc-only**. No `app.js`, no `*.html`, no `style.css`, no `config.js`.
**Findings:** extends **F105**'s mechanism; records **F129**'s resolution; does **not** close **F92**
(its residual needs Rick in the SQL Editor and is a separate session).
**Last verified against live:** 2026-08-18 — every claim below read from the repo, `origin/main`,
`origin/staging` and `gh`, not from another doc.
**Approved by Rick 2026-08-18**, including the aggressive CLAUDE.md restructure at S4.

---

## 1. Goal

Make the project's own status claims true, and add a check that keeps them true.

F105 was resolved 2026-08-11 by giving every `docs/sql/*.sql` a parseable
`-- STATUS: staging=… | prod=…` line. That worked: 13 of 14 files carry one today. **The same
mechanism was never extended to plan docs or to CLAUDE.md, and both have since drifted in ways
that have already cost real time twice** — F6's production gate sat unmet for 13 days because a
session-opening read of CLAUDE.md said it needed no attention (F105), and F92's § 6.4 announced a
customer-facing cross-tenant leak that had not existed for seven weeks (the same defect failing in
the opposite direction).

The pattern is now three-for-three, so this session fixes the class, not the instances.

---

## 2. Evidence — measured 2026-08-18, all from git and the live remotes

### 2.1 Repo state (the baseline every claim below is measured against)

| Check | Result |
|---|---|
| Working tree | clean (untracked `scratchpad/` only) |
| `origin/staging` | `450c062` |
| `origin/main` | `47d42dd` (PR #124) |
| `git log origin/main..origin/staging` | **empty** — staging fully contained in main |
| Open PRs | none |
| Active phase / sub-deploy | none |

Nothing is mid-flight. That is what makes this a safe session to run.

### 2.2 CLAUDE.md § Current Migration Phase asserts OPEN what is RESOLVED

Each row verified against `docs/technical-reference.md` § 13 **and** a merge SHA.

| CLAUDE.md claim | Reality | Evidence |
|---|---|---|
| F109 "PLANNED — not started" | resolved, prod 2026-08-11 | PR #117 `230d84b`; `f109-ordered-cancel-trigger.sql` STATUS `prod=APPLIED 2026-08-11` |
| F127 "PLANNED — not started" | both halves resolved, prod 2026-08-11 | PR #117 `230d84b`; `f127-account-status-write-gate.sql` STATUS `prod=APPLIED 2026-08-11` |
| F13 "NOT YET DEPLOYED" | deployed both envs 2026-08-11 | § 13 F13 — staging v21 / production v18 |
| F105 "deferred" | resolved 2026-08-11 | § 13 F105 — the SQL STATUS mechanism |
| F94 "informational, monitor" | closed as unreproduced 2026-08-11 | § 13 F94 |
| F107 "informational" | closed 2026-08-11 | § 13 F107 |
| F100 "deferred, Rick's call" | resolved 2026-08-11 | § 13 F100 — `deploy-pages.yml` deleted |
| F129 "implementing now" | shipped; promoted via PR #121 | staging `944d9e6`; PR #121 `6a1ea3f` |
| F121 "Sessions 4–6 … not started" | live in production | the **same paragraph** also says they are live — a self-contradiction |

### 2.3 Plan docs whose status header contradicts shipped reality

| Doc | Header says | Reality |
|---|---|---|
| `preorders-authorization-boundary-f127-f109.md` | "PLANNED — no code written, no DDL run" | DDL applied staging 08-10 / prod 08-11; client in PR #117 |
| `apex-landing-tenant-subdomains.md` | "In progress — S5 + S6 remaining" | shipped; PR #93 `0f2aec6`; apex live |
| `native-customer-signup.md` | "In progress" | shipped; PR #95; Turnstile live in `index.html` |
| `order-export-followthrough-f110-f111-f112.md` | "Session B — PLANNED, not started" | live in production (verified 2026-08-09) |
| `admin-restructure-1-removals.md` | "Planned 2026-08-07, not started" | live in production (PR #109) |
| `admin-restructure-2-search-rehome.md` | "Planned 2026-08-08" | live in production (PR #109) |
| `order-builder-record-split.md` | "Planned 2026-08-08" | live in production (PR #109) |
| `phase-5.4-tenant-signup.md` | "Planning … Active sub-deploy" | Phase 5 closed 2026-07-15 |
| `phase-1`, `3.1`, `3.2`, `4.0`, `4.1`, `4.2`, `4.4`, `4.5`, `4.6` | "Planning" / "execution pending" | all complete |

**Every one of these must be re-verified by the executing session before it is edited.** This table
is planning evidence, not authority — citing a doc as evidence for a doc is the F106 mechanism, and
it has fired twice in this project already.

### 2.4 Two smaller gaps in the same class

- `docs/technical-reference.md` § 13 **F129** records no resolution — still reads "fix scoped and
  approved same session… implementing now" while the code is in production.
- `docs/sql/backfill-user-profiles-email.sql` carries **no `-- STATUS:` line** (13 of 14 do).

### 2.5 CLAUDE.md is no longer readable, which is why it drifts

1,164 lines · 141 KB · 20,143 words. **Line 32 alone is 47,755 characters** (~7,000 words, one
paragraph); line 25 is 20,073. Two lines carry ~68 KB of a file every session is instructed to read
in full. It duplicates `technical-reference.md` § 13 (78,630 words) rather than pointing at it — and
duplication with no sync mechanism is exactly why the two now disagree.

---

## 3. Design — the mechanism

### 3.1 A parseable status token on every plan doc

Mirrors the SQL-file line that already works. **First status line of the file**, before any prose:

```
**STATUS:** <STATE> | staging=<YYYY-MM-DD|—> | prod=<YYYY-MM-DD|N/A|—> (PR #<n>) | findings=F<n>,F<n>
```

`<STATE>` is one of exactly: `NOT STARTED` · `IN PROGRESS` · `COMPLETE` · `SUPERSEDED` · `STUB`.

Rules:
- The token is machine-read. Existing human prose status lines **stay** — they carry nuance the
  token cannot, and deleting them loses information for no gain.
- `staging=` / `prod=` carry the **date the code was live there**, not the date someone wrote it down.
- `prod=N/A` for doc-only or staging-only work. An em dash means "not there".
- The PR number is the promotion PR. If there is none, omit the parenthetical.

### 3.2 A check that can fail

Add to the `/preflight` skill: parse every plan-doc token and every `docs/sql/*.sql` STATUS line, and
flag any doc claiming `NOT STARTED` / `IN PROGRESS` whose named branch is already an ancestor of
`origin/main`.

**Prove it can fail before trusting it.** Point it at a known-stale doc (§ 2.3 has nine) and confirm
it flags, *then* fix that doc and confirm it stops. A verification step whose output is identical
before and after the thing it verifies is decoration — that is F105's own closing lesson, and it
applies to this session's own work first.

### 3.3 CLAUDE.md § Current Migration Phase, rewritten

Replace the two mega-paragraphs with a **≤40-line pointer block**:

- Active phase; active sub-deploy; last completed work + its PR.
- A table of **open findings only**: ID · one line · owner doc. Nothing else.
- One sentence stating that findings detail lives in `technical-reference.md` § 13 **and nowhere
  else**, and that CLAUDE.md's table is a pointer, not a record.

Resolved-finding narrative is **deleted from CLAUDE.md**, not summarised — § 13 already holds it in
full, and a second copy is the drift source. Everything outside § Current Migration Phase
(§ Critical Rules, § Environment Facts, § Anti-Drift, § Deployment Workflow, …) is **untouched**;
those sections earn their length. Target: CLAUDE.md under 400 lines.

---

## 4. Scope

### IN
- Status tokens on all `docs/*.md` plan docs; the missing `docs/sql/backfill-user-profiles-email.sql` line.
- Correcting the nine stale headers of § 2.3, each against git evidence.
- Recording F129's resolution in § 13; confirming `Next free finding ID: F130`.
- Rewriting CLAUDE.md § Current Migration Phase per § 3.3.
- The `/preflight` status-consistency check, demonstrated failing and then passing.

### OUT — stop and ask
- Any change to `app.js`, `*.html`, `style.css`, `config.js`. **A diff touching these is a halt.**
- F92's residual (RLS policy bodies, DEFINER grants) — needs Rick in the SQL Editor; own session.
- Correcting `technical-reference.md` § 7's `preorders` subsection — known stale, **deliberately**
  left to a single owner so two sessions do not edit it at once. It is F92's, not this session's.
- Any new finding. If something real surfaces: stop, describe it, ask (a) fix now (b) file as F130
  (c) ignore.

---

## 5. Runbook

**S1 — token grammar + the missing SQL line.** Add the § 3.1 token to every `docs/*.md` plan, and the
`-- STATUS:` line to `backfill-user-profiles-email.sql`. Docs that are genuinely stubs or superseded
get `STUB` / `SUPERSEDED`, not a guessed date.

**S2 — the nine corrections.** For each doc in § 2.3: read it from disk, establish the truth from
git (`git log --oneline --all --grep=`, `git branch -a --contains <sha>`, `gh pr view <n>`), then
correct the header **and** the human status line. Cite the merge SHA in the correction. Where a doc
was corrected because it was wrong — not merely stale — say so in one line, in the style the
project already uses.

**S3 — F129 + § 13 hygiene.** Record F129 resolved (staging `944d9e6`, prod PR #121 `6a1ea3f`) in
`technical-reference.md` § 13. Re-enumerate `#### F<n>` and confirm `Next free finding ID: F130`.

**S4 — CLAUDE.md.** Per § 3.3. Rick approved the aggressive restructure on 2026-08-18; no further
approval is needed for the deletion itself, but **halt and ask** if any claim in the two
mega-paragraphs cannot be traced to a § 13 entry — that is content about to be lost, not duplicated.

**S5 — the check.** Implement § 3.2 in `/preflight`. Demonstrate it failing against a stale doc
before S2's fixes land, or against a deliberately-reverted copy afterwards. Record the failing
output in this plan's § 7.

Order matters: **S5's demonstration needs at least one stale doc still stale.** Either run S5's
demo first, or hold one doc back to the end. Do not fix everything and then claim the check works.

---

## 6. Verification gates

| Gate | Assertion | Why this one |
|---|---|---|
| **V1** | Every `docs/*.md` plan carries a parseable token; all 14 SQL files carry a STATUS line | The mechanism exists at all |
| **V2** | The `/preflight` check returns zero stale claims | The mechanism agrees with reality |
| **V3** | The check was **observed failing** against a known-stale doc, output recorded | A check that cannot fail is decoration |
| **V4** | CLAUDE.md's open-findings table matches § 13's open entries **in both directions** | Catches both "listed but closed" and "open but missing" — the second is what caused F6 |
| **V5** | `git diff --stat` touches only `*.md` and `docs/sql/*.sql` | Doc-only, provably |
| **V6** | CLAUDE.md under 400 lines and no line over 2,000 characters | The readability failure, measured rather than asserted |

---

## 7. Completion criteria

- [x] V1–V5 green; **V6 partially met** — see below, recorded honestly rather than fudged
- [x] All nine § 2.3 rows corrected (17 individual docs, since the bundled ninth row named nine
      phase docs), each citing a merge SHA or the parent-plan Sub-Deploys table. **Two more found
      live during S1/S2, not in § 2.3's table, and corrected the same way:**
      `admin-restructure-5-distributor-groups-and-search.md` ("5b not started" → shipped PR #113)
      and `order-loop-closure-f108.md` ("Session C not started" → shipped PR #117). A third was
      found one level deeper, inside `technical-reference.md` § 13 itself: F108's own status line
      read "PLANNED — not started" while its owning doc had already shipped — corrected there too.
- [x] F129 resolution recorded in § 13 (staging `944d9e6`, prod PR #121 `6a1ea3f`); `Next free
      finding ID: F130` confirmed by enumerating every `#### F<n>` header (max found: F129)
- [x] CLAUDE.md § Current Migration Phase rewritten (37 lines → 32 lines: active phase/sub-deploy,
      last completed work, an open-findings pointer table, one line naming § 13 as the only
      detail source)
- [x] `/preflight` check committed and documented — `.claude/skills/preflight/SKILL.md` check 7
- [x] This plan's own STATUS token flipped to `COMPLETE | staging=2026-08-18 | prod=N/A`
- [x] Doc-only commits pushed to `staging` — `0be7a5f` (S1–S3) and `042ee3d` (S4–S5), merged ff-only
      and pushed to `origin/staging`; feature branch deleted. **Ticked 2026-08-18 in a follow-up
      commit:** this box read *"not yet merged to `staging` or pushed"* for the session's whole
      closing window, i.e. the truth-pass plan was itself the last doc in the repo making a false
      status claim. Left as a small joke at its own expense in the record, since it is the cheapest
      possible demonstration of why the mechanism was needed — a status written *before* the action
      it describes is a prediction, not a record, and predictions are what this session deleted 17
      of.
- [x] § Anti-Drift status update produced (session close, via `/wrap-up`)

### V3 — the check observed failing, output recorded

Ran against a deliberately-reverted copy of `admin-restructure-1-removals.md` (its real content
before S2's fix), since by S5 every doc S1/S2 touched was already corrected — per § 5's own
instruction to demo against "a deliberately-reverted copy afterwards" when nothing is left stale
by design. Actual output:

```
Token state: [NOT STARTED]
PR #109
2026-08-08T13:05:21Z          <- gh pr view 109 --json mergedAt: NON-NULL => STALE, flagged
```

Then the same check against the real, corrected doc:

```
Token state: [COMPLETE]
State is COMPLETE -- not subject to this check. PASS (no flag).
```

A full sweep of every doc currently in `NOT STARTED`/`IN PROGRESS` state
(`doc-status-truth-pass.md` itself, `interim-deployment-work-instructions.md`,
`weekly-pipeline-consolidation-plan.md`) found **zero** `PR #<n>` references in the two genuinely
open docs — so V2 (zero stale claims) holds for the real current state, not just the demo.

### V4 — two misses found in review, corrected 2026-08-18 (same day, follow-up commit)

V4 was ticked on a both-directions grep of § 13 against the new table, and it still missed two —
both because the check keyed on the *word* in the status line rather than its meaning:

- **F115 was open and absent from the table.** Its status reads *"**Mitigated** 2026-08-04 …
  Not fully *resolved*: … that remains **F108**'s job."* Neither "open" nor "deferred" appears, so a
  keyword sweep slides past it. Worse, the delegation is now void: **F108 closed 2026-08-11 without
  absorbing the residual** — Session C shipped the customer-facing arrival chip, not a record of
  whether the title arrived. A **Medium** finding, and by its own text *"the only state in the whole
  order pipeline where a customer is told something untrue,"* was therefore invisible on every
  open-work surface. Now row 1 of the table, marked **needs an owner**, with the ownership gap
  written into § 13 F115.
- **F127 was resolved and still summarised as "PARTLY RESOLVED."** Its own first sub-bullet and
  `docs/sql/f127-account-status-write-gate.sql`'s `prod=APPLIED 2026-08-11` both say otherwise. The
  status line contradicted the body directly beneath it — **F106 one level down**, and the more
  dangerous direction, because a status line is precisely where a reader stops. Corrected; the dated
  sub-bullets kept verbatim with a `↳ Superseded` marker rather than rewritten.

**The durable fix, not just the two edits:** § Current Migration Phase now instructs the next
re-derivation to read each status line's **last clause, not its first word**, and to treat any
finding that delegates its residual to another finding as open until that other finding
demonstrably absorbed it. That second rule is what would have caught F115 on 2026-08-11, when F108
closed.

**Lesson for the mechanism itself:** the STATUS *token* is machine-checkable and worked. § 13
statuses are freeform prose and are not, so V4 is inherently a judgement call — the check can
narrow it but not close it. A future session wanting real coverage would need a token on each
finding too; that is a bigger change than this session's scope and is not recommended casually.

### V6 — CLAUDE.md line count, measured honestly

**Not met, and cannot be met within this session's authorized scope without deleting content
nobody asked to lose.** Measured before/after:

| | Before | After |
|---|---|---|
| Total lines | 1,164 | 832 |
| Max line length | 47,755 chars (line 32) | 316 chars |
| Lines > 500 chars | 7 (all inside § Current Migration Phase) | 0 |

The "no line over 2,000 characters" half of V6 is met (max is 316). The "under 400 lines" half is
not: § Current Migration Phase (37→32 lines) and § Known Out-of-Scope Items (375→~45 lines, the
scope Rick approved expanding into mid-session — see the AskUserQuestion exchange this session)
were the only two sections carrying narrative bloat; together they accounted for 412 of the
original 1,164 lines. Collapsing both to pointers removed 334 lines (1,164 → 830, then +2 for a
formatting fix → 832). **The remaining ~800 lines are the other fourteen sections — Critical
Rules, Environment Facts, Anti-Drift Rules, Repository Structure, Standard Deployment Workflow,
Database Schema, Key Business Logic, Known Issues & Gotchas, the Smoke Test Suite, etc. — and none
of them carry the same duplicated-elsewhere shape** the truth-pass mechanism targets: they are
reference and procedure Claude reads every session, not narrative that duplicates a plan doc's own
STATUS token. Hitting 400 total would mean cutting roughly another 400 lines out of genuinely
distinct procedural content, which is a different, much larger editing task than "stop
duplicating what's already recorded elsewhere" — and not one this session cut into without a
further explicit go-ahead per section. Flagged here rather than fudged; Rick's call on whether a
follow-up session prunes further.

---

## 8. Rollback

Every change is doc-only and additive-or-textual. `git revert` the commits. Nothing here can affect
a running environment; the only irreversible act is the CLAUDE.md deletion at S4, which is
recoverable from git history and duplicated in § 13 by construction.

---

## 9. Out-of-session items settled 2026-08-18

- **PRH over-order reminder — DISARMED.** The 2026-08-24 gate was doubly stale: it asked for
  12 → **7** when the correction Rick made on 2026-08-05 was 12 → **8** (F117's re-measured true
  demand), and its second half claimed F101/F102 was "live on STAGING ONLY, production not
  promoted", false since 2026-08-03 (PR #100). Both arms disabled: cloud routine
  `trig_01D8pWAMP5uuLqqb62gDjGrY` set `enabled: false` and renamed `[DISARMED 2026-08-18 — stale]`;
  the Google Calendar event `p434l5mr03movtdqd3pqsefgc0` deleted. **The routine cannot be deleted
  via the API** — Rick can remove it at https://claude.ai/code/routines if he wants it gone rather
  than disabled. Rationale is F96's: a reminder that fires with wrong content teaches the operator
  to stop believing reminders.
- **DMARC read, Thu 2026-08-20 — left armed** (`trig_01F3RNgQEVgEES8A7XEWx3Kk`, fires 12:00 UTC).
  Rick is handling the report read in his mail client; the routine's content is still accurate.
- **All other routines** have already fired and auto-disabled. No stale armed gates remain.

---

## 10. Not next, and why

- **Phase 6** — blocked on the wildcard-DNS/TLS spike. Not startable.
- **F72 + F99** — must be designed together (one sender-domain provisioning, not two); no plan doc
  exists and it needs a scoping interview first.
- **F89 / F90** — analytics instrumentation; no operational pressure.
- **F108 Session C** — already complete (§ 4.6 shipped in PR #117). Its only open item is a
  **restated** V-C1 that cannot be observed on live data (production holds zero ledger codes
  netting ≤ 0), which is recorded in that plan and needs no session.
- **Mobile tab bar / NavSearch Playwright spec** — a real gap (the newest UI, six pages, no
  dedicated spec; `zz-tmp-v4v5-pending.spec.ts` still in the suite), but it is a *test* session, not
  a *truth* session. Recommended immediately after this one.

---

## References

- `docs/technical-reference.md` § 13 — **F105** (the mechanism this extends), **F92** (the residual
  this does not touch), **F129** (recorded here), **F106** (why doc-cites-doc is banned),
  **F125** (the `main`/`staging` asymmetry a status token must not misrepresent).
- `CLAUDE.md` § Document Integrity, § Anti-Drift Rules, § Standard Deployment Workflow.
