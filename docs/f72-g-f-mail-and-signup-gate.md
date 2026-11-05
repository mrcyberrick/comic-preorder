# F72 G-F — the five remaining mail functions and the client signup gate

**STATUS:** IN PROGRESS — S1 on staging 2026-11-04 (`6bda474`, V1-V5 green); **S2 DONE 2026-11-05: PR #182 (merge `4ccf239`), all five functions DEPLOYED TO PRODUCTION from `origin/main`, deployed code == main, `verify_jwt` preserved; a real production email from Rick is still owed;** S3 (gate) NOT STARTED, waits on Rick's D1. Decisions Q12-Q16 ANSWERED 2026-11-04 (Rick: "defaults"). | staging=S1 2026-11-04 | prod=S2 2026-11-05 (PR #182) | findings=F72

Parent records: `docs/f72-multi-tenant-branding.md` (design, § 0.1 tier rules, § 4.2 S2) and
`docs/pre-phase-6-gate-closure.md` (row G-F, Phase 6 gate G3). This doc is the execution plan for
the part of F72 that is still open.

---

## 1. Where it stands (re-read from disk 2026-11-04)

**Done:** S0 (the `Tier` mechanism), S1a (web), S3 (print), S2a (`register-customer`, deployed to
production 2026-10-06 as v34 and verified live on `comicstore`), and `register-tenant`'s admin
invite (F153). `tenants_plan_check` is applied on both environments.

**Still open, unchanged since 2026-09-03:** five Edge Functions send Ray & Judy's identity to every
tenant's customers, and the sign-up link shows only on the founding hostname.

`supabase/functions/` is identical on `main` and `staging` (empty `git diff origin/main
origin/staging`), so production runs this same code.

| Function | Who calls it | Tenant id in hand | Founding text in the mail | `verify_jwt` (F99 S1 record; read live before deploy) |
|---|---|---|---|---|
| `approve-customer` | `app.js:2209` (admin Approve) | yes, `target.tenant_id` | subject, header, body, "sent personally by", footer address + phone | **ON** |
| `invite-customer` | `admin.html:4119` (admin Invite) | yes, `callerTenantId` (falls back to `FOUNDING_TENANT_ID`) | same set | OFF |
| `notify-customers` | the import script only (service role, pinned to `FOUNDING_TENANT_ID`); no admin UI calls it | yes | subject, header, footer address + phone | OFF |
| `reset-password` | `forgot-password.html:173` (public) | **no** | subject, header, footer address + phone | OFF |
| `send-my-list` | `app.js:2176` (customer) | yes, `callerTenantId` | both subject lines, header, footer address + phone | **ON** |

**Signup gate:** `index.html:586` reveals "Create one" only when `tenantSlugFromHostname() ===
FOUNDING_TENANT.slug`. The server already accepts any tenant's `slug` (`register-customer`), and
Turnstile already works on `comicstore.pulllist.app` (G-B smoke 6b, 2026-10-06).

## 2. Blocking items

| # | Item | Kind | Blocks |
|---|---|---|---|
| B1 | **D1 is due.** The G-F row says it waits on D1; D1 was "keep Shape D, revisit after the November import", and that import ran 2026-10-28 | Rick's decision (Q12) | the gate only, by the recommendation below |
| B2 | **The sign-up form now links Ray & Judy's own policy.** PR #180 (2026-11-01) added a required "I agree to the Pull-List Policy, Terms and Privacy" box; `policy.html` is Ray & Judy's text (six-week pickup, 10% off), and the comment says it is unconditional *because* signup is founding-only. Opening the gate as-is shows another shop's customers Ray & Judy's terms | code, S3 below | the gate |
| B3 | **`notify-customers` is promotional mail, and the free tier sends no postal address.** § 0.1 Q8 says a free tier's email footer carries no phone or address; § 4.2.3 says the monthly catalog email needs a physical postal address. They conflict for this one function | Rick's decision (Q13) | `notify-customers` only |
| B4 | **Where a paid tenant's footer comes from.** S2a hardcoded Ray & Judy's address and phone for any `pro` tenant. Production `rjbookstop` still has `contact_phone` and `location` NULL (§ 1.7 of the F72 plan, not re-read since 2026-09-01), so a database-driven footer needs a data step first | Rick's decision (Q14) | the paid branch of all five |
| B5 | **Test accounts and inboxes.** Each function needs one real send per tier, and Rick reads the headers. Needs: an admin login and a test customer on staging `demoshop` (free) and on production `comicstore` (free), with mailboxes Rick can read | Rick's input | the staging and production checks |
| B6 | **`MAIL_FROM_NAME` must not be a fallback any more.** Its secret value is "Ray & Judy's Book Stop" on both projects, so any `?? MAIL_FROM_NAME` on a failed tenant lookup re-leaks the founding name. The fallback is the literal `PULLLIST` | design rule, no decision | all five (biggest risk in `reset-password`) |

