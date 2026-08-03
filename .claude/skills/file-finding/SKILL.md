---
name: file-finding
description: File a new finding (F-number) the correct way — claim the next free ID, write the entry in technical-reference.md § 13, update the CLAUDE.md findings line and next-free pointer, and commit doc-only to staging. Use whenever an out-of-scope bug or discovery needs to be filed rather than fixed inline.
---

# /file-finding — File a finding without ID collisions or drift

## Steps

1. **Determine the next free ID from the files, not memory:**
   - Read CLAUDE.md § Current Migration Phase → "Next free finding ID".
   - Cross-check by grepping `docs/technical-reference.md` § 13 for the highest
     existing `F\d+`. If they disagree, the higher number + 1 wins — and report the
     contradiction as part of the filing.

2. **Write the finding entry** in `docs/technical-reference.md` § 13 using the
   established format of neighboring entries: symptom, root cause (or "unknown"),
   scope (staging/prod/both), status (open / deferred-to-X / resolved DATE),
   and any related finding IDs.

3. **Update CLAUDE.md**:
   - Add the one-line summary to § Open findings.
   - Advance "Next free finding ID" to N+1.

4. **Commit doc-only to staging** (never bundled into a feature branch):
   ```powershell
   git add docs/technical-reference.md CLAUDE.md
   git commit -m "docs: file F<N> - <one-line summary>"
   ```

5. **Report** the assigned ID and where it was filed. If the finding is
   security-sensitive, do NOT put details in the repo — follow the F75 pattern
   (reserve the ID, keep details in the local-only `security-findings-local.md`).

## Rules

- Never reuse or guess an ID.
- Filing a finding is not fixing it — do not start the fix unless the user says so.
