# F72 G-F — the five remaining mail functions and the client signup gate

**STATUS:** NOT STARTED — plan written 2026-11-04 (planning session, read-only; no code, SQL or deploy). Decisions Q12-Q16 below (continuing the F72 plan's Q1-Q11) ANSWERED 2026-11-04, Rick: "defaults" (every recommended column below is the decision). D1 itself is still Rick's, so S3 (the gate) waits on it. | staging=— | prod=— | findings=F72

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
