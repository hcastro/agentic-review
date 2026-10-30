# The ledger

`<piece-dir>/ledger.json` holds every finding the loop has seen. Write it after every review, triage and fix-check. It is the source of truth for open items, the re-review's known list, and the final report.

```json
{
  "piece": "archive-idle",
  "base": "main",
  "fixRounds": 2,
  "reviews": 1,
  "fixChecks": 2,
  "sinceReview": 2,
  "lastReviewSnapshot": "s1",
  "findings": [
    {
      "id": "F1.3",
      "origin": "review",
      "title": "Idle hold survives a restart and blocks the next session",
      "severity": "major",
      "raisedSeverity": "blocker",
      "file": "apps/archiver/src/idle.ts",
      "line": 88,
      "lenses": ["correctness", "failure"],
      "base": "new",
      "scenario": "Stream idles, archiver restarts, a new live segment arrives; the stale hold file is still present and the segment is dropped.",
      "verdict": { "result": "confirmed", "reasonClass": "real-defect", "reason": "Traced load() at idle.ts:41; the hold is never expired on boot.", "ran": "bun test idle.restart.test.ts (fails)" },
      "status": "fixed",
      "attempts": 1,
      "failed": 0,
      "group": "stale-hold",
      "history": [
        { "step": "s1", "event": "confirmed" },
        { "step": "s2", "event": "fixed", "evidence": "idle.ts:44 expires holds older than the session; idle.restart.test.ts fails on s1, passes on s2" }
      ]
    },
    {
      "id": "G2.1",
      "origin": "regression",
      "parent": "F1.3",
      "depth": 1,
      "title": "Hold expiry also drops a valid hold during a 2 s reconnect",
      "severity": "major",
      "status": "open",
      "history": [{ "step": "s2", "event": "confirmed", "evidence": "mirror of F1.3: expiry runs on reconnect, not only on boot" }]
    }
  ]
}
```

## Ids

- `F<step>.<n>`: a review finding from the snapshot `s<step>` review.
- `G<step>.<n>`: a regression found by the fix-check on `s<step>`. `parent` is the item whose fix caused it, and `depth` counts the chain (a regression of a regression is depth 2).
- `C<step>.<n>`: a gate failure introduced by the change. It closes only when its check passes.

## Statuses

| Status | Meaning | Counts as open |
|---|---|---|
| `open` | Confirmed and waiting for a fix round | yes |
| `fixed` | A fix-check ruled it fixed | no |
| `rejected-ok` | The implementer rejected it and the fix-check upheld the rejection; route the requirement to its owner | no |
| `refuted` | A refuter disproved it (for blockers and majors, with an executed check) | no |
| `unverified` | A minor nobody could check here; reported, not fixed | no |
| `escalated` | Failed its fix-check twice, or a pendulum; waiting on the owner | no, but blocks "done" |
| `deferred` | Confirmed, and the owner chose not to fix it now | no, listed in the report |
| `backlog` | Confirmed and pre-existing on the base (`"base": "pre-existing"`), or a late-round minor the owner agreed to leave; outside the fix rounds | no, listed in the report |

## Fields added for scope and pacing

- `base`: `new` when the change introduced or exposed the finding, `pre-existing` when the base behaves the same. Refuters set it; lenses may.
- `verdict.reasonClass: "executed-by-lens"`: a minor confirmed by the lens's own executed reproduction or a surviving mutation, without a separate refuter.
- `pendulum`: true on a finding whose mechanism changed in two consecutive fix rounds; its next regression fires R2.

## log.md

One line per decision, so a reader can replay the loop:

```
s1 review: 5 lenses, 14 proposals, 9 distinct, 7 confirmed (2 major), 2 refuted. -> fix round 1 (7 items)
s2 fix-check: 6/7 fixed, 1 partial, 1 major regression (G2.1, mirror of F1.3). R2 pendulum -> owner decides hold expiry vs reconnect
owner: expire holds only on boot, never on reconnect. Added to brief decisions.
s3 fix-check: 2/2 fixed, 0 regressions, gates pass. R8 -> ship, waiting for merge approval
```
