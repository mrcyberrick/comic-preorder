# F99 — Resend migration: cut the six Edge Functions over from MailerSend

**STATUS:** PLANNED — not started | staging=untouched | prod=untouched | findings=F99,F72,F148,F145

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

### M2 — Rewrite each function's mail-send block (staging, code)

Apply the § 1 diff to all six files. **Read and preserve each function's live `verify_jwt` setting
before deploying** — same F93/S1 discipline, a deploy with no `config.toml` in the repo can silently
reset it, and `approve-customer`/`send-my-list` are the two currently JWT-ON (CLAUDE.md § Supabase
platform facts).

### M3 — Set `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` to the Resend-verified sender (staging)

`noreply@pulllist.app` / the brand name — **must land together with M2, not phased apart the way
S1's fallback allowed.** Unlike S1 (same-provider swap, where the fallback literal
`noreply@mrcyberrick.us` was still a *working* MailerSend sender), that same fallback here would be
useless as a safety net: `mrcyberrick.us` was never verified in Resend and isn't going to be. If M2
deploys before M3, sends fail — **loudly**, per D7's own measured shape (`403 validation_error`,
domain not verified), the same "fails loud, not silent" property S1's design note already called for
with MailerSend's `422`. Confirm this is the intended failure mode before treating it as a surprise
mid-deploy.

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

### M5 — V2: full regression suite

`run-smoke.ps1`, full run, against deployed staging bytes post-push (not pre-push — see CLAUDE.md
§ Smoke-test ordering). Confirm no unrelated regression; this touches only Edge Function internals,
not `app.js`/HTML, so a client-side diff is not expected but should not be assumed.

### M6 — Promote to production (separate, explicit request per CLAUDE.md § Staging Only)

Set `RESEND_API_KEY` + the updated `MAIL_FROM_EMAIL`/`MAIL_FROM_NAME` values on the production
project (`plgegklqtdjxeglvyjte`), deploy the six updated functions one at a time, preserving each
`verify_jwt` setting. **This step is not authorized by this plan being written** — same as every
other production promotion in this project, it needs Rick's explicit request and confirmation that
staging has soaked.

### M7 — Post-cutover verification (production)

Real delivered-header check on at least one production send (`reset-password` is the lowest-risk
candidate, matching S1's own choice). **This will NOT be byte-identical to pre-migration** the way
S1's regression control was — the sending domain itself changes (`mrcyberrick.us` → `pulllist.app`)
by design. The control is "arrives, correctly branded, `dkim=pass`/`spf=pass`/`dmarc=pass`," not
byte-for-byte sameness.

### M8 — Retire `MAILERSEND_API_KEY` (later, optional)

No urgency. Consistent with this project's own S3-rollback discipline ("do not delete the old
records until S4 has been green for at least one full monthly cycle"), keep the MailerSend secret
and account dormant as a documented rollback path for some soak period before fully decommissioning.
Not scoped in this plan — a future, explicit decision.

---

## 4. Verification gates

| Gate | Assertion |
|---|---|
| **V1** | All six functions' diff matches § 1's table exactly; `grep -rn "api.mailersend.com" supabase/functions/` returns 0 post-M2 |
| **V2** | Each function's `verify_jwt` setting identical before and after deploy (dashboard read both times) |
| **V3** | Staging real sends (M4) — delivered headers show `dkim=pass d=pulllist.app`, `spf=pass` aligned, `dmarc=pass`, correct `From:` display name |
| **V4** | Full `run-smoke.ps1` green against deployed staging bytes, post-push |
| **V5** | Magic-link auth path confirmed either unaffected (Supabase-native) or explicitly migrated — not assumed either way |
| **V6** | Production real send (M7) — same header checks as V3, against `plgegklqtdjxeglvyjte` |
| **V7** | `MAILERSEND_API_KEY` and the six functions' old endpoint confirmed absent from the final deployed code (`grep` returns 0) |

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

**Last updated:** 2026-09-02 — written, same session as the discovery's GREEN result. Not started.
