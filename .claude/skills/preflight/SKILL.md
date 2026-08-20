---
name: preflight
description: Verify the environment is ready before any deployment or runbook session — git branch, gh CLI auth, node, scripts .env vars, Playwright suite, OneDrive script blocks. Run at the start of every execution session.
---

# /preflight — Environment readiness check

Run every check below, then print a single PASS/FAIL table. **Do not start deployment
or runbook work if any check fails** — report the failure and the fix command instead.
Never print credential values; report variable names and present/missing only.

## Checks

1. **Repo + branch**
   - `git -C "c:\Users\richa\OneDrive\Documents\(Work)\BookStop\repo\comic-preorder" status` — confirm current branch is `staging` (or the expected feature branch) and note any uncommitted files.
   - `git fetch origin` then report if local `staging` is behind `origin/staging`.

2. **gh CLI** (needed for PR workflows)
   - `gh --version` — if missing: fix is `winget install GitHub.cli`.
   - `gh auth status` — if unauthenticated: fix is `gh auth login`.

3. **Node**
   - `node --version` — needed for import scripts and `node --check` syntax gates.

4. **Scripts folder `.env`** (`C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\.env`)
   - Confirm the file exists and contains non-empty assignments for:
     `IMPORT_SERVICE_KEY`, `IMPORT_TENANT_ID`, `SUPABASE_URL`,
     `IMPORT_SERVICE_KEY_PROD`, `IMPORT_TENANT_ID_PROD`, `SUPABASE_URL_PROD`.
   - Check names only (e.g. `Select-String -Pattern '^IMPORT_SERVICE_KEY='`). **Never echo values.**
   - Confirm `SUPABASE_URL` contains `puoaiyezsreowpwxzxhj` (staging) — abort with a warning if it points at prod.

5. **Playwright smoke suite**
   - Confirm `C:\Users\richa\OneDrive\Documents\(Work)\BookStop\catalogs\scripts\playwright\run-smoke.ps1` exists.
   - OneDrive gotcha: run `Unblock-File` on `run-smoke.ps1` and `test-*.ps1` in the scripts folder (synced `.ps1` files get blocked as "downloaded from internet").

6. **Supabase reachability** (cheap, no auth)
   - `curl.exe -s -o $null -w "%{http_code}" https://puoaiyezsreowpwxzxhj.supabase.co/rest/v1/` — expect 401/200-range, not a timeout.

