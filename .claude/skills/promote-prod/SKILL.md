---
name: promote-prod
description: Promote staging → production for PULLLIST with the config.js preservation step, F59 merge-base regression check, PR flow, and post-deploy write-smoke. Only run when the user explicitly requests a production promotion and staging tests have passed.
---

# /promote-prod — Staging → production promotion

**Hard gate first:** confirm with the user that (a) they are explicitly requesting a
production promotion, and (b) staging smoke tests passed (Playwright suite + manual
check at https://staging.pulllist.pages.dev/). If either is unconfirmed, stop.

## Steps

1. **Merge with prod-credential preservation**
   ```powershell
   git checkout main
   git pull origin main
   git merge staging --no-commit --no-ff
   git checkout main -- config.js
   ```
   `config.js` is tracked per-branch; the checkout step preserves prod values.
   If the feature added a NEW key to `config.js`, stop — the user must add it
   manually to both branches first (checkout does not propagate new keys).

2. **F59 merge-base regression check** — assert critical app files actually changed:
   ```powershell
   foreach ($f in @('app.js', 'mylist.html', 'arrivals.html', 'admin.html')) {
       $diff = git diff "main:$f" "staging:$f" 2>$null
       if ($diff) { Write-Host "ok: $f differs from main (will update)" }
       else { Write-Host "WARN: $f identical to main - verify expected, NOT a merge-base regression" }
   }
   ```
   Any unexpected WARN → halt and investigate before committing.

3. **Commit and open PR**
   ```powershell
   git commit -m "<type>: <description>"
   git checkout -b feat/<description>-prod
   git push origin feat/<description>-prod
   ```
   Open PR `feat/<description>-prod → main` with `gh pr create` (run `gh auth status`
   first — a missing gh auth has derailed sessions before).

4. **Verify PR diff** — confirm `config.js` is NOT in the PR diff before the user
   merges. Report the PR URL and stop; the user merges.

5. **Post-merge verification** — after the user confirms merge + CF Pages deploy:
   - Post-deploy write-smoke: reserve one item through the live app as a test user,
     confirm the row lands in prod `preorders` with correct `tenant_id`, then cancel it.
   - Remind: if a hard-refresh shows stale behavior, remember F79 (asset cache skew) —
     `app.js`/`config.js` are `no-cache` via `_headers`, but verify the deploy hash.

6. **Close out** — update any plan-status cells and CLAUDE.md pointers that this
   promotion completes, as separate doc-only commits to staging.
