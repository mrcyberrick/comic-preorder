---
name: promote-prod
description: Promote staging → production for PULLLIST with the config.js preservation step, F59 merge-base regression check, PR flow, and post-deploy write-smoke. Only run when the user explicitly requests a production promotion and staging tests have passed.
---

# /promote-prod — Staging → production promotion

**Hard gate first:** confirm with the user that (a) they are explicitly requesting a
production promotion, and (b) staging smoke tests passed (Playwright suite + manual
check at https://staging.pulllist.pages.dev/). If either is unconfirmed, stop.

## Steps

0. **Unapplied-migration gate (F105).** Run this BEFORE the merge. It prints every
   `docs/sql/` file whose production state is not `APPLIED` or `N/A`:

   ```powershell
   Select-String -Path docs\sql\*.sql -Pattern '^-- STATUS:' |
     Where-Object { $_.Line -notmatch 'prod=(APPLIED|N/A)' } |
     ForEach-Object { "{0}`n    {1}" -f $_.Filename, $_.Line.Trim() }
   ```

   **Every file it lists is a decision, not automatically a blocker.** For each,
   establish one of:
   - it must run on production **before** this PR merges (schema the new client
     depends on — this is the common case, and running it after means a window
     where the client calls something that does not exist);
   - it is **deliberately** staging-only for now — then say so out loud to the
     user and get agreement, rather than letting silence be the answer;
   - it is `UNVERIFIED` — then verify it before promoting anything, because an
     unknown applied state on production is exactly the condition F105 describes.

   **Update the `-- STATUS:` line the moment a file is run.** The line is only
   worth having if it is true; a stale one is worse than none, because it will
   be believed.

   **0b. Does the client already reference it? (added 2026-08-18)** Do not decide
   the above by reading. For each unapplied migration, pull the identifiers it
   adds and grep the app files this PR would promote:

   ```powershell
   # identifiers added by the pending migration (columns, functions, tables)
   Select-String -Path docs\sql\<pending>.sql -Pattern 'ADD COLUMN\s+(\w+)|CREATE (?:OR REPLACE )?FUNCTION\s+(\w+)|CREATE TABLE\s+(\w+)' -AllMatches |
     ForEach-Object { $_.Matches.Groups | Where-Object { $_.Success -and $_.Name -ne '0' } | ForEach-Object { $_.Value } } |
     Sort-Object -Unique
   # then, for each identifier:
   Select-String -Path *.html, app.js -Pattern '<identifier>' -List
   ```

   **Any hit is a HARD BLOCKER, not a decision.** The client would call something
   production does not have. A PostgREST select naming a missing column returns
   **400 / `42703`**, which fails the whole request — so this is not graceful
   degradation of one panel, it is that page's entire data load.

   *Worked example, and why this was added:* on 2026-08-18 the F115 build put
   `arrival_outcome` into `admin.html`'s `fetchAllPreorders()` select list
   (`admin.html:1106`) with `f115-arrival-outcome.sql` at `prod=NOT APPLIED`.
   Promoting in that window would have taken the **entire production admin
   dashboard** offline — not the backorder panel, the whole gather. The session
   knew and said "do not promote" in its closeout, which is prose in a document
   nobody re-reads at promotion time. That is the F105 shape exactly, so it gets
   a check rather than a sentence.

   *Why this step exists:* `f6-app-settings-pk-rekey.sql` required a production
   re-key **before tenant 2**. Staging ran 2026-07-08, tenant 2 went live
   2026-07-15, production did not run until 2026-07-28 — a 13-day exposure found
   by an unrelated audit, not by any alarm. The gate was invisible because it
   lived in prose inside a SQL file rather than anywhere a promotion would look.
   With this step, that file would have printed `prod=PENDING` on every promotion
   in the window (PRs #86, #89, #90, #91) instead of passing silently four times.

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

2b. **Tree-integrity assertions (F125) — run BEFORE pushing any promotion branch.**

   **Create the branch from an explicit ref, never from ambient HEAD:**
   ```powershell
   git checkout -B feat/<description>-prod origin/main
   ```
   `git checkout -b <name>` takes whatever HEAD happens to be. On 2026-08-24 a
   second person committed in this same working tree mid-promotion, HEAD had
   moved to `staging`, and the branch silently inherited staging's tree. That PR
   would have **deleted both prod-only `supabase/migrations/` files and
   overwritten `config.js` with the staging anon key**, pointing production at
   the staging Supabase project. Assume HEAD can move under you.

   **Then assert the BRANCH TREE, not the working tree:**
   ```powershell
   $b = git rev-parse --abbrev-ref HEAD
   git fetch origin
   git diff --stat origin/main $b                                    # scope = intent, nothing more
   @(git ls-tree -r --name-only $b -- supabase/migrations/).Count    # expect 2
   git show "${b}:config.js" | Select-String plgegklqtdjxeglvyjte    # expect a match
   ```

   **Do not substitute per-file spot checks.** On 2026-08-24 `ls
   supabase/migrations/`, a `grep` of `config.js` and `git status` all PASSED on
   the bad branch — they read a working tree that was correct at that instant,
   on a branch that was not. Only `git diff --stat origin/main <branch>`, the
   whole diff against the *remote* base, exposed it.

   `.claude/hooks/guard-git.ps1` **Guard 3** now enforces the last two
   mechanically on any push of a `*-prod` branch. It was tested against the real
   failure: blocks a `*-prod` branch cut from staging (missing migrations) and
   one carrying staging's `config.js`; allows a branch cut from main, a staging
   push, a non-prod branch, and prose that merely names a prod push. Treat it as
   a backstop, not a substitute for reading the diff.

3. **Commit and open PR**
   ```powershell
   git commit -m "<type>: <description>"
   git checkout -B feat/<description>-prod origin/main   # explicit ref — see 2b
   git push origin feat/<description>-prod
   ```
   Open PR `feat/<description>-prod → main` with `gh pr create` (run `gh auth status`
   first — a missing gh auth has derailed sessions before).

4. **Verify PR diff** — confirm `config.js` is NOT in the PR diff before the user
   merges, and re-check the file list **on GitHub** (`gh pr diff <n> --name-only`)
   rather than trusting the local diff: what is local and what was pushed can
   disagree, which is exactly how the 2026-08-24 near-miss reached an open PR.
   The list must match your intended scope exactly. Report the PR URL and stop;
   the user merges.

5. **Post-merge verification** — after the user confirms merge + CF Pages deploy:
   - Post-deploy write-smoke: reserve one item through the live app as a test user,
     confirm the row lands in prod `preorders` with correct `tenant_id`, then cancel it.
   - Remind: if a hard-refresh shows stale behavior, remember F79 (asset cache skew) —
     `app.js`/`config.js` are `no-cache` via `_headers`, but verify the deploy hash.

6. **Close out** — update any plan-status cells and CLAUDE.md pointers that this
   promotion completes, as separate doc-only commits to staging.
