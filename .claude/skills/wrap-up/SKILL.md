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

## Project board (do this whenever a task's state changed)

Rick tracks work on the PULLLIST project board:
**https://claude.ai/artifact/Bcgf3TjSVg6Fa1qDq7ZSt9**. If this session finished,
started, reopened or re-scoped anything the board tracks, update its card before
closing. Add a card only if Rick asks. Change only what this session's evidence
supports (commits, served bytes, Rick's report); never mark a card Done on intent.

How (it is a dashboard Artifact; the cards are one attached JSON file, not page text):
1. `Artifact` `read` the URL, then `ArtifactData` `get` collection `datasets`, doc
   `tasks` and note its `version` and `source.url` (`/_blob/<id>`).
2. `Artifact` `read` with `path` = that blob id to download the rows (`{rows: [...]}`;
   fields `id, task, status` (`Todo`/`Doing`/`Done`), `area, phase, note, kind, gate,
   unblocks, order`).
3. Edit the affected rows in a scratchpad copy (dated, one-line `note`).
4. `Artifact` publish with `url`, `asset: true`, `file_path` = the edited JSON.
5. `ArtifactData` `update` `datasets/tasks` with `if_version` = the version from step 1:
   `source: {kind: "file", name: "pulllist-tasks.json", url: <new blob url>}` and
   `updated: {at: <ISO time>, by: "Claude for Rick"}`. Don't edit the page itself.

In the status update, name which cards moved, and list any cards you saw were stale but
did not touch. If nothing the board tracks changed, write "Board: no change".

## Drift check

Before printing the update, run `git status` — flag any uncommitted planning docs
(they are "not-yet-real until they land in git" per CLAUDE.md § Document Integrity).

Also flag any time-gated step (soak, quiet window) opened or still open this
session that has **no scheduled reminder** — fix it with `/schedule-gate` before
closing, or state explicitly that the gate is unscheduled and why.
