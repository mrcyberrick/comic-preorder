# Interim Work Instructions — Deploying PULLLIST on Cloudflare Pages

**Status:** Interim — written 2026-06-11, immediately after the Phase 5.1 hosting
migration. These instructions bridge the gap until the Cloudflare Pages setup has
matured (post-5.5, when GitHub Pages is torn down) and a permanent SOP is written.
**Canonical command sequence:** `CLAUDE.md` § Standard Deployment Workflow. If this
document and `CLAUDE.md` ever disagree, `CLAUDE.md` wins — file the contradiction as
a finding, don't improvise.
**Last verified against live: 2026-06-11** (5.1 S5/S6; soak running through 2026-06-14).

---

## 1. The core assurance

**The staging-first rule is unchanged and is now enforced by the hosting platform
itself, not just by procedure.**

Cloudflare Pages is configured with exactly one production branch: `main`. The
production site at `https://pulllist.app/` is rebuilt *only* when `main` changes.
No push to `staging`, no feature branch, no preview deployment can ever alter what
customers see. The only way code reaches production is the same way it always has:
it was deployed to staging, evaluated live, and then deliberately promoted via a
pull request into `main`.

What the migration changed is the *mechanics* of deployment, not the *policy*.

## 2. Environment model (one repo, two branches, two databases)

| | Staging | Production |
|---|---|---|
| Git branch | `staging` | `main` |
| URL | `https://staging.pulllist.pages.dev/` | `https://pulllist.app/` |
| Database | Staging Supabase (`puoaiyezsreowpwxzxhj`) | Prod Supabase (`plgegklqtdjxeglvyjte`) |
| Deploy trigger | `git push origin staging` (automatic, ~1 min) | PR merge into `main` (automatic, ~1 min) |
| Credentials | `config.js` as committed on `staging` | `config.js` as committed on `main` |

Environment isolation is carried by the per-branch `config.js`: each branch's copy
points at its own Supabase project, so the staging site can only ever read/write
staging data. This file is preserved during promotion by the
`git checkout main -- config.js` step — never skip it, never edit `config.js` in a
merge.

**Bonus:** feature branches pushed to `origin` also get their own preview URLs
(`<branch>.pulllist.pages.dev`). They carry staging credentials (branched off
`staging`), so they are safe, disposable, live previews — useful for evaluating a
change even before it merges to `staging`.

## 3. What changed vs. the GitHub Pages era

| Before 5.1 | After 5.1 |
|---|---|
| Two repos (prod + separate staging repo) | One repo, two branches — staging can no longer drift as a separate repository |
| Staging deploy: `git push staging staging:main` | **Retired.** Staging deploy is just `git push origin staging` |
| Staging URL: `mrcyberrick.github.io/comic-preorder-staging/` | `https://staging.pulllist.pages.dev/` |
| Prod URL: `mrcyberrick.us/comic-preorder/` | `https://pulllist.app/` (old URL 301-redirects via `_redirects`) |
| Deploy = GH Pages build after push (minutes, opaque) | Deploy = CF Pages build after push (~1 min, visible in CF dashboard with full history) |
| Rollback = git revert + wait for rebuild | **CF dashboard instant rollback** to any prior deployment, plus git revert, plus GH Pages warm fallback (until 5.5) |

The `staging` git remote still exists but is **not a deploy target** — it is a warm
rollback artifact until Phase 5.5 closes. Do not push to it.

## 4. Standard change flow (unchanged in substance)

1. **Branch off `staging`** → make changes → commit.
2. **Run the local Playwright smoke suite** (`run-smoke.ps1`). Stop on any failure.
3. **Merge to `staging` (`--ff-only`) and `git push origin staging`.** CF Pages
   auto-deploys the staging preview within about a minute.
4. **Evaluate live on `https://staging.pulllist.pages.dev/`** — this is the same
   "see it running before production" gate the old SOP required. Nothing has
   weakened here.
5. **Promote:** merge `staging` into `main` locally with `--no-commit --no-ff`,
   run `git checkout main -- config.js`, run the F59 diff assertion, commit, push a
   `feat/<x>-prod` branch, **open a PR to `main`**.