**Not blockers (checked):** Turnstile on other store hostnames (worked in G-B); the old reason for
keying the gate on the hostname (a broken subdomain fell back to the founding store) is gone,
because F171's fix halts an unknown name (PR #179); `notify-customers`' service-role branch being
founding-only is correct while the import is single-tenant (F131, F169).

## 3. Decisions (each has a recommended default)

| # | Question | Decided 2026-11-04 (Rick: "defaults") | Why |
|---|---|---|---|
| **Q12** | Do the five emails now, under Shape D? | **Yes, emails now; open the gate in the same pass only if D1 says so** | The emails fix a defect that exists today for `comicstore` and `demoshop` (an approved demo customer gets "Ray & Judy's Book Stop"), whatever D1 decides. The gate is the Phase-6-shaped part |
| **Q13** | Free-tier `notify-customers` footer | **On this one email a free tenant's footer shows its own name and `tenants.location` (the F72 plan's Q1 says that holds a full postal address); if `location` is empty, send nothing and log a warning. `pro` keeps today's footer (Q14)** | Keeps the legal requirement without inventing a platform address. Today only the founding tenant (`pro`) can trigger it, so it changes nothing live |
| **Q14** | Paid footer source | **Keep S2a's literal for `pro` (Ray & Judy's), one copy per function** | Byte-identical to today for the only paying tenant and needs no data step. A second paid tenant then needs the database-driven footer in all six functions plus the `rjbookstop` data fill; record that in the onboarding runbook |
| **Q15** | Add the tier-gated "View Online" footer link (§ 0.1) now? | **No, defer** | New copy in six templates, not needed to remove founding identity. Changing the action links' targets also needs a check of each Supabase project's Auth redirect allow-list for `rjbookstop.pulllist.app`, which nobody has read |
| **Q16** | The Pull-List Policy link on the sign-up form for other shops | **Founding only: other shops agree to Terms and Privacy only** | `policy.html` is one store's terms. A per-tenant policy page is new work |

## 4. Sessions

### S1 — five functions on staging (one session; code, no client page)

1. Step 0: read each function's live `verify_jwt` on staging by behaviour (an unauthenticated POST:
   the function's own error body means OFF; the gateway's "Missing authorization header" means ON).
2. One shared block, byte-identical in all five (Q11): `escapeHtml()`, `fetchTenantIdentity(tenantId)`
   returning `{ storeName, isPaid }` from `tenants?id=eq.<id>&select=display_name,plan`, and the
   paid footer builder. On any lookup failure: `storeName = 'PULLLIST'`, `isPaid = false` (B6).
3. Per function: `from` display name, subject, header line, body and footer use `storeName`
   (escaped in HTML); phone and address only when `isPaid`. `from.email` untouched.
4. `reset-password`: tenant from `generateData.user.id` → `user_profiles.tenant_id`, looked up only
   after the existing early return. The `{ success: true }` response must be byte-identical for an
   existing and a non-existing address (no new enumeration signal).
5. `notify-customers`: per Q13.
6. Deploy to staging one at a time, flags matching step 0 (`approve-customer` and `send-my-list`
   without `--no-verify-jwt` if they read ON), re-read `verify_jwt` after, download the artifact and
   hash it against the committed file.

### S2 — production (one session, Rick's explicit `/promote-prod`)

PR of `supabase/functions/` + docs (merging changes nothing at runtime), then deploy the five
functions from a worktree of `origin/main`, the G-B procedure: rollback artifacts saved first,
`verify_jwt` read before and after, hashes compared. Live checks on `comicstore` (free); the paid
branch rests on V1's byte-identical proof plus one `reset-password` to Rick's own account.

### S3 — the signup gate (one session, after S2, and only if Q12/D1 allow)

