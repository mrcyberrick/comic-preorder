---
name: sql-check
description: Discipline for writing ANY SQL or PostgREST query against the PULLLIST staging/prod databases — verify schema against technical-reference.md and the live DB before running, and apply known column/enum/matching conventions. Use before writing seed INSERTs, diagnostics, or verification queries.
---

# /sql-check — Write SQL against the real schema, not memory

Past sessions lost multiple iterations to guessed column names (`price` vs
`price_usd`, nonexistent `item_id`), missing required fields (`catalog_month`),
enum casing (`LUNAR` vs `Lunar`), and wrong join keys. This skill prevents that.

## Before writing any SQL

1. **Read the canonical schema** — `docs/technical-reference.md` for every table the
   query touches. Do not write column names from memory or from CLAUDE.md.
2. **If the doc's "last verified against live" date is stale or absent**, probe live
   first (staging anon-key PostgREST or a `select ... limit 0`):
   `curl.exe -s "https://puoaiyezsreowpwxzxhj.supabase.co/rest/v1/<table>?limit=0" -H "apikey: <anon>"` — or ask the user to run an `information_schema.columns` query in the SQL Editor.
3. **Dry-fit before bulk** — for multi-row seeds, run ONE row first, verify it, then
   run the rest. Never fire a multi-statement seed untested.

## Known conventions (verified against past findings)

- `catalog` uses **`price_usd`** (not `price`); **`catalog_month` is required**.
- Distributor enum is capitalized exactly: **`Lunar`**, **`PRH`** (never `LUNAR`).
- Title matching: shipment↔reservation match key is `catalog_id` OR `upc` OR
  `item_code` (F76), but **admin views match on `item_code`** — `upc` is null for
  some titles. Never match on `upc` alone.
- **Every INSERT must pass `tenant_id` explicitly** (column defaults removed
  post-Phase-3.3).
- Supabase `range()` returns **416 on empty result sets** — count first.
- SQL Editor runs as `postgres` superuser and **bypasses RLS**; `BEGIN` + `SET LOCAL`
  + `ROLLBACK` probes fail with 25P02 in the editor — use superuser row counts for
  soak probes instead.
- Cross-month duplicates exist historically (F85): when counting reservations,
  consider whether `catalog_month` scoping matters for the question being asked.

## Output rules

- Put runnable SQL in **plain code blocks** (never inside AskUserQuestion options —
  copy/paste breaks).
- For diagnostic queries, state the expected result shape BEFORE running, so a
  surprising result triggers re-verification instead of remediation.
