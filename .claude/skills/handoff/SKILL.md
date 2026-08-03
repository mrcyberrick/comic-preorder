---
name: handoff
description: Generate a CLI execution handoff prompt in the standard PULLLIST format — after verifying the plan doc is committed. Use at the end of a planning session to hand work to a fresh execution session.
---

# /handoff — Planning → execution handoff prompt

Your planning/execution split: planning sessions write plans and handoff prompts;
a fresh CLI session executes. This skill standardizes the handoff.

## Pre-check (blocking)

The plan doc this handoff points at must be **committed and pushed to staging**.
Uncommitted planning docs are not-yet-real (CLAUDE.md § Document Integrity).
Run `git status` + `git log --oneline -3` and halt if the plan isn't in git.

## Handoff prompt structure

Produce the prompt in a single plain code block (easy copy/paste), containing:

1. **Session identity** — which sub-deploy is being executed, one sentence.
2. **Required reading, in order** — CLAUDE.md, the parent phase plan, the
   sub-deploy plan (exact repo paths). Instruct the agent to read from disk,
   never from memory of prior sessions.
3. **Scope** — explicit IN list and OUT list ("stop and ask" for anything else).
4. **Gated steps** — numbered, each with its verification query/command and the
   expected result. A failed verification is a halt-and-report.
5. **Environment facts the session needs** — branch (`staging`), target env,
   which credentials file, any Rick-in-the-loop DB steps (DB writes the user runs
   in the SQL Editor, not the agent).
6. **Completion criteria** — the plan's checkbox list, verbatim.
7. **End-of-session requirement** — run `/wrap-up` (or produce the equivalent
   status update).

## Rules

- Reference doc paths; do NOT paste whole documents into the prompt (bloated
  handoffs have blown context/output limits in past sessions).
- The handoff prompt itself is chat content, not a directive — only the committed
  plan instructs the CLI. The prompt must point at the plan, not replace it.