7. **Doc-status consistency** (added 2026-08-18, doc-status truth pass — extends F105's mechanism)
   - Every `docs/*.md` plan doc carries a first-line-after-title token:
     `**STATUS:** <STATE> | staging=... | prod=... (PR #<n>) | findings=...`, where `<STATE>` is one
     of `NOT STARTED` / `IN PROGRESS` / `COMPLETE` / `SUPERSEDED` / `STUB`. Every `docs/sql/*.sql`
     file carries `-- STATUS: staging=... | prod=...`. (Reference/template docs are exempt:
     `technical-reference.md`, `monthly-catalog-refresh.md`, `tenant-onboarding-runbook.md`,
     `phase-4.1-canary-procedure.md`.)
   - For every doc whose token state is `NOT STARTED` or `IN PROGRESS`, grep that file's body for
     `PR #<n>` references and 7-40 char hex strings that look like commit SHAs. For each one found,
     run `gh pr view <n> --json mergedAt` (a non-null `mergedAt` means it shipped) or
     `git branch -a --contains <sha>` (a hit on `main` or `origin/main` means it shipped). **If
     any hit lands on a merged PR or a SHA that is an ancestor of `origin/main`, FLAG that doc** —
     its token claims unstarted/in-progress work that git says already shipped.
   - Bash one-liner for the SHA/PR sweep once a candidate doc is identified:
     ```bash
     git branch -a --contains <sha> | grep -q 'main$' && echo "STALE: <sha> is on main"
     gh pr view <n> --json mergedAt -q '.mergedAt' # non-null/non-empty => STALE
     ```
   - **Findings cross-check (added 2026-08-18 — this is the one that catches doc-only sessions).**
     The SHA/PR sweep above keys on a doc naming a branch or PR, which **doc-only sessions never
     have**: they commit straight to `staging`, so there is no branch to be an ancestor of anything.
     That is the most common session shape in this project, and all three observed instances of this
     drift were doc-only. So also run, using data already in the token:
     > **Read the `findings=` list of every `NOT STARTED` / `IN PROGRESS` doc and check each ID's
     > status in `technical-reference.md` § 13. Then:**
     > - state is **`NOT STARTED`** and **ANY** listed finding is RESOLVED/CLOSED → **FLAG.** The
     >   plan has demonstrably progressed; it is at minimum `IN PROGRESS`.
     > - state is **`IN PROGRESS`** and **ALL** listed findings are RESOLVED/CLOSED → **FLAG.** Its
     >   declared scope is finished; it is probably `COMPLETE`.
     > - state is `IN PROGRESS` and only *some* are resolved → **no flag.** A plan legitimately
     >   spans a closed finding and an open one while it is being worked.
     ```bash
     # for one doc: extract findings= from the token, then check each in § 13
     grep -m1 '^\*\*STATUS:\*\*' docs/<doc>.md | grep -o 'F[0-9]\+'
     grep -A2 "^#### F<n> " docs/technical-reference.md | grep -icE 'RESOLVED|CLOSED'
     ```
     Worked example, and why this rule exists: `f92-policy-audit-and-f115-arrival-truth.md` declared
     `findings=F92,F115`, F92 went RESOLVED on 2026-08-18, and the doc sat at `NOT STARTED` with
     every completion box unticked while both halves were committed and pushed. The SHA/PR sweep
     could not see it. This rule would have — via the **first** clause, not the second: the state was
     `NOT STARTED` and F92 had gone RESOLVED, which is enough. F115 was still open in that same
     list, so an "all findings closed" rule would have **missed it** — that was the first draft of
     this rule, and it failed against its own worked example. Check any new rule here against the
     case that motivated it before trusting it.
     A flag still means **go look**, per the § Calibration note below — a plan spanning several
     findings may be legitimately mid-flight and just need its state moved to `IN PROGRESS`.
   - This check has a **known blind spot**: it only catches a doc claiming *less* progress than
     git shows (a stale "not started"/"in progress"). It cannot catch a doc claiming *more*
     progress than reality (a premature "COMPLETE") — that direction needs the doc's cited
     evidence (PR number, SHA) to be checked for existing, not just for having merged, which this
     same sweep already does as a side effect: a `PR #<n>` that `gh pr view` can't find at all is
     also worth flagging.
   - **Do not trust this check the first time it is added to a project.** Demonstrate it failing
     against a real stale doc before relying on it (see `docs/doc-status-truth-pass.md` § 7 for the
     first such demonstration and its recorded output).
   - **Calibration (added 2026-08-18, F92 catalog-audit session):** a plan-level `NOT STARTED` or
     `IN PROGRESS` token can legitimately contain a finished sub-item — a plan is often a numbered
     list of steps, and one step shipping does not mean the plan is done. `weekly-pipeline-consolidation-plan.md`
     is the worked example: its token correctly reads `NOT STARTED` (items 4–5, parallel run and
     cutover, are genuinely not started), while item 3 shipped to both staging *and* production on
     2026-07-09 and the doc said so five weeks later. **A flag from this check means GO LOOK at the
     cited PR/SHA and the surrounding prose — it does not mean the token itself is wrong.** Don't
     "fix" a flagged doc by changing its token to match a shipped sub-item; fix the stale sentence
     and leave the token describing the plan as a whole.

## Output

A table: check | status (PASS/FAIL) | fix (if FAIL). End with one line: either
"Preflight clean — safe to start" or "Preflight FAILED — resolve before starting".
