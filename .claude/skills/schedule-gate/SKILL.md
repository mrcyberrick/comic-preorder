---
name: schedule-gate
description: Schedule a notification for a time-gated step (soak, quiet window, "let X elapse before Y"). Use the moment a plan opens any gate whose completion depends on real elapsed time — never leave a gate relying on human memory.
---

# /schedule-gate — Notification for a time-gated step

Every soak or quiet window gets a scheduled reminder at its earliest valid
completion time, created in the same session that opens the gate. A gate with
no reminder is drift waiting to happen (see the F86 Step 4→5 gap, 2026-07-16).

## 1. Identify the gate

- **Start timestamp** — from the plan's execution log or `git log`, the actual
  event time (toggle flip, deploy merge), never "roughly when the session ran."
- **Condition** — duration (≥24h, ≥48h) or event-based (one Wednesday shipment
  cycle, one monthly import).
- **Day-of-week / blackout constraints** — e.g. not Tue/Wed (shipment+bagging),
  not the early-month import week. Verify day-of-week with
  `(Get-Date 'YYYY-MM-DD').DayOfWeek` — never from memory.

Compute the **earliest valid completion date** from real elapsed time. A soak
"green so far" is not elapsed (CLAUDE.md § Definition of Done).

## 2. Create the notification (in preference order)

**A. One-time scheduled routine** (works without connector auth):
Load `RemoteTrigger` (`ToolSearch select:RemoteTrigger`) or invoke `/schedule`.
Create with `run_once_at` at 12:00 UTC (8:00 AM ET) on the gate date,
`model: claude-sonnet-5`, `allowed_tools: ["PushNotification", "Read", "Grep",
"Glob"]`, repo source `https://github.com/mrcyberrick/comic-preorder`.
Prompt template (must be fully self-contained — the cloud agent has zero context):

> You are a one-time scheduled reminder agent for Rick (PULLLIST). Today is
> DAY DATE. [One sentence: which gate just elapsed and why today is valid.]
> Your ONLY job is to deliver this reminder. If a push-notification tool is
> available, send a push titled '<gate name>' with the text below; regardless,
> end your session with the full reminder text as your final message.
> REMINDER — [what to check / which plan step is now unblocked, the plan doc
> path + section, and the halt-and-report rollback if applicable].
> Do not modify any files, do not commit, and take no action other than
> delivering this reminder.

**B. Google Calendar event** (if the claude.ai Google Calendar connector is
authorized — it may need re-auth): primary calendar, 8:00–8:15 AM ET on the
gate date, `popup` + `email` reminders, description = same reminder text.
Prefer creating BOTH A and B when calendar auth is available — calendar
reaches the phone, the routine reaches Claude Code.

**C. Neither available:** print the gate date prominently in `/wrap-up` output
and tell Rick to set a manual reminder — and say explicitly that no automatic
reminder exists.

## 3. Hard rules

- Reminder text NEVER contains a credential value — key prefixes and project
  refs already committed in the repo are fine, nothing else.
- The reminder agent only **reminds**. Never schedule an agent to perform the
  gated action itself — dashboard toggles, deploys, and DB changes stay
  Rick-in-the-loop per the plan's PAUSE steps.
- One reminder per gate boundary. A watch-day + action-day pair (like F86
  Jul 22 + Jul 23) counts as two boundaries.

## 4. Log it

Append to the plan doc's execution log, same session:
`Gate scheduled (DATE): <condition> elapses <gate date>; reminder: <routine id
and/or calendar event>, 8:00 AM ET.` Doc-only commit to staging.

One-shot routines auto-disable after firing (`ended_reason: run_once_fired`).
Delete stale ones at https://claude.ai/code/routines if plans change.
