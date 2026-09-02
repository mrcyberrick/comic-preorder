# F99 — Resend migration: cut the six Edge Functions over from MailerSend

**STATUS:** **COMPLETE, BOTH ENVIRONMENTS, GREEN — 2026-09-02, same day as the plan was written.**
M1–M7 all executed; V1–V7 all green. Production real send authenticated perfectly but surfaced a
separate, unrelated finding (**F152** — Outlook spam placement, Rick's call: monitor, not act) filed
during M7. | staging=`85ce9ce` (code) + secrets set | prod=PR #148 (merge `4a4a475`) + secrets set,
both live | findings=F99,F72,F148,F145,F152

**What this is:** the actual cutover, following `docs/f99-resend-discovery.md`'s **GREEN** result
(2026-09-02). That session proved Resend works from a brand-new account with zero bearing on
production: `pulllist.app` verified, alignment measured clean (DKIM exact-match + SPF aligned), no
tracking artifacts, no unsubscribe injection. This plan turns that into code. **Not started, not
executed — written the same day as the discovery, as its own completion criteria require.**

Read `docs/f99-resend-discovery.md` and `docs/f99-sender-domain-consolidation.md` § 10 before
executing this. Addressing is **decided**: flat `noreply@pulllist.app` for all tenants (§ 3 of the
discovery doc) — not per-tenant subdomains. Do not re-litigate that here.

---

## 1. What's actually changing — measured from the live code, 2026-09-02

All six functions' MailerSend call is **byte-identical in shape**, verified by reading all six files
directly rather than assuming S1's parameterization implied anything about the call shape itself:

| Function | Endpoint line | `from`/`to` lines |
|---|---|---|
| `reset-password/index.ts` | 68 | 75–76 |
| `invite-customer/index.ts` | 105 | 112–113 |
| `notify-customers/index.ts` | 183 | 190–191 |
| `approve-customer/index.ts` | 159 | 166–167 |
| `send-my-list/index.ts` | 239 | 246–247 |
| `register-customer/index.ts` | 139 | 146–147 |

Every one reads `MAILERSEND_API_KEY` from `Deno.env.get()`, posts to
`https://api.mailersend.com/v1/email`, and builds `from: { email: MAIL_FROM_EMAIL, name:
MAIL_FROM_NAME }` / `to: [{ email, name }]` — an **object** shape for both. This confirms the parent
plan's own estimate ("~4 lines each plus a secret") rather than assuming it.

**The diff, per function, mechanical and identical six times:**

| | MailerSend (today) | Resend (target) |
|---|---|---|
| Endpoint | `https://api.mailersend.com/v1/email` | `https://api.resend.com/emails` |
| New secret | — | `RESEND_API_KEY` |
| Auth header | `Bearer ${MAILERSEND_API_KEY}` | `Bearer ${RESEND_API_KEY}` |
| `from` shape | `{ email: MAIL_FROM_EMAIL, name: MAIL_FROM_NAME }` (object) | `` `${MAIL_FROM_NAME} <${MAIL_FROM_EMAIL}>` `` (string — confirmed real, D3) |
| `to` shape | `[{ email, name }]` (array of objects) | `email` or `[email, ...]` (plain string(s), no name field) |
| `html` field | present | present, unchanged (confirmed, D3) |

**`MAIL_FROM_EMAIL` / `MAIL_FROM_NAME` don't get renamed** — same two secrets S1 already built,
same `Deno.env.get(...) ?? '<literal fallback>'` pattern. Only their **value** changes, from
`noreply@mrcyberrick.us` to `noreply@pulllist.app` (§ 3's flat decision).

**⚠️ One property S1 was explicitly designed around does NOT carry over to this migration, and it's
worth being precise about why.** S1's whole point was making a *same-provider* domain swap a secret
flip with no code deploy in the risk window. This is a *cross-provider* swap — the request **shape**
differs (object `from`/`to` vs. string `from`, array-of-plain-strings `to`), so a code deploy is
unavoidable here. That doesn't make this riskier than S3, though — the opposite, see § 2.

---

## 2. Why this is structurally safer than S3, not just "hopefully so"

S3's entire danger was **domain-slot contention within one MailerSend account**: the old sender had
to be *removed* before the new one could be *added*, so every attempt cost a live outage window by
construction, and the ~50–55 minute real outage came directly from that.

**Resend and MailerSend are two independent accounts on two independent services.** Nothing has to
be removed from either for the other to work. Consequences:

- **The old sender (`MAILERSEND_API_KEY` calling MailerSend) keeps working, unmodified, for the
  entire time this code is written, deployed to staging, and tested** — there is no equivalent of
  "the free tier only allows one domain."
- **`pulllist.app` is already fully verified in Resend, today**, with real production-shaped sends
  already exercised in the discovery session (D6) — none of S3's "cold domain, `0 Sent`,
  `#MS42207`" uncertainty applies. The domain isn't new the day this migration runs; it's already
  hours or days old with a clean send history.
- **Deploying a Supabase Edge Function is a matter of seconds, not a DNS/domain-slot operation.**
  Rollback is redeploying the previous function version — no domain to re-add, no DNS to wait on.
- **Maintenance Mode is arguably not structurally required at all** (unlike S3, where it covered a
  real gap while the only working sender was gone). Recommended anyway during the actual per-function
  deploy window as ordinary defense-in-depth, not because the architecture forces it — Rick's call,
  § 7.

---

## 3. Work breakdown

### M1 — Add `RESEND_API_KEY` secret (staging first)

```
supabase secrets set RESEND_API_KEY=<value> --project-ref puoaiyezsreowpwxzxhj --workdir "<repo path>"
```

F93 discipline: explicit `--workdir`, watch the CLI's "Using workdir ..." line.

> ✅ **DONE 2026-09-02.** Rick's call: a **fresh dedicated key** (Sending-access scope, not the
> discovery session's key) — asked explicitly since the plan left it open. Set by Rick via
> `supabase secrets set` (same credential-touching-command discipline as every other secret in this
> project). Confirmed present via `supabase secrets list --project-ref puoaiyezsreowpwxzxhj` —
> digest `5d0c32d...`, names-only per the CLI's own behavior. **This CLI version (2.75.0) never
> printed a "Using workdir ..." line on any `secrets set`/`functions deploy` call this session** —
> noted as a discrepancy from F93's documented tell, not something to chase; `--workdir` was passed
> explicitly every time and the correct repo's files were unambiguously what got deployed (matched
> filenames in each deploy's own "Uploading asset" line).

### M2 — Rewrite each function's mail-send block (staging, code)

Apply the § 1 diff to all six files. **Read and preserve each function's live `verify_jwt` setting
before deploying** — same F93/S1 discipline, a deploy with no `config.toml` in the repo can silently
reset it, and `approve-customer`/`send-my-list` are the two currently JWT-ON (CLAUDE.md § Supabase
platform facts).

> ✅ **DONE 2026-09-02.** Live `verify_jwt` read via `supabase functions list -o json` **before any
> edit** — matched CLAUDE.md exactly (`approve-customer`/`send-my-list` ON, the other four OFF).
> All six files rewritten on `feature/f99-resend-migration-m2`, committed (`85ce9ce`), merged
> `--ff-only` to `staging`, pushed. Deployed one at a time — the four OFF functions with
> `--no-verify-jwt` explicit, the two ON functions with no flag (CLI default is verify_jwt=true with
> no `config.toml` present, confirmed this is what "no flag" actually produced, not assumed).
> **V1 green:** `grep -rn "api.mailersend.com" supabase/functions/` → 0; diff matches § 1's table
> exactly (endpoint, secret name, auth header, `from` string shape, `to` plain-string shape, `html`
> unchanged) in all six files. **V7 green:** `grep -rn "MAILERSEND_API_KEY" supabase/functions/` → 0
> (one explanatory comment that would have tripped this was reworded before committing). The
> deliberate `noreply@mrcyberrick.us` fallback literals in the `MAIL_FROM_EMAIL ??` default are
> unchanged in all six files, per this step's own note — 6 occurrences, untouched.

### M3 — Set `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` to the Resend-verified sender (staging)

`noreply@pulllist.app` / the brand name — **must land together with M2, not phased apart the way
S1's fallback allowed.** Unlike S1 (same-provider swap, where the fallback literal
`noreply@mrcyberrick.us` was still a *working* MailerSend sender), that same fallback here would be
useless as a safety net: `mrcyberrick.us` was never verified in Resend and isn't going to be. If M2
deploys before M3, sends fail — **loudly**, per D7's own measured shape (`403 validation_error`,
domain not verified), the same "fails loud, not silent" property S1's design note already called for
with MailerSend's `422`. Confirm this is the intended failure mode before treating it as a surprise
mid-deploy.