`index.html` only: reveal "Create one" on any tenant hostname that resolved through the hostname
(not on the apex, `*.pages.dev` or a halted name); the policy link and the agreement error text per
Q16; update the two comments that say "founding tenant only". Staging cannot complete a sign-up
(Turnstile rejects `*.pages.dev`, no store hostname exists there), so: a local harness with
`register-customer` stubbed, plus spec 12 and the full suite on the deployed bytes. Production: a
real sign-up on `comicstore` by Rick, approve it as `comicstore`'s admin, read the approval email,
delete the test account.

## 5. Verification gates

| Gate | Check |
|---|---|
| V1 | Template harness (the S2a method): extract each mail builder from `git show HEAD` and from the edited file. **Ray & Judy's (`pro`) subject, `from` and HTML byte-identical to today**; a free tenant's mail contains its own name and none of "Ray", "Judy", "Rockaway", "Main St", "973"; a hostile `display_name` is escaped; the lookup-failure path says PULLLIST. One assertion seen red, then reverted |
| V2 | Grep: the shared block hashes identically in all five files (Q11's V10) |
| V3 | `verify_jwt` by behaviour before and after each deploy; artifact hash == committed |
| V4 | `reset-password`: status and body identical for an existing and an unknown address |
| V5 | Real inbox, headers only (Rick; link replaced by `[link]`): one send per function per tier on staging, `dkim`/`spf`/`dmarc` pass, correct `From`. `notify-customers` only if every recipient in the test tenant is a throwaway (count them first); otherwise V1 only |
| V6 | S3: harness (gate shown on a store hostname, hidden on apex / `*.pages.dev` / a halted name; the policy link per Q16), spec 12, full suite on the deployed bytes |

## 6. Out of scope

`register-customer` (already done; its user-submitted `name` is interpolated unescaped into the
greeting of the customer's own email, observed, not filed); the pricing copy at `index.html`
247-262 (S4); per-tenant sending addresses (Q10); the database-driven paid footer and the
`rjbookstop` contact data (Q14); "View Online" links (Q15); a per-tenant policy page (Q16);
`notify-customers` for non-founding tenants through the import (F131, F169).

## 7. Rollback

Functions: redeploy the saved previous artifact with the same `verify_jwt` flag. Gate: revert the
`index.html` commit (Cloudflare Pages redeploys `main`).

---

## 8. S1 result — 2026-11-04

**Code (`6bda474`, staging, pushed):** the five functions, +394 / -58. One shared block, byte-identical in
all five (`escapeHtml`, `mailFromName`, `fetchTenantIdentity`, `PAID_CONTACT_HTML`, fallback
`PULLLIST`). `MAIL_FROM_NAME` is no longer read by any of the five (its secret is Ray & Judy's name).
`from.email` untouched; links and `APP_BASE_URL` untouched (Q15).

**Verified:**
- **V1** harness (local, scratchpad `gf/harness.mjs`): each function's OLD (`git show HEAD`) and NEW file run
  under Node with a fake Deno and fake network, comparing what reaches Resend. **48/48.** For the founding
  tenant (`pro`, `Ray & Judy's Book Stop`) the From, subject and HTML are **byte-identical** to the old code in
  all five; a free tenant gets its own name in From/subject/body and none of "Ray", "Judy", "Rockaway",
  "Main St", "973"; a failed lookup says PULLLIST; a hostile name is escaped in HTML and stripped in From;
  `notify-customers` for a free shop with no `location` returns 422 and sends nothing. **Negative controls
  red:** one changed digit in the paid phone (1 fail), and the old code run as "new" (26 fails).
- **V2:** the shared block hashes `5dfc44bc878611bb` in all five.
- **V3:** staging `verify_jwt` read by behaviour before and after: `approve-customer` and `send-my-list` ON,
  the other three OFF, unchanged. Deployed artifacts downloaded and hashed: all five equal the committed
  files. Rollback copies (the pre-change code, which staging was running) are in the session scratchpad;
  re-derive from `6bda474~1` if that is gone.
- **V4:** harness (known and unknown address give the same response) plus a live unknown-address probe on
  staging: `{"success":true}`, HTTP 200.
- Staging's founding tenant `display_name` read as exactly `Ray & Judy's Book Stop`, so the byte-identical
  result applies there.

**Not verified:**
- ~~**V5, real inboxes (Rick):** no real email was sent by this session.~~ **V5 DONE 2026-11-04/05 (Rick's three
  pastes, read by me):** (1) Ray & Judy's invite: From `Ray & Judy's Book Stop <noreply@pulllist.app>`, address and
  phone footer present; (2) `demoshop` invite: From `Capital City Comics`, its name throughout, no address, phone or
  Ray & Judy's text; (3) reset for the `demoshop` address: From `Capital City Comics`, no contact paragraph, and
  Rick reports the reset link worked. All three `dkim=pass` (`pulllist.app` and `amazonses.com`), `spf=pass`,
  `dmarc=pass`; links direct, no tracker. Received by a PrivateEmail-hosted mailbox, so inbox versus spam at other
  providers is not established. Both test accounts deleted afterwards (profile re-read 0, auth 404; the `demoshop`
  one left 4 `usage_events`, kept with `user_id` NULL by design). To sign in as the `demoshop` admin
  (`demo-admin@example.test`, no inbox) a password was set on that staging account. Observed, pre-existing and
  unchanged by S1: the reset greeting used the email's local part ("devdemo") rather than the invite's full name.
- ~~**Production's `rjbookstop` `display_name`:** my read was refused by the session's permission check. If it is
  not exactly `Ray & Judy's Book Stop`, Ray & Judy's mail will change in that one string. Rick checks it before S2:
  `SELECT slug, display_name, plan FROM public.tenants ORDER BY slug;`~~ **CHECKED 2026-11-04 (Rick ran the query on
  production):** `rjbookstop` = `Ray & Judy's Book Stop`, `pro`; `comicstore` = `The Comic Store`, `free`. So the
  byte-identical result applies on production too; this S2 precondition is met. (`comicstore`'s `location` was not
  read; with none, its catalog email returns 422 and sends nothing, per Q13.)
- `approve-customer` and `send-my-list` were never run live after the change; the harness is the evidence.
- Staging `demoshop`'s `location` is `Springfield, IL`, not a postal address; only matters if someone sends its
  catalog email.

**V5 steps for Rick (staging, headers only, replace the link with `[link]`):**
1. Signed in as Ray & Judy's admin on staging, Customers > Invite a throwaway address you can read. Expect
   From `Ray & Judy's Book Stop <noreply@pulllist.app>` and the address/phone footer, as today.
2. Signed in as `demoshop`'s admin (`?t=demoshop`), invite a second throwaway address. Expect From
   `Capital City Comics <noreply@pulllist.app>`, no address/phone, no Ray & Judy's anywhere.
3. On `forgot-password.html`, request a reset for the step-2 address. Expect From `Capital City Comics`.
Then tell me the two addresses and I delete both test accounts.

## 9. S2 result (2026-11-05, production)

Rick: `/promote-prod`, then merged PR #182 (merge `4ccf239`; promotion commit `bad6de3`, parents `59362be` main +
`8b42450` staging tip). The PR is 8 files: the five functions and three docs; re-read on GitHub, no `config.js`,
nothing under `supabase/migrations/`.

**Gates before the PR:** step 0 found no pending SQL; merge result of all five functions == staging, `app.js` and
every page identical on both branches, `config.js` == `origin/main` (prod ref x1, staging ref x0), migrations 2 files.

**Deploy, from a worktree of `origin/main` at `4ccf239`:**
- `verify_jwt` read on production by behaviour BEFORE the deploy: `approve-customer` and `send-my-list` ON (gateway
  `UNAUTHORIZED_NO_AUTH_HEADER`), `invite-customer`, `notify-customers`, `reset-password` OFF (their own errors).
  Deployed accordingly (`--no-verify-jwt` only on the three OFF ones); re-read AFTER: unchanged.
- Rollback: the live versions were downloaded first and equal `4ccf239^1`'s copies modulo CR, so the previous code
  is `git show 4ccf239^1:supabase/functions/<name>/index.ts`. Versions before -> after: approve-customer 30 -> 31,
  invite-customer 52 -> 53, notify-customers 42 -> 43, reset-password 30 -> 31, send-my-list 31 -> 32.
- Deployed artifacts downloaded and hashed (CR stripped): equal to `main` and to staging's deployed copies
  (approve `bb54919799fa`, invite `59bf28adb893`, notify `9ef4e9e7f0e1`, reset `84096b20ec3d`, send `413e0071c7ae`);
  shared block one hash (`5dfc44bc`) across all five.
- Live probe: an unknown-address reset on production returns `{"success":true}`, HTTP 200.

**Not verified:** no real production email has been read yet (Rick's check, headers only); `approve-customer`,
`send-my-list` and `notify-customers` have not sent live on production since the deploy; inbox versus spam is not
established. Write-smoke skipped: no web byte changed, nothing on the reserve path.
