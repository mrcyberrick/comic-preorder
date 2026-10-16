# F135 — decouple the pull-feed publish from shipment import

**STATUS:** IN PROGRESS 2026-10-13 — S0, S1 (RPC applied on both environments), S2 (build-then-send workflow LIVE on `weekly-pull-feed` `main`) and S3 (the first unattended cron, Tue 2026-10-06, observed GREEN and SENT, § 11.5) are DONE; S4's CODE is DONE (2026-10-13, scripts repo `fc044f9`, § 11.6) and S5 (one Tuesday without an import-time publish: the Tue 2026-10-20 cron) is OPEN; tracked as W1 of `docs/weekly-newsletter-architecture.md` | staging=APPLIED 2026-10-01 | prod=APPLIED 2026-10-01 | findings=F135,F134
**Owner finding:** F135 (`docs/technical-reference.md` § 13). **Target:** two repos — the private
scripts repo (`catalogs/scripts`, `mrcyberrick/comic-preorder-scripts`) and
`mrcyberrick/weekly-pull-feed` (public). **No `comic-preorder` app change.** One optional DB object
(§ 4.4, decision D2).
**Last verified against live:** 2026-10-01 (S0) — scripts repo read from disk at `8f964a5` (`main`,
in sync with `origin/main`): `import.js`, `import-staging.js`, `build-pull-feed.js` and the tests
that import them; production `weekly_shipment` read with the service role (GET only); `weekly-pull-feed`
`main` re-read through the GitHub API (tip still `4a20821`); the PAT's health probed read-only.
**Line numbers in § 10.1 are measured at that commit; the 2026-08-21 numbers this doc used before
(`import.js` ~1931 and ~1510) were off by +388 and +267 lines.** Earlier read, 2026-09-30:
send workflow run `36648375252` log; `send-brevo-campaign.js` stale guard at lines 60–95.

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

### 0.1 S0 result — classified (a), measured 2026-10-01

**The weekly shipment import ran. The publish did not. Case (a); case (b) is ruled out.**