> ✅ **DONE 2026-09-02, landed with M1 in one combined `supabase secrets set` call** — sequenced
> deliberately before M2's deploy, so the loud-failure window this note describes never actually
> occurred. `MAIL_FROM_EMAIL` set to `noreply@pulllist.app` (digest changed: `3ee1c46...` →
> `78f5a8b8...`, confirming the value actually changed, not just re-set). `MAIL_FROM_NAME`'s digest
> is **unchanged** (`68ee1d6...` both before and after) — correct, not a miss: the brand name itself
> ("Ray & Judy's Book Stop") doesn't change between providers, only the address does.

### M4 — V1: staging functional test, real sends, delivered headers

Trigger at minimum `reset-password` and `register-customer` for real on staging. Read the delivered
message from Gmail `Show original` — not the API's success response, per this entire project's
standing discipline. Confirm: `From:` reads the new sender correctly formatted, `dkim=pass
d=pulllist.app`, `spf=pass` aligned, `dmarc=pass`, and — importantly — **confirm whether Supabase
Auth's own magic-link email is in scope here at all.** These six functions are PULLLIST's *custom*
transactional mail; magic-link sign-in may be issued through Supabase's own built-in email templates,
a separate mechanism this plan has not confirmed one way or the other. **Verify this before assuming
magic-link auth needs no change** — do not carry the assumption from S1/S3's own scope without
re-checking it here.

