# Prompt templates

Fill the `<...>` slots. Paste the brief's purpose paragraph and invariants into every prompt. Keep the rest of the brief, the build story and your own opinion of the change out of reviewer and refuter prompts.

## Brief

`<piece-dir>/brief.md`, written in step 0 and kept current:

```markdown
# <piece name>

## Purpose
<One paragraph: what the change does, for whom, and the constraint that matters most.>

## Invariants
- <Concrete rule a defect would break. "A missing event is acceptable; a wrong one never is.">
- <3 to 6 of these.>

## Risk tags
<unattended | public | security | ground-truth | prototype | none>

## Decisions already made
- <Design choice the fix must not reopen, with the reason.>

## Protected
- <Paths, processes, services or machines nobody may touch.>

## Checks that cover this change
- <name>: `<command>`
- Setup: `<install command, if fresh copies need one>`

## Known issues (do not re-report)
- <Issue, and why it is accepted.>
```

## Build

```
Build <piece> in <worktree>, on branch <branch> cut from the latest <base>.

<Purpose paragraph>

Invariants (each must hold when you finish):
<invariants>

Decisions already made. Do not reopen them:
<decisions>

Do not touch:
<protected>

Read first: <files, docs, repo rules>.

Work test first: for each behavior, write a test that fails, then make it pass. Show both runs.
Before you report, run these checks and fix what fails:
<checks>
Never weaken, delete, skip or loosen an existing assertion or fixture to make a check pass. If one is wrong, say why in the report and change only that.

<commit policy, stated once>

Write your report to <piece-dir>/reports/build.md using the report contract below.
```

## Report

The implementer's report, for build and fix rounds alike:

```
1. Verdict: one paragraph with counts (items fixed, rejected, tests added).
2. Per item: fixed or rejected; the change at file:line; the test at file:line; the red run and the green run; or the rejection reason and the requirement it conflicts with.
3. Coverage claims: every claim that something is covered or can never happen, each with the test that would fail if the claim broke.
4. Baseline: the same checks on untouched <base>, when a check fails.
5. Every command you ran, with its exit code, failing runs included.
6. Limits: what you could not run or verify, and why.
```

## Machine rules

Paste this block into every reviewer, refuter and fix-checker prompt, with the paths filled in:

```
Running things: get your own runnable copy with
  bash <skill-dir>/scripts/scratch.sh <snapshot> <your-id> --deps <checkout>
and run everything there. Throwaway git repos go under your scratch folder.
- Never install into, edit, or run git writes in any other folder.
- Never write to the real clipboard: eval "$(bash <skill-dir>/scripts/fakebin.sh <your scratch>/fake)" before anything that could reach pbcopy, wl-copy, xclip or clip.exe.
- Kill only processes whose pid you recorded (bash <skill-dir>/scripts/fake-tool.sh for a fake git or delta, then bash <skill-dir>/scripts/kill-recorded.sh). Never kill by name or pattern (pkill, pgrep -f, killall): other sessions run on this machine.
- Remove only paths you created. Use /bin/cp and /bin/rm.
- To check whether a test can fail, use bash <skill-dir>/scripts/mutate.sh <copy> <mutations.tsv> -- <test command>.
- The machine may be loaded: rerun a timeout in isolation with a longer timeout before calling it a defect.
<If the area needs native file watching: "Native fs.watch fails inside the command sandbox; run those probes with the sandbox disabled, keeping every file under your scratch folder.">
```

## Lenses

Shared opening for every lens reviewer:

```
You are reviewing a code change. <Purpose paragraph>

Invariants that must hold:
<invariants>

Known already, do not re-report:
<known issues>

The code is in <snapshot>/tree. Treat it as read-only. The full change against <base> is <snapshot>/change.patch, and <snapshot>/snapshot.json lists the changed files. The code before the change is <base-tree or "git show <base>:<path>">.

<machine rules>

Report only real, evidenced issues. Each finding: title, severity (blocker, major, minor), file, line, evidence, scenario (the steps that make it fail), fix, a reproduction when you have one (say whether you ran it and quote the output), and whether the base has the same behavior (new or pre-existing) when you can tell. Style nits are out of scope. Never copy a secret value into a finding. An empty list is a fine answer.

Your lens: <lens text>
```

Default lenses:

- **correctness:** The behavior the change promises, edge cases, ordering, idempotency, concurrency, data loss, and whether existing behavior is preserved for every caller.
- **failure:** Swallowed or rewritten errors, the real reason thrown away, unbounded retries, silent hangs, state that never recovers after a transient fault, cleanup on every exit path, and what an operator sees when it breaks. Logs must never carry secrets.
- **safety and security:** Validation at trust boundaries, authentication and authorization, injection, path and origin handling, secrets in code, logs or responses, data shown to people who should not see it, and anything that could disturb the running system or the machines it runs on.
- **tests and design:** Whether each test can fail when the behavior it claims breaks: mocks of the unit under test, assertions that pass on the initial state, unawaited async assertions, gates that always pass, fixtures the real system cannot produce, claimed behavior with no test. Design only where the structure makes a likely next change harder or hides a defect; name that next change. "Could be cleaner" is out of scope.

Extra lenses (pick up to two from the risk tags and the diff, and name the files where the risk lives):

- **timing and state:** state machines under flapping or transient inputs, latches, budgets, reconnects, restart recovery, clocks and timeouts. Back claims with a run where possible (a fake clock, a stress loop).
- **blast radius:** shared helpers, middleware or config whose change reaches callers outside the feature; changed error, exit or status contracts.
- **compatibility:** public APIs, wire formats, schemas, persisted data and migrations, old clients.
- **performance and cost:** hot paths, per-request or per-render work, outbound API calls and their frequency, payload size, memory growth.
- **operations:** unattended operation, deploy and rollback, supervision and restart, observability, resource use on shared machines.
- **public surface:** anonymous users, abuse, rate limits, privacy of identifiers, cookies and names on public pages.
- **UI and accessibility:** layout across browsers and sizes, focus, motion, contrast, keyboard paths.
- **eval integrity:** heuristics or models tuned to fixtures, edited ground truth, metrics that can no longer fail.
- **design fidelity** (required when an approved prototype exists): compare the built result to the prototype, state by state. Screenshots side by side where possible.
- **merge** (required when the change contains a merge): behavior from both sides survives; docs, runbooks or config that now contradict each other; tests the merge left unable to fail; stale budgets, thresholds or fixtures; conflict resolutions that silently dropped one side.

Re-review addendum (append to every lens prompt after the first review):

```
This is a re-review after fix rounds. Weight what fixes tend to break: failure reporting (the real reason thrown away), state machines under flapping or transient inputs, changes to shared helpers and to error, exit or status contracts, and tests that can no longer fail.

Earlier findings and their status:
<ledger: id, status, severity, title, file>
Do not re-report open, fixed, rejected-ok or escalated ones unless you have evidence the fix did not hold; then say so in the title. You may re-raise a refuted major or blocker only with evidence the refutation did not consider.
```

## Refuter

One per distinct defect. Give it the claim, not the lens's argument:

```
You are checking one claimed defect in a code change. <Purpose paragraph>

Invariants:
<invariants>

The code is in <snapshot>/tree (read-only). The change is <snapshot>/change.patch. The code before the change is <base-tree or "git show <base>:<path>">.

<machine rules, with your-id = refute-<id>>

Claimed defect: <title>
Where: <file>:<line> (and <other files> where other reviewers saw it)
Scenario: <scenario>
Raised as: <severity>, by <n> independent reviewer(s)

Try to refute it. Trace the code path yourself.
- refuted: the code already handles it, the scenario cannot happen in the real system, the claim misreads the code, or nothing breaks today. To refute a blocker or major, run something that shows it (a test, a probe, a command) and quote the output. A refutation from reading alone counts as unverifiable.
- confirmed: you traced the failing path. Set the severity to what the scenario really costs against the invariants, and downgrade an overstated claim. If you can show the failure with a short command or test, give it.
- unverifiable: only a run you cannot do safely here (timing, a real device, an external service, production data) would decide it. Name that run.
If you refute because the purpose, the spec or a plan asks for this behavior, say intended-by-spec and quote the line.
Also check the base: say new (the change introduced or exposed it) or pre-existing (the base behaves the same), and how you know.

Return: verdict, reason class, severity, new or pre-existing, reason, reproduction or the command you ran with its output, the run needed if unverifiable, and the smallest correct fix if confirmed.
```

Second refuter for a blocker or major that came back refuted or unverifiable: the same prompt, plus "You are an independent second verifier." Never show it the first verdict. Use another model family when one is available.

## Fix