| Evidence | Reading | Source |
|---|---|---|
| Production `weekly_shipment`, week Mon 09-28 → Sun 10-04 | **71 rows** (PRH 43, Lunar 28), `on_sale_date` 2026-09-30, every row has a title and a cover | service-role read, 2026-10-01 |
| Those rows' `created_at` | **2026-09-27 23:43:22Z** (Sun 7:43 PM ET), one batch (all within 0.12 s). The October catalog import cleared `order_deadline` at 23:32Z, 11 min earlier — consistent with one run | same read; CLAUDE.md October gate record |
| `weekly-pull-feed` commits after 09-18 | **None.** Tip `4a20821`, 2026-09-18 16:58:45Z; `main` is the only branch | GitHub API, 2026-10-01 |
| Normal import → publish gap | 2 min 21 s (09-11: rows 22:59:14Z → commit 23:01:35Z) to 6 min 6 s (09-18: 16:52:39Z → 16:58:45Z) — so a 09-27 publish would have landed by ~23:50Z | same sources |
| The builder on the 09-30 data | `node build-pull-feed.js --local` renders **71 titles**, exit 0 — the data and render half cannot have thrown | local run (writes only the gitignored `pull-feed-out/`; nothing uploaded) |
| `GITHUB_TOKEN_PULL_FEED` today | present and **uncommented** (`.env` line 13); a 93-character fine-grained PAT; GitHub accepts it: repo `GET` 200, `permissions.push = true`, `git/ref/heads/main` (the publish's own first call) 200 | `.env` read with values redacted; read-only API calls |
| `.env` last modified | **2026-09-27 23:46:17Z (7:46 PM ET) — 176 s after the shipment rows landed** | file mtime |
| The 09-21 ad-hoc import | 2 PRH rows, on-sale 09-22, created 2026-09-22 00:20–00:24Z (Mon 8:20 PM ET). **No publish commit followed it either**; any successful publish commits, because `rss.xml` stamps the build time (`build-pull-feed.js:53-57`) | same read |

**What this leaves.** Two production imports since 09-18 and neither published. With the token valid
today, the one cause that fits both is **the token line being absent from `.env` during those runs**:
commented out for the 09-21 ad-hoc import (the § 3 mitigation) and not restored before 09-27 — the
forgotten-*restore* direction § 3 named on 09-30. The `.env` edit 176 s after the 09-27 shipment fits
"put back right after the run". **That is an inference, not a confirmed cause.** Rick was asked on
2026-10-01 and does not remember, and the console line that would settle it (`⚠️  GITHUB_TOKEN_PULL_FEED
missing from .env — skipping feed publish.`, `import.js:2328`) was not kept. A publish that failed
inside the `try/catch` (`import.js:2347-2350`) is not strictly excluded, but the narrow remainder is
unlikely: the token works today, the build renders, and the first publish call succeeds against the
live ref. **Either way the incident reduces to one console line, and that is the finding:** `import.js`
treats "nothing was published" as a warning, and nothing downstream looks for it.

**Decoupling closes this class; § 4.5 does not.** The 71 rows were in the database from Sunday night,
so Monday's preflight (§ 4.5) would have passed. Only moving the build into the cron (§ 4.2) closes
(a). § 4.5 exists for (b), which has **never been observed** (§ 10.4 item 7).

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

**S0 additions, measured 2026-10-01.**

1. **State today:** the line is **uncommented** (`.env` line 13) and the PAT is valid (§ 0.1). The
   import for the 10-07 week is safe to run as-is. Check with
   `grep -n GITHUB_TOKEN_PULL_FEED .env` — a leading `#` means the publish will be skipped.
2. **⏰ The PAT expires 2026-10-07 15:43:24 UTC (11:43 AM ET)** (GitHub's own
   `github-authentication-token-expiration` header). It is a fine-grained token; 90 days before that
   is 2026-07-09, the date of the decision to publish from `import.js`, so it was probably created
   then *(inferred, not read from GitHub)*. After expiry, `publishPullFeed()`'s first
   GitHub call fails with 401, `import.js:2347-2350` prints a warning and the import carries on:
   **the same silent no-publish as § 0, with a different trigger.** The weekly import for the 10-07
   week (expected around 10-02) falls inside the window; the import for the 10-14 week (expected
   around 10-09) does not. **Renew the token before 10-07.** Decoupling cannot land first: S3 alone
   needs one observed Tuesday. *(Recorded under F135 rather than filed separately: it is a second
   trigger of the mechanism F135 already owns, and D3 retires the token.)*
3. **There is no shipment-only entry point.** The shipment import is Step 6 of the full
   `node import.js <lunar> <prh> [<ship1> <ship2>]` run (`import.js:1969`, `:2250`), reached only after
   a catalog import. The toggle therefore applies to a whole catalog-plus-shipment run.
4. `.env.example` has **never** listed this variable (§ 10.4 item 2), so a rebuilt `.env` gets no hint
   that it is needed.

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

**D1 precondition — CHECKED 2026-10-01: met.** Lines 1–740 (everything except the email/RSS templates)
were read in full; the whole 1,875-line file was then pattern-scanned for key shapes, UUIDs, emails,
phones, project refs and local paths — **the ~1,100 template lines were scanned by pattern, not read.**
Result: **no literal secret and no UUID.** The four credentials arrive
only through `.env` (`SUPABASE_URL_PROD`, `IMPORT_SERVICE_KEY_PROD`, `IMPORT_TENANT_ID_PROD`,
`GITHUB_TOKEN_PULL_FEED`, `:66-69`). What is hardcoded is already public: the production project ref
(`:72`, a wrong-environment guard — it is also in the public `config.js`), the shop's phone and
address (`:1238-1239`, `:1301-1302`, `:1351-1353` — printed in every email), `rjbookstop.pulllist.app`, and the
GitHub owner and repo. **Two soft items for Rick's eye, neither a blocker:** comments at `:84-88` and
`:130-135` quote internal measurements (a Brevo campaign's byte size, a list "roughly 70% Gmail",
catalog-month row counts). **Moving it is not a plain copy:** `loadDotEnv()` exits 1 when no `.env`
sits next to the script (`:222-232`) and the four `requireEnv()` calls run at module load, so the
file cannot even be `require`d in Actions as written. Both change in S2, in the same edit that
switches the data path (§ 10.4 item 4).

**D2 — DECIDED 2026-10-01 (Rick): A, the anon-callable `SECURITY DEFINER` RPC.**
S0 step 3 found the builder's whole data footprint: **one table, `weekly_shipment`**, read by two
queries (§ 10.2) — `title`, `cover_url` and the joined `catalog.series_name` for one Mon–Sun week,
plus the latest `on_sale_date`. **No per-customer or reservation data**, and every column already
ships in the public newsletter, so the stop condition in the paragraph below did not fire. S1 settles
the signature; two points carried in from S0: (1) it must return **every** row for the week,
including ones with no title or cover, because the builder derives its "skipped / collapsed"
warning and the customer-facing title count from the raw row count (`:346-352`); (2) the embedded
`catalog:catalog_id(series_name)` is a **left** join (null when no catalog row), so the RPC must be
one too. Taking the tenant **slug** (`rjbookstop`) instead of the UUID would keep the tenant UUID out
of a public repo — an S1 design choice, `/sql-check` first.

*Original framing, kept for the record:* **D2 — how the Actions job reads production data
(recommended: a narrow read-only RPC).**

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

**S0 — Discovery + this week's recovery (one session, read-mostly). Gate V0.** ***DONE 2026-10-01 —
V0 green. Step 1 → § 10.1, step 2 → § 0.1, step 3 → § 10.2 and § 4.4, step 4 → § 4.4, step 5 →
**publish only, no send, run later the same day on Rick's explicit call (§ 10.6)**, step 6 → no
finding filed (§ 10.5).*** *(This line first read "nothing run (week skipped; its on-sale date has
also now passed)", true until Rick overrode the 09-30 skip decision that afternoon.)*
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
| **V0** | § 0 classified (a) or (b) with a DB read and the `.env` state; builder's query list recorded; builder confirmed public-safe (D1); D2 answered by Rick | this doc updated — **GREEN 2026-10-01:** (a) per § 0.1 (cause inferred, not confirmed); queries § 10.2; D1 met § 4.4; **D2 = A** |
| **V1** | Anon call to the RPC returns the week's rows with only the projected columns; anon call to `weekly_shipment` directly still denied/filtered | curl output, both environments |
| **V2** | Each § 4.6 assertion observed **red** under its forced input, then green; one Pages deployer | Actions run links |
| **V3** | Workflow build == import build for the same week (timestamps aside); scheduled Tuesday run delivered | diff output + Brevo campaign status |
| **V4** | `import.js` has no publish call, no `resolveFeedWeek`, no `GITHUB_TOKEN_PULL_FEED`; `npm test` green; pushed | `git log origin/main`, test count |
| **V5** | One unattended Mon+Tue cycle: preflight green, build correct week, thumbnails 200, campaign delivered | Brevo status, not Actions colour |

---

## 7. Risks to check, not assume

- **R1 — Does a `GITHUB_TOKEN` push trigger the legacy Pages build?** ***ANSWERED 2026-10-01: YES (§ 11.4, run `36882659720`).*** GitHub suppresses most
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
- [ ] `GITHUB_TOKEN_PULL_FEED` removed from `.env`; `README.md:13` no longer names it (it was never
      in `.env.example`, § 10.4 item 2); no doc still instructs commenting it out
- [ ] RPC `STATUS:` line reads APPLIED on both environments (if D2 = A)
- [ ] § 13 F135 → RESOLVED; CLAUDE.md F135 row removed; this STATUS token flipped
- [ ] `/wrap-up`

---

## 10. S0 record — code map, query inventory and corrections (2026-10-01)

Everything below was read from disk or from the live systems on 2026-10-01. Where § 5 and this
section disagree, **this section is current.**

### 10.1 Where the code is — scripts repo `main` @ `8f964a5` (in sync with `origin/main`)

| File | What | Lines |
|---|---|---|
| `import.js` | `NO_WRITE` flag | `:72` |
| | positional args: `[lunarCatalogPath, prhCatalogPath, argShipPath1, argShipPath2]` | `:1969` |
| | `resolveFeedWeek()` (comment `:1755-1776`) | `:1777-1789` |
| | Step 6 shipment import | `:2250-2352` |
| | `upsertShipment(...)` — the shipment write, runs **before** the publish | `:2315` |
| | **publish block**: `NO_WRITE` skip `:2325-2326`; missing-token warning `:2327-2328`; `resolveFeedWeek(allShip)` `:2331`; spread print `:2335-2344`; `require('./build-pull-feed.js')` + `publishPullFeed({ refDate: feedDate })` `:2345-2346`; `catch` → warning only `:2347-2350` | `:2319-2351` |
| | `module.exports` (includes `resolveFeedWeek`) | `:2450-2466` (`:2455`) |
| `import-staging.js` | `resolveFeedWeek()` — **no call site** (comment `:1752-1768`) | `:1769-1781` |
| | `module.exports` includes it | `:2413` |
| `build-pull-feed.js` | header, usage, data contract | `:1-58` |
| | credentials: `loadDotEnv()` call `:65`, four `requireEnv()` `:66-69`, prod-URL guard `:72-75` | `:64-75` |
| | `loadDotEnv()` / `requireEnv()` | `:222-241` |
| | `resolveLatestShipmentWeek()` | `:286-301` |
| | `fetchWeekRows()` (raw/skipped/collapsed accounting `:346-352`; returns `shipmentCount` `:356`) | `:303-357` |
| | `gh()` GitHub Git Data API wrapper | `:392-405` |
| | `readPublishState()` · `resolveThumb()` · `planPurge()` · `verifyPublishedTree()` | `:411` · `:461` · `:530` · `:564` |
| | **`publishPullFeed()`** — the single-commit publish | `:600-678` |
| | `buildLocal()` · `module.exports` · CLI | `:680` · `:695-703` · `:706-720` |
| | email/RSS templates (`buildNewsletterHtml` first) | `:729-1875` |
| | `pull-feed-generated` stamp: `new Date().toISOString().slice(0, 10)` | `:1371`, `:1439` |

### 10.2 Every query the builder makes — the D2 projection

| # | Where | Request | Columns used |
|---|---|---|---|
| Q1 | `resolveLatestShipmentWeek()` `:286-301`, called from `fetchWeekRows()` `:304` only when no `--week` is given | `GET weekly_shipment?select=on_sale_date&tenant_id=eq.{T}&on_sale_date=not.is.null&order=on_sale_date.desc&limit=1` | `on_sale_date` |
| Q2 | `fetchWeekRows()` `:311-322` | `GET weekly_shipment?select=title,cover_url,catalog:catalog_id(series_name)&tenant_id=eq.{T}&on_sale_date=gte.{Mon}&on_sale_date=lte.{Sun}&limit=1000&offset=N`, paged until a short page | `title`, `cover_url`, `catalog.series_name` (left join through `catalog_id`) |

**Not in D2** (not database reads): the GitHub API calls on `mrcyberrick/weekly-pull-feed`
(`gh()`: `git/ref`, `git/commits`, `git/trees`, `git/blobs`, `PATCH git/refs`) and `wsrv.nl`, the
image resizer (`:475`). **No other table, no database write, no RPC.** Downstream the raw row count
matters as much as the columns: it becomes `shipmentCount`, the customer-facing "titles arriving"
number (`:356`). Weekly sizes, measured: 67 / 73 / 68 / 77 / 88 (+2 ad-hoc) / 71 rows for the weeks
08-26 → 09-30 — nowhere near PostgREST's 1,000-row cap, but give the RPC an explicit `ORDER BY`
anyway (F162's lesson).

### 10.3 Test coverage S4 will touch

- `test/feed-week.test.mjs` — imports `resolveFeedWeek` from `../import.js` (`:37`); goes with the
  function.
- `test/builders.test.mjs:35-41` — asserts `import.js` and `import-staging.js` export **the same key
  set**. Deleting `resolveFeedWeek` from one file only turns this red.
- `test/thumb-retention.test.mjs` — `require`s `../build-pull-feed.js` (`:33`) after injecting dummy
  env, which only works because the module reads its env at load. It moves with the builder, and
  `weekly-pull-feed` has **no `package.json` and no test runner today** (root: `.github/`, `images/`,
  `index.html`, the three artifacts, `scripts/send-brevo-campaign.js`, `thumb-retention.json`,
  `thumbs/`), so S2 must decide where those tests live or they are dropped by accident.

### 10.4 Corrections to the 2026-09-30 runbook

1. **S4 must also remove `resolveFeedWeek()` from `import-staging.js`** (`:1769`, export `:2413`). It
   has no call site, but the parity test above requires both files to export the same set. S4's text
   named only `import.js`.
2. **`.env.example` has never listed `GITHUB_TOKEN_PULL_FEED`** — it holds only the six
   Supabase/tenant variables. S4's "remove it from `.env.example`" is a no-op; the doc that names the
   variable is `README.md:13`. The same fact means nothing reminds an operator rebuilding `.env` that
   the publish needs it (F131's single-operator shape).
3. **S2 starting state, confirmed:** one workflow (`send-newsletter.yml`, `cron: "0 21 * * 2"`,
   `permissions: contents: read`), Pages `build_type: legacy` on `main` / `/`, `deploy-pages.yml`
   absent — so there is exactly one deployer now, and the build job's `contents: write` is the only
   permission change. Secrets the workflow references today: `BREVO_API_KEY`, `SENDER_EMAIL`.
4. **The builder is not a drop-in copy for Actions** (§ 4.4 D1): `loadDotEnv()` exits 1 with no `.env`,
   and four `requireEnv()` calls run at module load. Both must change in S2, along with the data path.
5. **The stamp is a UTC date** (`:1371`) while the same file's retention code uses local date parts
   (`todayLocalDate()` `:505`). Harmless at a 21:00 UTC run; choose one clock for the stamp **and** for
   § 4.6(3)'s "stamp equals today" assertion, or that assertion can disagree with the thing it checks.
6. **§ 4.6(1) is Wednesday-anchored** ("the week containing the next Wednesday"). The builder's own
   comment (`:284-285`) and CLAUDE.md § Key Business Logic both prohibit Wednesday-anchored logic.
   Measured `on_sale_date`s are Wednesdays except one ad-hoc Tuesday (09-22), so it would work today.
   The intent — fail when the database's newest week is not this run's week — can be stated from the
   Mon–Sun week of the run date. Re-derive it in S2.
7. **§ 4.5's Monday preflight addresses case (b), which has never been observed.** The observed failure
   (a) passes it, because the rows were present from Sunday night (§ 0.1). **Rick's call** whether it
   stays in scope for this finding or is deferred. It is cheap once S1's RPC exists, but it is a
   second workflow and a second alert to maintain for a failure with no instance on record.

### 10.5 Decisions and disposition

- **Rick, 2026-10-01:** D2 = **A** (anon `SECURITY DEFINER` RPC). Asked what happened to the token
  line on 09-21 / 09-27: **does not remember** — the cause stays an inference (§ 0.1).
- **Earlier, standing:** D1 = move the builder (2026-09-30); skip the week-of-09-30 newsletter
  (2026-09-30). ***Superseded in part the same day (§ 10.6): Rick chose "publish only, no send" after
  S0's classification.** This bullet first read "no late build or send was run, and nothing was
  published or sent in S0" — true until that publish.* **No Brevo send was run, and none is
  planned for this week.**
- **No finding filed.** The case-(a) cause matches the failure § 3 already named, and the token
  expiry (§ 3, item 2) is a second trigger of the mechanism F135 owns, not a new mechanism. Rick can
  ask for it to be filed. **Next free finding ID: F169** — F168 was filed 2026-09-30 on `staging`
  (the phone drawer). This branch is cut from `main` and its `CLAUDE.md` still reads F168, so file
  from `staging`'s copy, not this one.
- **Writes outside this repo: exactly one, the § 10.6 publish.** Everything else in S0 was production
  reads (GET), one local `build-pull-feed.js --local` run (gitignored `pull-feed-out/`; no upload)
  and read-only GitHub API calls. No code, SQL or workflow was changed in either repo.
  *(First read "Nothing written outside this repo" — true until the publish.)*

### 10.6 Recovery — publish only, 2026-10-01 (Rick's explicit call)

Rick was offered three options (keep the skip / publish only / publish and send) and chose
**publish only, no send.** Run from the scripts folder: `node build-pull-feed.js --publish`, no
`--week`, so the week resolved from the database to on-sale 2026-09-30 (Mon 09-28 → Sun 10-04).

| Check | Result |
|---|---|
| The script's own report | 71 titles; +71 thumbnails staged (0 cached, 0 `wsrv.nl` failures, 0 over the 100 KB limit); 143 expired purged, 88 retained; its own tree check "163 referenced file(s) present, 143 orphan(s) gone"; exit 0 |
| The commit on `weekly-pull-feed` `main` | **`d7263702`**, 2026-10-01 14:24:56Z, one parent; `newsletter-email.html`, `newsletter.html`, `rss.xml` and `thumb-retention.json` modified plus thumbnails; 218 files in all |
| The committed stamp | `<!-- pull-feed-generated: 2026-10-01 -->` (read from the commit, not the local build) |
| Pages | `pages-build` for `d7263702` reached `built`; **exactly one deployment** for that sha; the one workflow run since is `pages build and deployment`, `success` — F100's one-deployer property held |
| Images actually served | all **37** distinct cover URLs in the committed email return **HTTP 200**, and a 5-thumbnail sample of the 88 retained from the prior issue also returned 200 (the email shows one cover per series, so 37 of the 71 staged thumbnails are referenced) |
| No send | no `Send Weekly Newsletter` run exists after the 09-30 failure; the Brevo workflow was not dispatched |

***SUPERSEDED the same day by the cutover (§ 11): the Tuesday run now builds its own feed from the database and `check-stamp.js` refuses to send an email not stamped TODAY, so a stale issue can no longer pass. The paragraph below is kept as the record of the risk while it stood.***

**⚠️ The risk this publish created, accepted by Rick when he chose it.** The send guard passes a feed
less than 6 days old, measured from the stamp date. This feed is stamped **2026-10-01**, so at the
Tuesday **2026-10-06 21:00 UTC** cron its age is ~5.9 days and **it passes**. If the import for the
10-07 week has not published a newer feed by then, **that Tuesday's send mails the week-of-09-30
issue — books that went on sale a week earlier — which is the 2026-08-11 incident from the other
side.** Before 10-06 21:00Z: confirm `weekly-pull-feed` `main` has a publish commit **after**
`d7263702` for the 10-07 week (recent weeks run 67-88 titles; stamp on or after the import date), and
that the import was run with the token line uncommented and the PAT still valid (§ 3 item 2). If the
10-07 import slips past that Tuesday, **disable the scheduled workflow** (Actions → Disable
workflow) until it has published; a `dry_run` dispatch does not stop the cron.

**Gate scheduled (2026-10-01):** the two checks above — the pre-send publish confirmation (due before
Tue 2026-10-06 21:00Z) and the PAT renewal (due before Wed 2026-10-07 15:43:24Z) — share **one
reminder, Mon 2026-10-05 8:00 AM ET** (33 h before the send, ~52 h before expiry). Two channels:
one-time routine `trig_015GUseYiM3LGbNvruo9t2TD` (`run_once_at` 2026-10-05T12:00:00Z, reminds only,
no credential values) and a Google Calendar event on Rick's primary calendar (popup + email,
8:00–8:15 AM ET). Delete the routine at https://claude.ai/code/routines if the plan changes. Combined
deliberately: both deadlines fall after the same morning, and a second reminder for a single check
would be noise.

---

## 11. Cutover by 2026-10-06 — execution record (started 2026-10-01)

**Rick, 2026-10-01: "It should be fully decoupled from the import script"; chose to cut over by
Tue 2026-10-06** (asked which of: cut over by Oct 6 / keep the plan's pace / also give shipment loading
its own entry point — he selected the first only). That pulls S1 and S2 forward and folds S3's
equivalence evidence into them; S4 and S5 stay **after** the Oct 6 cycle, because the new trigger must
be observed before the old one is removed (§ 5's order rule is unchanged).

### 11.1 Deviations from § 4–§ 5, each deliberate

1. **The week rule is the Mon–Sun week containing the run date** — not "the week containing the next
   Wednesday" (§ 4.6(1)). That resolves § 10.4 item 6 (no Wednesday anchoring). No rows for that week
   fails loudly; rows that have **all** already gone on sale fail too unless a week is named.
2. **The Monday preflight (§ 4.5) is NOT in the cutover.** Rick has not ruled on § 10.4 item 7. The
   Tuesday build gives the same signal (no rows → red run → GitHub's email), about 15 hours later.
3. **Two gates added that the plan did not have**, because with build and send adjacent the send
   script's 6-day stale guard is near-vacuous: `scripts/check-stamp.js` (the email must be stamped
   today, checked in the send job against a fresh checkout of the branch tip) and
   `scripts/wait-for-thumbs.js` (every image the email references must be **served**, HTTP 200, before
   the send job may run — the F98 / F100 gap).
4. **The send job checks out the branch tip, not the triggering commit.** A default checkout would read
   the pre-build `newsletter-email.html`; the build job's commit is not in it.

### 11.2 Status

| Step | State |
|---|---|
| **S1** RPC `get_pull_feed_week` — `docs/sql/2026-10-01-f135-pull-feed-week-rpc.sql` | **APPLIED on BOTH environments 2026-10-01 (Rick), V1 green on both.** Verdicts: `OK - F135 week RPC present, SECURITY DEFINER, anon-callable, projection exact, parity holds` — staging `raysandjudys` week 2026-09-28 71 = 71; **production `rjbookstop` week 2026-09-28 71 = 71**. **V1 as a real anonymous caller, production:** HTTP 200, 71 rows, exactly the four keys (67 with a series name); unknown slug → `[]`; the other tenant (`comicstore`) same week → `[]`; empty week → `[]`; identical output across two calls; direct anon read of `weekly_shipment` → `200 []` (closed by RLS). Staging, same checks: 200 / 71 / four keys / `[]` / `[]` / deterministic / **401** `42501`. The `200 []` vs `401` difference is the production-vs-staging anon-grant divergence F150 already records for `app_settings`, now also seen on `weekly_shipment`; both are closed. The `sb_publishable_` key works as `apikey` alone |
| **S2** build in the workflow | **LIVE on `weekly-pull-feed` `main` since about 15:12Z on 2026-10-01 (its Pages build ran 15:13Z) — feature commit `ca8a7ed9`**, pushed as a fast-forward of **only that commit** (the rehearsal branch had two extra publish commits touching 79 files, mostly junk thumbnails; the branch was deleted afterwards). Verified end to end — see § 11.4 |
| Repo variables | `SUPABASE_URL` and `SUPABASE_ANON_KEY` set on `weekly-pull-feed` 2026-10-01 14:50Z from the public `config.js` the live site serves (non-secret by design). The anon key's shape and length (`sb_publishable_`, 46) were read back; the value never was |
| Scripts repo | **Untouched.** Its copy of `build-pull-feed.js` and import-time publish stay until S4, so **two copies of the builder exist for now: edit only the `weekly-pull-feed` one** |

**Evidence, local (before anything was pushed):**
- **35 unit tests pass with an empty environment** (12 ported retention tests + 23 new). **Every guard
  was mutation-tested**: broken in a throwaway copy, and the matching test went red each time —
  empty-week check removed (2 red), 1000-row cap removed (1), already-on-sale removed (1) and inverted
  (1), stamp check made to always pass (2), earliest-wins restored (5), thumbnail wait made to never
  fail (2) — and the unmutated control stayed 35/35.
- **V3 (early, data stubbed): rendered output equals what production published.** A local stub served
  the rows the OLD service-role query returns for the week of 09-30 to the NEW builder; against the
  artifacts at `weekly-pull-feed` `d7263702`, `newsletter-email.html` and `newsletter.html` are
  **byte-identical** and `rss.xml` is identical apart from its build-time `pubDate`/`lastBuildDate`.
  It also proves the CRLF→LF conversion and one scrubbed comment changed nothing rendered.
  **Repeated against the REAL production RPC after S1: the same result** — `newsletter-email.html`
  (55,258 chars) and `newsletter.html` (62,684) byte-identical, `rss.xml` identical apart from
  build-time stamps.
- **A comment was scrubbed before the file could go public:** the S0 soft item naming the subscriber
  list's Gmail share (`build-pull-feed.js:99`) now reads "Gmail is a large share of recipients". The
  other internal-measurement comments (a Brevo campaign's byte size, catalog row counts) were left —
  Rick has not ruled on them and they identify no one.

**Remaining:** the Oct 6 cron is the unattended observation (gate V3's "observe a Tuesday"); S4 and S5
follow it (§ 5). Everything before that is done and recorded in § 11.4.

### 11.3 Fallback, and what to watch on Oct 6

If the Oct 6 build step fails, the send job is skipped and the run goes red (GitHub emails Rick). Then:
fix forward, or dispatch `mode=send-only` — which sends the feed already on `main`. That fallback is
valid **only while `import.js` still publishes at import time** (until S4), which is exactly why S4
waits for a green Oct 6 cycle. **The Oct 5 reminder was revised when the cutover landed** (routine
`trig_015GUseYiM3LGbNvruo9t2TD` and the calendar event, both 2026-10-01): it no longer says "confirm the
import published or disable the workflow" — that hazard is closed (§ 10.6) — and now says to confirm the
week's shipment rows are loaded (the one input the workflow cannot create), watch the first run and check
the Brevo campaign status, and renew the PAT only if S4 has not landed.

### 11.4 Rehearsal and live verification, 2026-10-01

The branch was pushed to `weekly-pull-feed` as `f135-s2-build-in-workflow` first (a push there starts
nothing: the workflow triggers only on schedule and dispatch, and legacy Pages builds only `main`), then
dispatched one run at a time (the workflow's concurrency group would cancel a queued run). Guard
messages quoted from the run logs.

| Run | Input | Result | What it proves |
|---|---|---|---|
| `36881315177` | `build-only`, `week=2030-01-07` | **RED** at "Build and publish": `No shipment rows for the week 2030-01-07 -> 2030-01-13. The weekly shipment import has not run for this week ... Refusing to publish a different week instead.` Send job skipped | Case (b) fails loudly. Also the first proof that the YAML parses, Node 22 sets up, the 35 tests pass on the runner, and the env reaches the real RPC |
| `36881394480` | `build-only`, no week (run date 10-01) | **RED**: `Every row for 2026-09-28 -> 2026-10-04 is already on sale (latest 2026-09-30, today 2026-10-01). Refusing to preview a past week` | A run can never preview an already-shipped week. This is the live situation today |
| `36881472703` | `build-only`, `week=2026-09-16`, `thumb_wait_minutes=1` | Build step **success**, then **RED** at the wait: `42 of 43 image(s) are NOT being served after 1 min` | The F98 failure (images in the commit, not on the site) is caught before the send job can run. Pre-checked: 0 of 77 of that week's thumbnails were served |
| `36882230466` | `build-and-send`, `week=2026-09-30`, `dry_run=true` | **GREEN**, both jobs. 71 titles → one commit `7774ad5e` on the rehearsal branch; `round 1: 38/38 served`; `newsletter-email.html is stamped 2026-10-01 - built by this run`; the send step created **Brevo draft campaign 34** ("weekly-pull-feed 2026-10-01", list of 12) and sent nothing | The whole chain, including the send job's checkout of the branch tip and the stamp check. **Draft 34 is a rehearsal artifact for Rick to delete** |
| `36882659720` | `build-only`, `week=2026-09-30`, on **`main`** | **GREEN**: commit **`da7ba7c6`** on `main` (one commit, content-identical to the live issue; only `rss.xml`'s build-time stamps changed), `Pages build of da7ba7c6 was started by the push itself (R1: yes)`, 38/38 images served, send skipped | The real commit + Pages + wait path, which a scratch branch cannot exercise |

- **R1 is answered: YES.** A `GITHUB_TOKEN` push starts the legacy Pages build by itself. The
  request-a-build step stays as a harmless safety net (it did not fire).
- **F100's one-deployer property holds on `main`:** the Pages build of `da7ba7c6` reached `built`,
  exactly **one** deployment exists for that sha, one `pages build and deployment` run, and the only
  workflow defined is `send-newsletter.yml`.
- **Order mattered and was respected:** the `main` run targeted the week production **already showed**
  (09-30), done **before** the Oct 2 import. Production's newest loaded week was still 09-30 (week
  10-05 → 0 rows), so nothing newer could be replaced.
- **A trap avoided:** the rehearsal runs committed to the rehearsal branch itself, so fast-forwarding
  `main` to that branch's tip would have shipped ~79 junk files. Only `ca8a7ed9` was pushed to `main`.
- **A guard hook did its job:** the first push attempt was blocked by `guard-git.ps1` ("could not resolve
  `$SCR/wpf` as a git repository for the pre-push secret scan. Failing closed (F104)") because it reads the
  literal command text before the shell expands a variable. Re-run with a literal path; the secret scan
  ran. A secret scan of everything the branch adds, run beforehand, found nothing.

**What is still unproven, stated plainly:** (1) **no scheduled (cron) run of the new workflow has ever
happened** — Oct 6 is the first, and `schedule` runs on `main` with `inputs` absent, a code path the
dispatch rehearsals exercised only by `mode`/`week` inputs; the expressions are written for it
(`github.event_name == 'schedule' || …`) and nothing has run them yet; (2) **the send itself was only
ever run with `dry_run=true`**, so a real Brevo send from the new workflow is first seen on Oct 6 (the
send script is byte-unchanged; its last real send was run #29 on 2026-09-22, which succeeded); (3) a first week with
**new** thumbnails on `main` (this republish had 0 new) exercises the Pages-build → wait ordering for
real only on Oct 6.

### 11.5 S3 observed — the Oct 6 cron (recorded 2026-10-13)

All three "still unproven" items in § 11.4 were exercised by one run, read from its log on 2026-10-13
(`gh run view 37551468895 --log`, not from the Actions colour):

| Item | Result |
|---|---|
| The `schedule` path (inputs absent) | Run `37551468895`, event `schedule`, `build` and `send` both `success`. It **started 2026-10-07 00:20:44Z, 3 h 20 min after the 21:00Z cron**, i.e. past UTC midnight. The week rule (Mon-Sun containing the **UTC** run date) still resolved correctly because Tue and Wed share a week: `Target week: 2026-10-05 -> 2026-10-11 (the week containing the run date 2026-10-07)`, `72 shipment row(s); on-sale date 2026-10-07 (from 2026-10-06×2, 2026-10-07×70)` |
| A real, non-dry-run send | `sendNow accepted for campaign 35. Verifying actual status... Campaign 35 confirmed SENT.` (Brevo list 7, 12 subscribers) |
| New thumbnails on `main` | `Pull feed published: 72 titles` as **one** commit `cd1412bb` by `github-actions[bot]` (`-88 expired thumb(s)`); `round 1: 32/32 served`; `newsletter-email.html is stamped 2026-10-07 - built by this run` |

**Not part of this result, and the reason F135 is still open:** the old path was still live. Commit
`faf6feaf` (**2026-10-10**, 119 titles, `+119 thumbnail(s)`) was authored by `mrcyberrick`, not the
Actions bot, so the Fri 2026-10-09 shipment import still published through `import.js`'s publish block
with the PAT. S4 removes that; S5 reads the first Tuesday without it.

**Measured delay worth knowing:** the workflow header's cron-drift table stops at +2 h 01 min (09-15);
this run is **+3 h 20 min**. The build and send jobs are adjacent, so only the UTC stamp and week rule
care. The week rule (Mon-Sun containing the UTC run date) stays correct until Sunday; the limit that
bites first is `checkWeek`'s "already on sale" guard, which fails the run loudly (it never publishes a
past issue) if the run starts after the on-sale Wednesday has ended, i.e. from Thu 00:00Z. This run
started at 00:20Z Wednesday, so the margin was about a day.

### 11.6 S4 landed in code (2026-10-13)

Scripts repo `main` **`fc044f9`**, pushed and read back from `origin/main`. Removed from both
`import.js` and `import-staging.js`: `resolveFeedWeek()` and its export; from `import.js` also the whole
publish block (the `GITHUB_TOKEN_PULL_FEED` read, the `resolveFeedWeek(allShip)` call, the
`require('./build-pull-feed.js')` and `publishPullFeed` call), replaced by a 3-line pointer comment.
Deleted: the scripts-repo `build-pull-feed.js` (the copy in `weekly-pull-feed/scripts/` is canonical),
`test/feed-week.test.mjs` (9 tests) and `test/thumb-retention.test.mjs` (12 tests, which `require` the
builder; all 12 names exist in `weekly-pull-feed/test/thumb-retention.test.mjs`). Also touched: the
README row and `.gitignore` allowlist entry for the builder, and two comment lines in
`reconcile-shipment.js` that named it.

| Check | Result |
|---|---|
| `grep -n "publishPullFeed\|resolveFeedWeek\|GITHUB_TOKEN_PULL_FEED"` over `import.js`, `import-staging.js`, `test/*` | **0 lines**, locally and on `origin/main` |
| `node --check` | clean on `import.js`, `import-staging.js`, `reconcile-shipment.js`, `check-dates.js` |
| `npm test` | **333/333** (was 354/354; 354 - 12 - 9 = 333) |
| `--no-write` dry run of `import-staging.js` with a Lunar + PRH shipment pair (a prompt-answering driver, because piped stdin is consumed by the first readline) | exit 0, ran to `Import complete!`; **output line-for-line identical to the run taken before the edit** (108 lines), no publish line. Staging never had a publish call, so this proves the removal changed nothing else, **not** that the production publish is gone |
| `origin/main` | `fc044f9`, local `main` 0 ahead / 0 behind |

**What this does not prove, stated plainly:** (1) `import.js` was not dry-run (the established
convention; its first real run is Rick's Fri 2026-10-16 production import); the removed regions mirror
staging's and the symbol grep is the evidence that the publish is gone. (2) S5/V5 is unmet: no Tuesday
has yet run with the import path gone. **The Tue 2026-10-20 cron is that run**; reminder routine
`trig_017vViYcKefTkoHgdLjC7ArP` and a calendar event, Wed 2026-10-21 8 AM ET. F135 closes there.
(3) `GITHUB_TOKEN_PULL_FEED` is still in the scripts `.env` and the PAT is still live: Rick deletes the
line and revokes the token (deliberately not done by the agent).

---

## References

`docs/technical-reference.md` § 13 — **F135**, **F134**, **F98**/**F100**, **F96**/**F106**, **F84**.
`docs/weekly-pipeline-hardening.md` · `docs/weekly-pipeline-consolidation-plan.md` ·
`docs/newsletter-acquisition-funnel.md` (S6a, the other editor of `build-pull-feed.js`).