> ✅ **DONE 2026-09-02.** Two real sends triggered, both read from delivered headers (not the API's
> success response):
>
> 1. **`reset-password`**, via direct `curl` to the deployed staging endpoint, to
>    `rssedivec@gmail.com` (a real account on staging, per S1's own prior use of the same address).
>    Delivered headers (Gmail `Show original`): `dkim=pass header.i=@pulllist.app header.s=resend`
>    (exact match), `spf=pass smtp.mailfrom=...@send.pulllist.app` (aligned via the organizational
>    domain), `dmarc=pass (p=NONE)`, `From: Ray & Judy's Book Stop <noreply@pulllist.app>`. Link
>    un-rewritten (`staging.pulllist.pages.dev/forgot-password.html?token_hash=...`), no injected
>    tracking pixel, no `List-Unsubscribe` header.
> 2. **`invite-customer`**, triggered by Rick from the live admin panel on staging (substituting for
>    `register-customer`, which needs a real Cloudflare Turnstile token this session cannot produce —
>    same untestable-headlessly limitation this project's own F149 already recorded; Rick's call to
>    accept this as the second confirmation rather than chase a DevTools workaround). Delivered
>    headers, read at a **different** receiving MTA (`jellyfish.systems`/`privateemail.com`, not
>    Gmail): `dkim=pass header.d=pulllist.app header.s=resend` (exact match), `spf=pass` aligned via
>    `send.pulllist.app`, `dmarc=pass (policy=none)`, correct `From:`. The body's `action_link` still
>    points at `puoaiyezsreowpwxzxhj.supabase.co/auth/v1/verify...` (Supabase's own link, untouched
>    by this migration) and is un-rewritten.
>
> **`register-customer`'s live UI check was not completed this session** — Turnstile-gated, no real
> tenant-hostname URL exists on staging (`*.pages.dev` is hard-coded to the apex bucket in
> `index.html`'s pre-paint script; confirmed in code, not assumed — this project's own
> `native-signup-verify.mjs` has to fake the hostname via Playwright request-interception to reach
> this form at all). Accepted as a residual, Rick's explicit call, same disposition F149 gives this
> exact class of check. The two real sends above share `register-customer`'s identical request shape
> (same secrets, same endpoint, same `from`/`to`/`html` construction), so the underlying Resend
> integration this migration actually changed is proven either way.

### M5 — V2: full regression suite

`run-smoke.ps1`, full run, against deployed staging bytes post-push (not pre-push — see CLAUDE.md
§ Smoke-test ordering). Confirm no unrelated regression; this touches only Edge Function internals,
not `app.js`/HTML, so a client-side diff is not expected but should not be assumed.

> ✅ **DONE 2026-09-02.** Run directly (not through an agent PowerShell tool, per CLAUDE.md's
> 2026-08-30 note) — unit stage `npm test` in the scripts repo: **279/279 passed**. Playwright stage,
> `npx playwright test --reporter=line` against `https://staging.pulllist.pages.dev/`: **143 passed,
> 0 failed, exit 0, 22.1 minutes** — real "N passed" text present in the output, not a truncated
> false-green (the exact failure mode CLAUDE.md's own note warns about). No client-side diff, as
> expected — this change never touched `app.js`/HTML.

### M6 — Promote to production (separate, explicit request per CLAUDE.md § Staging Only)

Set `RESEND_API_KEY` + the updated `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` values on the production
project (`plgegklqtdjxeglvyjte`), deploy the six updated functions one at a time, preserving each
`verify_jwt` setting. **This step is not authorized by this plan being written** — same as every
other production promotion in this project, it needs Rick's explicit request and confirmation that
staging has soaked.

> ✅ **DONE 2026-09-02, same day, Rick's explicit request ("start M6/M7").** Code promoted via PR
> #148 (`feat/f99-resend-migration-prod` → `main`, merge `4a4a475`). **A real surprise surfaced
> during the merge, not a formality:** production's `main` had never actually received F99 S1's
> parameterization — every prior promotion since 2026-08-31 (F149's, explicitly recorded; by the
> same pattern presumably the rest) deliberately restored these six files to their pre-S1
> hardcoded-literal state after merging, mirroring `config.js`'s own preservation step. So the merge
> conflicted on all six files (main: old hardcoded object shape; staging: parameterized-then-Resend
> string shape), resolved by taking staging's side wholesale (`git checkout --theirs`), verified
> byte-identical to `origin/staging` by hash before committing. This promotion is therefore the one
> that finally carries S1 forward too, not only M2. F125 tree-integrity checks all green:
> `supabase/migrations/` still exactly 2 files, `config.js` still carries the prod ref, PR file list
> matched intent on GitHub itself (12 files: the six functions + doc set, no `config.js`, no
> migrations).
>
> **Secrets:** Rick set `RESEND_API_KEY` + `MAIL_FROM_EMAIL=noreply@pulllist.app` via
> `supabase secrets set` against `plgegklqtdjxeglvyjte` — **reused the same Resend API key as
> staging**, a deliberate choice (not the "fresh dedicated key per environment" pattern M1 used on
> staging). Confirmed via `supabase secrets list` digest comparison (`RESEND_API_KEY` digest matches
> staging's exactly; `MAIL_FROM_EMAIL` digest changed from its pre-migration value; `MAIL_FROM_NAME`
> unchanged, as expected).
>
> **`verify_jwt` read live before deploy, matched staging exactly** (`approve-customer`/
> `send-my-list` ON, other four OFF) — deployed one at a time with `--no-verify-jwt` on the four OFF
> functions, no flag on the two ON functions. **V2 re-confirmed post-deploy, identical.**

### M7 — Post-cutover verification (production)

Real delivered-header check on at least one production send (`reset-password` is the lowest-risk
candidate, matching S1's own choice). **This will NOT be byte-identical to pre-migration** the way
S1's regression control was — the sending domain itself changes (`mrcyberrick.us` → `pulllist.app`)
by design. The control is "arrives, correctly branded, `dkim=pass`/`spf=pass`/`dmarc=pass`," not
byte-for-byte sameness.

> ✅ **DONE 2026-09-02.** Real `reset-password` send triggered via direct `curl` against
> `plgegklqtdjxeglvyjte`, to `rick.sedivec@outlook.com`. Delivered headers, read from the actual
> message (not the API's `{"success":true}`): `spf=pass smtp.mailfrom=send.pulllist.app`,
> `dkim=pass header.d=pulllist.app` (verified) **+** `dkim=pass header.d=amazonses.com` (verified),
> `dmarc=pass action=none`, **`compauth=pass reason=100`** (Microsoft's own composite-authentication
> verdict — a stronger signal than Gmail/Google ever reports), correct
> `From: Ray & Judy's Book Stop <noreply@pulllist.app>`. **Every technical check this gate asks for
> passes, cleanly.**
>
> **A real, separate finding surfaced anyway: the message landed in spam.** Filed as **F152**
> (`docs/technical-reference.md` § 13) rather than treated as a V6 failure — it isn't one; nothing
> V6 checks for is wrong. Reads as cold-start reputation cost for the brand-new `pulllist.app`
> sender identity specifically with Microsoft (no prior send history there, unlike `mrcyberrick.us`'s
> years of it), not confirmed as the sole cause. Gmail and a third-party relay both delivered cleanly
> in this session's earlier tests. Mitigated by `forgot-password.html`'s pre-existing "check your
> spam folder" copy. **Rick's explicit call: monitor real customer traffic over the following days to
> weeks, do not act unless it doesn't self-resolve.**

### M8 — Retire `MAILERSEND_API_KEY` (later, optional)

No urgency. Consistent with this project's own S3-rollback discipline ("do not delete the old
records until S4 has been green for at least one full monthly cycle"), keep the MailerSend secret
and account dormant as a documented rollback path for some soak period before fully decommissioning.
Not scoped in this plan — a future, explicit decision.

---

## 4. Verification gates

| Gate | Assertion | Result |
|---|---|---|
| **V1** | All six functions' diff matches § 1's table exactly; `grep -rn "api.mailersend.com" supabase/functions/` returns 0 post-M2 | ✅ **GREEN** — diff matches exactly, grep → 0 |
| **V2** | Each function's `verify_jwt` setting identical before and after deploy (dashboard read both times) | ✅ **GREEN** — read live via CLI both times, all six identical (2 ON, 4 OFF) |
| **V3** | Staging real sends (M4) — delivered headers show `dkim=pass d=pulllist.app`, `spf=pass` aligned, `dmarc=pass`, correct `From:` display name | ✅ **GREEN** — `reset-password` + `invite-customer`, both from delivered headers, both clean; `register-customer` a recorded residual (Rick's call) |
| **V4** | Full `run-smoke.ps1` green against deployed staging bytes, post-push | ✅ **GREEN** — 279 unit + 143 Playwright, 0 failures, exit 0 |
| **V5** | Magic-link auth path confirmed either unaffected (Supabase-native) or explicitly migrated — not assumed either way | ✅ **GREEN** — confirmed by code trace, not assumed: no separate Supabase-native mail path exists anywhere in the app; `signInWithOtp`/`resetPasswordForEmail`/`inviteUserByEmail` are never called client-side. All magic-link/invite/reset mail already goes through the six functions this migration covers |
| **V6** | Production real send (M7) — same header checks as V3, against `plgegklqtdjxeglvyjte` | ✅ **GREEN** — `dkim=pass d=pulllist.app` + `amazonses.com`, `spf=pass` aligned, `dmarc=pass`, `compauth=pass reason=100`. Landed in spam anyway — filed as **F152**, not a V6 failure (see M7 above) |
| **V7** | `MAILERSEND_API_KEY` and the six functions' old endpoint confirmed absent from the final deployed code (`grep` returns 0) | ✅ **GREEN** — both return 0 in the final committed code |

---

## 5. Rollback

Redeploy the previous function version (`git revert` the M2 commit, `supabase functions deploy
<name>` per function) — no domain to re-add, no DNS to wait on, no account-level state to undo.
Materially simpler than S3's rollback because nothing about MailerSend was ever touched to make this
migration work; MailerSend keeps its own verified domain and working sender the entire time, whether
this migration is mid-flight, rolled back, or abandoned.

---

## 6. Out of scope — stop and ask

- **F148's actual fix** (bulk/batch endpoint, or accepting metered overage cost). D8 measured its
  shape under Resend; fixing it is separate work.
- **F72's per-tenant branding body-copy substitution.** Unaffected by provider choice.
- **Per-tenant subdomain addressing.** Decided flat (§ 3 of the discovery doc). Revisit only as an
  explicit future paid-tier decision.
- **Retiring `mrcyberrick.us` as a domain.** Only the sending identity moves, same as F99's original
  scope.
- **Retiring MailerSend entirely.** M8 is optional, later, not scoped here.

---

## 7. Open questions for Rick

1. **Timing** — clear of the 2026-09-25 October import gate, same constraint every F99 sub-step has
   carried.
2. **Use Maintenance Mode defensively during the M2/M6 deploy windows even though § 2 argues it
   isn't structurally required?** Low cost either way; your call.
3. **How long to keep `MAILERSEND_API_KEY` as a dormant rollback path (M8) before retiring it?**
   Not urgent — can be answered whenever M7 is green.

---

## Reference

- **`docs/f99-resend-discovery.md`** — the GREEN discovery this plan follows. Full measured evidence:
  alignment headers, D7's rejection text, K1–K6 evaluation.
- **`docs/f99-sender-domain-consolidation.md`** § 10 — the decision record.
- **F148** — daily-cap shape under Resend, measured (D8), not fixed here.
- **F72** — per-tenant branding; unaffected by provider choice.

**Last updated:** 2026-09-02 (second pass, same day) — **M1–M5 executed end to end, staging COMPLETE
and GREEN.** RESEND_API_KEY set (fresh dedicated key, Rick's call), all six functions rewritten
exactly per § 1's diff table and deployed with `verify_jwt` preserved (V1/V2/V7 green),
`MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` flipped to `noreply@pulllist.app` (M3 landed with M1, before any
code deploy — the loud-failure window this doc warned about never occurred), two real sends
(`reset-password`, `invite-customer`) confirmed clean from delivered headers at two different
receiving MTAs (V3 green), magic-link auth path traced in code and confirmed fully covered by this
migration — no separate path exists (V5 green), full regression suite green (279 unit + 143
Playwright, V4 green). `register-customer`'s live UI check accepted as a residual — Turnstile-gated,
no real tenant-hostname URL exists on staging, same disposition F149 already established for this
exact class of check; the two functions actually exercised share its identical request shape.
~~**M6 (production promotion) NOT started**~~ — **superseded below.** First pass: written, same
session as the discovery's GREEN result, not started.

**Last updated:** 2026-09-02 (third pass, same day, Rick's explicit request "start M6/M7") —
**M6/M7 executed, COMPLETE on production too.** Code promoted via PR #148 (merge `4a4a475`) — the
merge conflicted on all six functions because production's `main` had never received F99 S1's
parameterization (every prior promotion had deliberately restored these files to hardcoded
literals, mirroring `config.js`'s preservation pattern); resolved by taking staging's side wholesale,
verified byte-identical by hash. F125 tree-integrity checks green (migrations still 2 files,
`config.js` still prod ref, PR file list matched intent on GitHub). Secrets set by Rick
(`RESEND_API_KEY` — reused the same key as staging, his explicit choice this time, not a fresh one;
`MAIL_FROM_EMAIL` → `noreply@pulllist.app`). All six deployed, `verify_jwt` preserved and
re-confirmed post-deploy (V2 green again). **V6: real production send, authentication fully
clean** — `dkim=pass d=pulllist.app` + `amazonses.com`, `spf=pass` aligned, `dmarc=pass`,
`compauth=pass reason=100` — **but it landed in spam**, filed as **F152** (cold-start Microsoft
reputation, not a technical defect; Rick's call: monitor, don't act). Write-smoke deliberately
skipped — this migration never touches `app.js`/HTML or the customer reserve path, confirmed via
the production diff itself (Edge Functions + docs only). **Both environments now fully cut over to
Resend.** MailerSend secrets left in place on both projects as a dormant rollback path (M8, optional,
not scoped here).
