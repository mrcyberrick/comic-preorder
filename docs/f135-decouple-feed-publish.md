# F135 — decouple the pull-feed publish from shipment import

**STATUS:** PLANNED 2026-09-30 (re-activated after the 2026-09-29 missed send) — NOT STARTED | staging=— | prod=— | findings=F135,F134
**Owner finding:** F135 (`docs/technical-reference.md` § 13). **Target:** two repos — the private
scripts repo (`catalogs/scripts`, `mrcyberrick/comic-preorder-scripts`) and
`mrcyberrick/weekly-pull-feed` (public). **No `comic-preorder` app change.** One optional DB object
(§ 4.4, decision D2).
**Last verified against live:** 2026-09-30 — `weekly-pull-feed` read at `4a20821`; send workflow run
`36648375252` log read; `send-brevo-campaign.js` stale guard read at lines 60–95. The scripts repo
was **not** readable from the planning session — every claim about `import.js` /
`build-pull-feed.js` below carries its 2026-08-21 line numbers and **must be re-read in S0**.

*(History: written 2026-08-21, direction settled with Rick the same day — **decouple**, do not add an
ad-hoc mode. **Deferred 2026-08-29** in favour of the `.env` mitigation (§ 3), because the gated
rollout spanned ~2 weeks for a failure mode the mitigation already blocked. **Re-activated
2026-09-30 by Rick** after the incident in § 0 — which was not the ad-hoc failure the deferral
accepted, but the *other* failure the coupling produces: no publish at all. The design in § 2 and
§ 4.1–4.3 is unchanged from the 2026-08-21 text; § 0, § 4.4–4.6, § 5 and § 6 are rewritten.)*

---

## 0. The 2026-09-29 incident — what failed, measured

| When (UTC) | Event | Source |
|---|---|---|
| 2026-09-18 16:58 | Last feed publish: `4a20821` "88 titles", stamp `pull-feed-generated: 2026-09-18` | `weekly-pull-feed` git log |
| 2026-09-22 23:28 | Send run #29 **success** on that feed (age ~4.3 days) — correct, it was the 09-23 week | Actions |
| 2026-09-25 → 09-29 | **No publish commit at all** — the week-of-09-30 feed was never built | git log (next commit after `4a20821`: none) |
| 2026-09-30 00:03 | Send run #30 **failure**: `Content generated: 2026-09-18 (age 12.0 days, limit 6)` → `ERROR … This week's prep likely did not run` → exit 1 | run `36648375252`, job log |

**What this proves.** The Brevo side and the stale guard both worked: the guard failed closed and
nobody was mailed a repeat of the 09-23 issue. **The failure is upstream — the publish never
happened**, and the only thing that publishes is `import.js`'s shipment step.

**What it does NOT yet prove — S0 must establish which one, because the fix differs:**

- **(a) The shipment import ran but the publish was skipped.** Candidates: `GITHUB_TOKEN_PULL_FEED`
  still commented out in `.env` from an earlier ad-hoc run (the § 3 mitigation's documented
  forgetting risk, in the direction nobody weighted — forgetting to **restore** it), the publish
  erroring after the upsert, or the week's shipment going in through a path that doesn't publish.
  → **Decoupling fixes this class entirely.**
- **(b) The weekly shipment import never ran** (busy week: the October catalog import ran
  09-27, the F158 record names a "09-27 Lunar invoice"). → Decoupling does **not** fix this by
  itself: a DB-driven build finds no rows and must fail loudly. What fixes it is the **early
  warning** in § 4.5, which moves detection from Tuesday night to Monday morning.

**Either way the coupling is the defect.** A newsletter's existence is currently a side effect of an
operator running a data import on a laptop with the right `.env` line uncommented. That has now
failed in both directions: wrong week mailed (2026-08-11) and nothing mailed (2026-09-29).

---

## 1. The defect (unchanged from 2026-08-21)

The publish is welded inside the shipment-import block and fires unconditionally:

```js
// Automatic whenever a shipment ran — no prompt (decision 2026-07-09).
const feedDate = resolveFeedWeek(allShip);
await publishPullFeed({ refDate: feedDate });
```

