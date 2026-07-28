---
name: wrap-up
description: Produce the end-of-session status update required by CLAUDE.md's Anti-Drift Rules — what changed, what was verified, what's left, what was filed — plus the standard reminders. Run at the end of every working session.
---

# /wrap-up — End-of-session status update

Produce the status update CLAUDE.md § Anti-Drift Rules requires, from the actual
session record (git log/diff, commands run) — not from memory of intentions.

## Sections (all required, "none" is a valid answer)

1. **What was changed** — files + line ranges, commits made (`git log --oneline`
   since session start), SQL run against which environment.
2. **What was verified** — queries run and their results, smoke tests passed,
   gates cleared.
3. **What is left for the next session** — concrete next steps, in order.
4. **Out-of-scope discoveries** — filed (with finding IDs) vs. explicitly ignored.
5. **New finding IDs assigned** — if any.

## Standard reminders (include only the ones that apply)

- Copy any generated output files to the repo before committing.
- Push to staging and smoke test before promoting to production.
- Production database changes needed (list the exact SQL or "none").
- Local script updates needed (`import.js` / `import-staging.js` in the scripts repo).
- If a sub-deploy state changed: update the parent-plan status cell and the
  CLAUDE.md § Current Migration Phase pointer (doc-only commit to staging).

## Drift check

Before printing the update, run `git status` — flag any uncommitted planning docs
(they are "not-yet-real until they land in git" per CLAUDE.md § Document Integrity).

Also flag any time-gated step (soak, quiet window) opened or still open this
session that has **no scheduled reminder** — fix it with `/schedule-gate` before
closing, or state explicitly that the gate is unscheduled and why.