6. **Review the PR** — confirm `config.js` is not in the diff — **merge.**
   *Merging the PR is the production deploy.* CF Pages publishes `main` to
   `pulllist.app` automatically.
7. **Post-deploy write-smoke** on production (reserve one item as a test user,
   verify the row + `tenant_id`, cancel it).

Exact commands: `CLAUDE.md` § Standard Deployment Workflow.

## 5. Hotfix flow

Hotfixes take the **same path, compressed in time — not in gates**:

1. Branch off `staging`, fix, smoke-test locally.
2. Push to `staging`, verify the fix live on the staging URL (minutes, not hours —
   the auto-deploy makes this cheap, so there is no longer any time-pressure excuse
   to skip it).
3. PR to `main`, merge, verify on `pulllist.app`.

**If production is actively broken and the cause is a recent deploy,** there is a
faster lever than any hotfix: CF dashboard → Workers & Pages → `pulllist` →
Deployments → pick the last known-good deployment → **Rollback**. This restores the
prior build in seconds with no git surgery. Then fix forward through staging at
normal speed. Note: rollback restores *files only* — it does not undo database or
Edge Function changes, which deploy separately (§ 7).

## 6. Things that demand respect in the new setup

- **A direct push to `main` is an instant production deploy.** This was true under
  GH Pages too, but CF is faster. The rule is unchanged — never push `main`
  directly; everything goes through a PR. **Recommended hardening (Rick, GitHub
  settings):** enable branch protection on `main` requiring a pull request before
  merging. That converts the rule from procedure to mechanism.
- **The PR merge button is the deploy button.** Treat merging to `main` with the
  same weight as the old "deploy to production" step, because it is that step.
- **`config.js` discipline is unchanged and still load-bearing** — per-branch
  values, preserved at promotion via `git checkout main -- config.js`, verified
  absent from every prod PR diff.
- **Old URLs keep working** — `mrcyberrick.us/comic-preorder/*` 301-redirects to
  `pulllist.app` (query strings preserved, so emailed `?token_hash=` links survive).
  Old Edge-Function-generated email links are governed by F67 (fix lands with 5.2).

## 7. What this document does NOT cover (unchanged by 5.1)

- **Database changes** — applied directly to the Supabase projects per phase
  runbooks; never coupled to a Pages deploy. Staging database first, always.
- **Edge Functions** — deployed via Supabase, separately from the static site;
  staging project first, prod after staging verification.
- **Monthly import** — local scripts, unchanged.

A Pages deploy and rollback only ever moves static files (`*.html`, `app.js`,
`style.css`, `config.js`, `_redirects`).

## 8. Quick health checks (anyone can run)

```powershell
# Production serving from Cloudflare with prod credentials:
curl.exe -sI https://pulllist.app/            # expect 200 + CF-RAY header
curl.exe -s https://pulllist.app/config.js    # expect plgegklqtdjxeglvyjte

# Staging serving staging credentials (no crossover):
curl.exe -sI https://staging.pulllist.pages.dev/            # expect 200 + CF-RAY
curl.exe -s https://staging.pulllist.pages.dev/config.js    # expect puoaiyezsreowpwxzxhj

# Legacy-path redirect intact:
curl.exe -sI "https://pulllist.app/comic-preorder/catalog.html?x=1"
# expect 301, Location: /catalog.html?x=1
```

## 9. Maturity criteria — when to replace this with a permanent SOP

Write the permanent SOP when **all** of these hold:

- [ ] Phase 5.1 soak closed clean (S8, expected 2026-06-14)
- [ ] At least one real feature promotion has run end-to-end through the new
      workflow (a successful mid-soak or post-soak promotion counts)
- [ ] F67 resolved (Edge Function URLs point at the new domains) — until then,
      emailed links are a known-degraded surface
- [ ] Phase 5.5 closed: GitHub Pages torn down, `staging` remote removed — at that
      point §§ 3 and 5's "warm fallback" language is obsolete and the SOP should
      describe only the CF-native rollback paths
- [ ] Branch protection on `main` decided (enabled or explicitly declined)

Until then, this document plus `CLAUDE.md` § Standard Deployment Workflow are the
operating reference.