`resolveFeedWeek()` infers the week from **the rows just imported**. An ad-hoc file's dominant
`on_sale_date` is a past week, so an ad-hoc import republishes a past issue, the orphan purge deletes
the current week's thumbnails, and the next cron mails the stale issue — measured on production
2026-08-11 (`resolveFeedWeek()`'s own comment: *"the feed republished 19 already-shipped titles,
purged the 50 correct thumbnails as orphans, and the Tue 08-11 Brevo send mailed that stale issue"*).

## 2. Why decouple rather than add a flag (unchanged)

1. `import.js` becomes data-only and uniform — no ad-hoc branch to forget.
2. The week is resolved from the **database** (all shipments), not from one file's contents —
   `build-pull-feed.js`'s existing `resolveLatestShipmentWeek()` fallback becomes primary.
3. `resolveFeedWeek()` is deleted rather than patched a third time.
4. `publishPullFeed()` is already exported and `node build-pull-feed.js --publish` is already the
   documented recovery route — most of the machinery exists.

## 3. Interim mitigation (still in force until S4)

Comment out `GITHUB_TOKEN_PULL_FEED` in the scripts `.env` for an **ad-hoc** shipment import, then
**restore it** before the next weekly import. **New as of 2026-09-30:** forgetting the *restore*
silently produces the § 0 failure. Until S4 lands, check the line is uncommented before every weekly
import.

---

## 4. Design

### 4.1 Move the trigger — do not remove it (unchanged)

Making publish a manual step trades a **loud** failure for a **quiet** one (F96: three green-Actions
weeks, every campaign suspended). The trigger **moves** to a cron; no human is added to the loop.

### 4.2 Target shape

```
mrcyberrick/weekly-pull-feed
  preflight-feed.yml   Mon ~13:00 UTC   read-only: does the DB hold shipment rows for this
                                        Wednesday's week?  No → fail (GitHub emails Rick)   § 4.5
  send-newsletter.yml  Tue 21:00 UTC
     job build:  resolve target week (tomorrow's Wed, from the DB)
                 → build → week/row-count assertions → single commit → push
     wait:       thumbnails for this build return 200 from Pages                           § 4.6
     job send:   send-brevo-campaign.js on the freshly built newsletter-email.html
  workflow_dispatch inputs: mode = build-only | build-and-send ; week = YYYY-MM-DD (optional)
                            ; dry_run (existing)
```

- `import.js` publishes nothing, ever. `resolveFeedWeek()` and its export are deleted.
- **Recovery no longer needs the laptop:** `workflow_dispatch` with `mode=build-only` or
  `build-and-send` (and a `week` override for a deliberate re-publish). `node build-pull-feed.js
  --publish` remains available locally.
- Build and send are adjacent, so the stale guard's 6-day budget stops being a timing hazard (the
  09-16 cron-drift note becomes moot).

### 4.3 Two constraints carried forward (unchanged)

- **F100 — exactly one Pages deployer.** The in-workflow commit must be deployed by the existing
  built-in legacy Pages builder; do **not** add `actions/deploy-pages` or a second workflow.
- **Credentials live in the repo that runs the job**, not copied from the laptop `.env`.

### 4.4 Where `build-pull-feed.js` lives, and how it reads data — decisions for Rick