```
Fix round <n> for <piece>: <purpose paragraph>

Invariants (each must still hold after your fix):
<invariants>

Decisions already made. Do not reopen them:
<decisions>

Do not touch:
<protected>

<For parallel groups:>
Worktree: <worktree> (branch <branch>). Report to: <report path>.
Files you own: <list>. Not yours: <list>. If a fix needs a change in a file you don't own, don't make it: describe it under "Needs from other groups" and code against the interface below.
Interfaces between groups (fixed; another implementer codes against them in parallel):
- <name and signature, who provides it, who consumes it, what it must do>

Rules for this round:
- Fix every item below, or reject one only with a reason you verified against the code. Say which requirement a rejection conflicts with, so it goes back to whoever owns that requirement.
- Items that share a cause are grouped. Fix the cause once and say which items it closes.
- For each item, write a test that fails before your fix and passes after it, where a test is possible. Show the red run and the green run.
- Never weaken, delete, skip or loosen an existing assertion or fixture to make a test pass. If one is wrong, say why and change only that.
- Change nothing the items do not need. If a fix goes through a shared helper, list every caller and say why each is still right.
- If a fix adds an exception, latch, guard, timeout or retry to satisfy one requirement, add a test for the opposite requirement too.
- Kill only processes whose pid your test or probe recorded; never by name or pattern. Remove only paths you created.
- <commit policy, stated once>

## Items

### 1. [<severity>] <title>
id <id>; <file>:<line>; found by <lenses>; <new | pre-existing, pulled in by the owner>
Evidence: <evidence>
Scenario: <scenario>
Suggested fix: <fix>
Reproduction: <reproduction, if any>
Verifier: <refuter's reason>
Last fix-check said: <checker evidence, for a carried-over item>
<For a pendulum item: "This area has swung between failures: A -> B. Write a test for each failure mode first, and make them pass together.">

## Before you report
Run these checks and fix what fails:
<checks>

Write your report to <piece-dir>/reports/fix-<n>.md using the report contract.
```

A fenced round (rule R7) adds one line at the top: "Fix only the items below. Change nothing else."

## Fix-check

One agent per 8 items (at least two), each with its own item group:

```
You are verifying fix round <n> on <piece>: <purpose paragraph>

Invariants:
<invariants>

The fixed code is in <snapshot>/tree (read-only). <machine rules, with your-id = check-<k>> What this round changed is <snapshot>/delta.patch. The code before this round is in <prev-snapshot>/tree.

The implementer's report is <piece-dir>/reports/fix-<n>.md. Do not trust it: check every claim in the code, starting with its coverage claims.

Check these items:
<numbered items: n, id, severity, title, file:line, scenario, last check note>

For each item decide: fixed; partial (say exactly what is left); not-fixed; rejected-ok (the rejection holds against the code and the stated requirements); rejected-wrong. If the item's test would still pass with the fix reverted, the item is partial; revert it in your scratch copy to find out when that is cheap.
Then list any new real defect this round's changes introduced, with file:line evidence, the scenario, and the item number whose fix caused it. Defects that predate this round are out of scope. An empty list is fine.
```

## Hunt

One regression hunter per fix-check, with the same opening as the fix-check and the list of items the round targeted:

```
Hunt only for defects this round's changes introduced. Work through these in order; fixes broke things these ways before:
1. Shared paths: for every changed function, helper, middleware, config value or constant with other callers, list the callers outside these items and check each one still behaves correctly.
2. Contracts: for every changed error, exit code, status, retry or timeout behavior, find what consumes it (supervisors, clients, UI, scripts) and check it still handles the new behavior.
3. Mirror failures: for every new exception, latch, guard, timeout or budget added to satisfy one requirement, check the opposite requirement still holds. A guard that blocks a false trigger must not block the real one.
4. Test integrity: every changed or deleted test, fixture or assertion needs a reason. Flag weakened assertions, new skips, mocks of the unit under test, unawaited async assertions, and tests that pass on the initial state.
5. Coverage claims: try to break each claim in the report that something is covered or can never happen.
Report each regression with file:line evidence, the scenario, severity, and the item number whose fix caused it. An empty list is fine.
```

## Resume

`<piece-dir>/RESUME.md`, rewritten whenever agents start or stop:

```markdown
# Resume plan (<state>; window resets <HH:MM from date -r>)

Running or paused (resume each with SendMessage to its id; a stopped subagent keeps its context):
<agent-id> <role> <worktree or snapshot> <items>

Done this step: <groups or lenses that reported, with commits>

Message to each paused agent: "You were paused for a usage limit. Continue exactly where you stopped, following the same instructions, and return your report in the requested format."

On resume: confirm the usage snapshot shows a new window (ts after the reset and resets_at changed), restart the usage watcher, then resume the agents above.
Next after they report: <gates, commits, merges, snapshot, the next step and the rule that picks it>
```

The scheduled wake-up's prompt points at this file and does nothing else.