**D1 — single source of truth for the builder. DECIDED 2026-09-30 (Rick): move it.** Move
`build-pull-feed.js` from the scripts repo into `weekly-pull-feed/scripts/`, and delete it from the
scripts repo at S4. Two copies of a generator is the drift shape this project keeps paying for.
`weekly-pull-feed` is **public**, so S0 must confirm the file is credential-free (it should be —
the scripts repo has been `.env`-driven since 2026-07-08) and contains nothing Rick minds being
public (S6a's `?series=` link logic is fine; it ships in every email anyway).

**D2 — how the Actions job reads production data (recommended: a narrow read-only RPC).**

| Option | Secret in GitHub | Blast radius if leaked | Work |
|---|---|---|---|
| **A. Anon-callable `SECURITY DEFINER` RPC** (e.g. `get_pull_feed_week(p_tenant_id, p_week_start)`) returning only the columns the builder uses | none (anon key is public by design) | the same data the public newsletter already publishes | one `docs/sql/` migration, staging then prod; same pattern as `resolve_tenant_by_slug` / `get_popular_series()` |
| B. Service-role key as an Actions secret | prod `service_role` | **full RLS bypass on production** | none |
| C. Dedicated read-only Postgres role/key | a scoped key | table-scoped | Supabase role + key management; heaviest |

Recommend **A**. It keeps the service-role key on the laptop only (CLAUDE.md § Credential Safety),
and the projection is exactly what is already public. The RPC's column list is set in S0 from what
the builder actually reads. **If S0 finds the builder needs anything not already public
(e.g. per-customer reservation counts), stop and re-decide D2 with Rick.**

**D3 — `GITHUB_TOKEN_PULL_FEED`.** Replaced by the workflow's own `GITHUB_TOKEN` with
`permissions: contents: write` on the build job. Removed from the scripts `.env` at S4.

### 4.5 Early warning — the fix for § 0 case (b)

`preflight-feed.yml`, Monday ~13:00 UTC, read-only, same RPC: count shipment rows for the week
containing this Wednesday. Zero → exit 1 with *"No shipment rows for week of YYYY-MM-DD — run the
weekly shipment import before Tuesday 21:00 UTC."* GitHub's failure email is the alert. This turns a
Tuesday-night miss into a Monday-morning to-do with a day and a half of lead time.

### 4.6 Assertions that can fail (per CLAUDE.md "a verification step that cannot fail…")

Once build and send are adjacent, the stale-age guard is **near-vacuous** — a fresh build always
passes it. It stays (it still protects a manual `send-only` path) but it is no longer the safety
net. The build step asserts instead:

1. **Target week = the week containing the next Wednesday** relative to the run's UTC date — not
   "latest shipment week". If the latest week in the DB is *last* week, fail: that is § 0 (b), and
   publishing it would be the 08-11 incident again from the other side.
2. **Row count > 0** for that week.
3. **The committed `newsletter-email.html` stamp equals today**, checked immediately before send.
4. **Thumbnails reachable**: a sample of the new thumbnail URLs return 200 from Pages before the
   send step runs (poll with a bounded timeout, ~10 min; fail if exceeded). Covers the Pages-deploy
   gap and the `GITHUB_TOKEN`-push-triggers-Pages question in § 7 R1.

Each must be **negative-control tested** in S2: force the failing input, observe red.

---

## 5. Runbook

Session boundaries are marked. **Order matters: the new trigger is proven before the old one is
removed** — S4 before S3 recreates the silent-no-publish window.

**S0 — Discovery + this week's recovery (one session, read-mostly). Gate V0.**
1. Re-read `import.js` publish block, `resolveFeedWeek()`, `publishPullFeed()` and all of
   `build-pull-feed.js` from disk; record current line numbers here.
2. **Classify § 0**: service-role read of production `weekly_shipment` for the week of 2026-09-30
   (and `created_at` of those rows); check the scripts `.env` for `GITHUB_TOKEN_PULL_FEED`
   commented/uncommented; ask Rick which imports he ran 09-25 → 09-29 and whether any printed
   `skipping feed publish`. Record case (a) or (b) with evidence.
3. List every query `build-pull-feed.js` makes (table, columns, filters) → this is the D2 projection.
4. Confirm the builder is credential-free and safe to make public (D1 is decided; this is its
   precondition — if the file carries anything that must not be public, stop and re-raise D1).
5. **Recovery — DECIDED 2026-09-30 (Rick): SKIP this week.** No late build or send for the week of
   2026-09-30; the next normal weekly import publishes the 10-07 feed as usual. *(Options that were
   considered, kept for reference:)* either skip this week, or run
   `node build-pull-feed.js --publish` locally, confirm the new commit + stamp, then
   `workflow_dispatch` the send with `dry_run=false`. Do **not** raise `STALE_MAX_DAYS` to push the
   old feed.
6. If a finding is warranted (e.g. case (a) shows a new mechanism), file it with `/file-finding`;
   otherwise record the incident under F135 only.

**S1 — Data path (if D2 = A). Gate V1.** Write `docs/sql/YYYY-MM-DD-f135-pull-feed-week-rpc.sql`
(`BEGIN; … COMMIT;`, `STATUS:` line, explicit `GRANT EXECUTE … TO anon`, minimal projection,
tenant-scoped by parameter, verification that **fails** if the function is missing or `anon` lacks
EXECUTE). `/sql-check` first. Rick runs it on staging, then production (the builder reads production
data; there is no staging newsletter). Verify with an anon `curl` returning rows for a known week.

**S2 — Build in the send workflow, NOT yet in force. Gate V2.** In `weekly-pull-feed`:
add `scripts/build-pull-feed.js` (moved per D1, switched to the RPC), add the `build` job with the
§ 4.6 assertions, `mode`/`week` dispatch inputs, and `preflight-feed.yml`. **The scheduled path
still sends only** — gate the new build job to `workflow_dispatch` until S3. Negative controls:
week with no rows → red; stale DB week → red; thumbnail 404 → red. Confirm exactly one Pages
deployer afterwards (list workflows; only `send-newsletter`, `preflight-feed` and the built-in
`pages build and deployment`).

**S3 — Equivalence, then switch on. Gate V3.** After the next normal weekly import (still
publishing via `import.js`), run `workflow_dispatch mode=build-only` **to a scratch branch or with
the commit step disabled**, and diff its `newsletter-email.html` / `newsletter.html` / `rss.xml`
against the import-published ones for the same week, ignoring timestamps. Identical (or every
difference explained) → enable the build job on the schedule. Observe that Tuesday's run builds,
commits, and sends. **Read the Brevo campaign status, not the Actions colour** (F96/F106).

**S4 — Remove the import-time publish. Gate V4.** Scripts repo: delete the publish block,
`resolveFeedWeek()` + export, `build-pull-feed.js` (now living in `weekly-pull-feed`), and their unit
tests; update any test that imports them. `npm test` green; `--no-write` dry run clean; commit and
**push** (verify `git log origin/main`). Remove `GITHUB_TOKEN_PULL_FEED` from `.env` and
`.env.example`. Update `docs/weekly-pipeline-hardening.md` and `docs/monthly-catalog-refresh.md` /
any ad-hoc-shipment instructions so none still say "comment out the token".

**S5 — One unattended cycle with the import path gone. Gate V5.** Monday preflight green, Tuesday
build+send green, campaign delivered. Only then does F135 close. *(Use `/schedule-gate` at S3 and S5
for the elapsed-time waits.)*

---

## 6. Verification gates

| Gate | Assertion | Evidence |
|---|---|---|
| **V0** | § 0 classified (a) or (b) with a DB read and the `.env` state; builder's query list recorded; builder confirmed public-safe (D1); D2 answered by Rick | this doc updated |
| **V1** | Anon call to the RPC returns the week's rows with only the projected columns; anon call to `weekly_shipment` directly still denied/filtered | curl output, both environments |
| **V2** | Each § 4.6 assertion observed **red** under its forced input, then green; one Pages deployer | Actions run links |
| **V3** | Workflow build == import build for the same week (timestamps aside); scheduled Tuesday run delivered | diff output + Brevo campaign status |
| **V4** | `import.js` has no publish call, no `resolveFeedWeek`, no `GITHUB_TOKEN_PULL_FEED`; `npm test` green; pushed | `git log origin/main`, test count |
| **V5** | One unattended Mon+Tue cycle: preflight green, build correct week, thumbnails 200, campaign delivered | Brevo status, not Actions colour |

---

## 7. Risks to check, not assume

- **R1 — Does a `GITHUB_TOKEN` push trigger the legacy Pages build?** GitHub suppresses most
  workflow triggers from `GITHUB_TOKEN` pushes; Pages' dynamic builder has behaved differently over
  time. **Measure in S2** (push a test commit from the workflow, watch for a `pages build and
  deployment` run). If it does not trigger: request a Pages build via the REST API
  (`POST /repos/{o}/{r}/pages/builds`) from the same job — still one deployer. Do not add
  `deploy-pages.yml` (F100).
- **R2 — Cron drift.** Tuesday runs have landed up to +2h. Build + thumbnail wait adds minutes;
  keep 21:00 UTC. Revisit at the November DST change (the workflow's own note).
- **R3 — Public-repo exposure** of the builder source (D1) — checked in S0.
- **R4 — Two edits to one generator.** S6a (`newsletter-acquisition-funnel.md`) edited
  `build-pull-feed.js` in the scripts repo. After D1 the canonical copy moves; update that doc's
  pointers in S4 so the next change lands in the right repo.
- **R5 — Node 20 deprecation warning** on `actions/checkout@v4` / `setup-node@v4` (seen in run #30).
  Bump `node-version` to 22+ in S2 while the workflow is open anyway; not the cause of anything.

---

## 8. Rollback

Until S4, both paths coexist: disable the scheduled build (revert the S3 enable commit) and the
import-time publish is still in force. After S4, `git revert` the scripts-repo commit restores the
import-time publish and `GITHUB_TOKEN_PULL_FEED` (re-add to `.env`). The RPC is additive and can be
left in place or dropped.

---

## 9. Completion criteria

- [ ] V0–V5 green, each with recorded output in this doc
- [ ] `import.js` publishes nothing; `resolveFeedWeek()` deleted; scripts repo committed **and
      pushed** (`git log origin/main`)
- [ ] `weekly-pull-feed`: build-then-send on schedule, Monday preflight, dispatch recovery modes,
      one Pages deployer, repo-native credentials
- [ ] `GITHUB_TOKEN_PULL_FEED` removed from `.env` / `.env.example`; no doc still instructs
      commenting it out
- [ ] RPC `STATUS:` line reads APPLIED on both environments (if D2 = A)
- [ ] § 13 F135 → RESOLVED; CLAUDE.md F135 row removed; this STATUS token flipped
- [ ] `/wrap-up`

---

## References

`docs/technical-reference.md` § 13 — **F135**, **F134**, **F98**/**F100**, **F96**/**F106**, **F84**.
`docs/weekly-pipeline-hardening.md` · `docs/weekly-pipeline-consolidation-plan.md` ·
`docs/newsletter-acquisition-funnel.md` (S6a, the other editor of `build-pull-feed.js`).
