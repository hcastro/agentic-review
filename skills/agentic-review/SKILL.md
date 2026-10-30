---
name: agentic-review
description: Takes a change that you or an implementer agent built and runs it through review until it is ready to merge. A full review by fresh subagents through several lenses, a refuter that attacks each finding, fix rounds by the implementer, a fix-check after every round that rules on each finding and hunts for regressions the fix introduced, and a full re-review when the code drifts. Fixed rules pick each next step, the loop's state lives in files on disk, and nothing merges, pushes or deploys without approval. Use when the user asks to review a change or branch they own until it is clean, to run the review loop, to review, fix and re-check, for multi-round or adversarial review of their own work, or when Codex or another implementer finishes a piece that needs review before merge. Not for reviewing someone else's pull request, and not for review without fixes.
---

# Agentic review loop

One agent builds a small change. This session orchestrates: it runs the checks itself, freezes a snapshot, and sends fresh subagents to review it through several lenses. Every finding goes to its own refuter before anyone acts on it. The implementer fixes every finding that survives, or rejects one with a reason. A cheap fix-check then rules on each finding and hunts for regressions the fix itself introduced. That repeats until a fix-check comes back clean, and a full re-review replaces the fix-check whenever the code drifts far from what was last reviewed.

The loop exists because fixing is where new defects come from. In the case study behind this skill, 95% of targeted findings were fixed, and 83% of fix rounds still introduced at least one new defect. The evidence for every rule here is in [references/evidence.md](references/evidence.md).

**Requirements:** `git`, an agent that can launch subagents (Claude Code's Agent tool), and an implementer: Codex CLI, a subagent working in its own git worktree, or a person. The repo's own checks (tests, typecheck, build) must be runnable from this session.

**The user's own rules win.** When the user's instructions (CLAUDE.md, memory, the request) set a worktree location, a usage-limit policy, a writing style, approval rules for outward steps, or a naming policy, follow them. The defaults below apply only where the user has none.

## Roles

| Role | Who | Does | Never does |
|---|---|---|---|
| Owner | the user | Sets the goal, the invariants and the risk rules. Settles design trade-offs. Approves merges, pushes and deploys. | Write fix prompts |
| Orchestrator | this session | Writes every prompt, runs the gates, takes snapshots, launches reviewers and checkers, triages, decides the next step, keeps the ledger | Edit product code |
| Implementer | Codex, a subagent in its own worktree, or a person | Builds the piece and every fix round with red/green tests. Reports every command with its exit code. | Commit (unless the commit policy says so), weaken an assertion, see the reviewers' reasoning beyond the fix prompt |
| Lens reviewer | one fresh subagent per lens | Reads the snapshot through one lens and reports evidenced defects | See other lenses' output |
| Refuter | one fresh subagent per distinct finding that needs one (see step 4) | Tries to disprove one finding from the code, and says whether the base branch has it too | See other findings or which lens raised it |
| Fix-checker | one fresh subagent per 8 items, at least two | Rules on each finding and hunts regressions in the fix | Trust the fix report |

## Independence rules

These apply to every reviewer, refuter and fix-checker. They are what make several passes worth more than one.

1. **Fresh subagents only.** Launch each with the Agent tool as a new general-purpose agent. Never use `fork`, which inherits this session's whole conversation, and never continue an earlier reviewer for a new round. A refuter that wrote the findings defends them.
2. **No build story in the brief.** A reviewer gets the snapshot paths, the one-paragraph purpose, the invariants and the known-issues list. Leave out how the change was built, what you think of it, and the PR description or commit messages. Framing a change as safe cut vulnerability detection by 16 to 93 points in one study.
3. **The implementer's report goes to the fix-check only.** Lens reviewers and refuters never see it. Fix-checkers get it with "do not trust it" and attack its coverage claims first.
4. **Reviewers read a frozen snapshot**, never the live checkout. Make one with `scripts/snapshot.sh` before every review and every fix-check.
5. **Read-only on code and machine.** Reviewers and checkers run probes only in their own copy from `scripts/scratch.sh`. No installs into shared folders, no edits, no git writes. They kill only processes whose pid they recorded (`scripts/fake-tool.sh` and `scripts/kill-recorded.sh`), never by name or pattern, and remove only paths they created. Probes that could reach a clipboard tool run behind `scripts/fakebin.sh`. These rules go in every reviewer, refuter and checker prompt word for word: other sessions share the machine.
6. **Vary the reviewer.** When a second model family is available (Codex CLI, for example), use it for the second refutation of a high-severity claim. Models favor output that resembles their own.

Several pieces at once: run their loops in parallel only when they touch different files, and never run two full reviews at the same time.

## The loop

```
frame -> build -> gates -> snapshot -> FULL REVIEW -> refute -> triage
                                            ^                     |
                         drift: re-review   |                     v
                                            +---- decide <- FIX-CHECK <- snapshot <- fix round
                                                    |
                        clean -> gates -> owner approves -> merge, deploy, log
```

### 0. Frame the piece (owner and orchestrator)

Write `brief.md` in the piece folder: one paragraph on what the change does, three to six invariants, the risk tags, protected resources, settled design decisions, and the checks that cover the change. Use the template in [references/prompts.md](references/prompts.md#brief).

- **Concrete invariants.** "A missing race event is acceptable; a wrong one never is." Abstract invariants cost more regressions per item than concrete ones.
- **Risk tags:** `unattended`, `public`, `security`, `ground-truth`, `prototype` (an approved design exists), `none`. They choose extra lenses and decide when a minor-only result still needs another check.
- **Size it.** One paragraph should describe it. Findings per review stay between about 7 and 19 whatever the size, so a large change gets sampled. Above about 1,500 changed lines, split the piece, or split the review by area with a lens set per area.
- **Mechanical guards** for any invariant that matters, such as a test or a preload that fails when a test touches a live directory. A sentence in a prompt doesn't stop an implementer's test run.

Confirm the brief with the user before the first build or review.

### 1. Build (implementer)

The implementer works on its own branch from the latest base, in a worktree at the user's worktree location. It uses red/green tests and writes a report that follows the contract in [references/prompts.md](references/prompts.md#report): per item, every command with its exit code, and a coverage-claims list. Give it the checks it will be judged by, so it can run them itself.

When the change already exists (the user built it, or it came from elsewhere), skip to step 2.

### 2. Gates (orchestrator)

Run the checks that cover the change yourself. Never take the implementer's green on trust. On a failure:

- Decide first whether the product or the check is wrong.
- Rerun the failing check on the base, on the same machine.
- Classify the result: introduced, pre-existing or environment. Only an introduced failure goes to the implementer, as a gate item.

### 3. Snapshot (orchestrator)

```bash
bash scripts/snapshot.sh <checkout> <base-ref> <piece-dir>/s<step> [--prev <piece-dir>/s<prev-step>]
```

This writes a frozen `tree/`, `change.patch` against the merge base (untracked files included), `delta.patch` since the previous snapshot, and `snapshot.json` with the commit, the file counts and whether a merge is involved. It never touches the checkout's index or working tree. Copying costs no model usage, so near a usage limit take the snapshot now and run the review after the reset.

Each agent gets its runnable copy from `scripts/scratch.sh <snapshot> <agent-id> --deps <checkout>`: the tree plus the checkout's `node_modules`, cloned on APFS and reflink file systems, so a dozen agents don't each copy the dependency folder. Put the exact command in the agent's prompt. The same `scripts/` folder holds `mutate.sh` (break production lines one at a time and report caught or survived), `fakebin.sh` (fake clipboard tools) and `fake-tool.sh` with `kill-recorded.sh` (a fake git or delta that records its pids, and a kill that touches only those). Point agents at them so they don't write their own.

### 4. Full review (lens reviewers, then refuters)

Launch one subagent per lens in a single message, so they run in parallel. Use the lens prompts in [references/prompts.md](references/prompts.md#lenses).

- **Default lenses:** correctness, failure handling, safety and security, tests and design.
- **Extra lenses**, up to two, picked from the risk tags and the diff: timing and state, blast radius, compatibility, performance and cost, operations, public surface, UI and accessibility, eval integrity, and design fidelity whenever an approved prototype exists.
- **Every review adds a merge lens** when the change contains a merge.
- **Re-reviews add the late-round focus** and the ledger of earlier findings.

As each lens returns:
1. Merge duplicates across lenses into distinct defects, and record which lenses found each. Agreement between lenses predicts severity: multi-lens defects were major or worse 68% of the time, single-lens ones 25%.
2. Send each distinct defect that needs it to its own refuter with the refuter prompt. The refuter gets the claim (title, file:line, scenario) and traces the code itself, without the lens's argument.
   - **Needs a refuter:** every blocker and major, every finding raised from reading alone, and anything lenses disagree on.
   - **Confirmed by its evidence, no refuter:** a minor raised by two or more lenses with executed probes, or a minor whose lens quotes an executed reproduction or a mutation that survives. Record `reasonClass: "executed-by-lens"`.
   - Refuters for minors can run on a cheaper model.
3. Every refuter also checks the base branch and labels the finding **new** (the change introduced or exposed it) or **pre-existing** (the base behaves the same). Lens reviewers label it when they can tell.

Verdicts and their rules:
- **confirmed:** the refuter traced the failing path. It also corrects the severity, since reviewers inflate.
- **refuted:** a refutation of a blocker or major must cite an executed probe or test. A refutation from reading alone is `unverified`. In the data, read-only refuters refuted 26% of what they saw, and refuters that ran code refuted 7%.
- **unverifiable:** only a run that can't be done safely here would decide it. A major or blocker stays open as "write the failing test first". A minor is reported and left unfixed.
- **Second refuter:** a blocker or major that comes back refuted or unverifiable goes to a second, independent refuter, from another model family when available. It survives if either one confirms it.
- **Spec-based refutations:** tag them `intended-by-spec` and quote the line. Revisit them when the spec changes.

Record every finding in the ledger (see below).

### 5. Triage (orchestrator)

This is the judgment step. Do it in minutes, from the ledger:

- Group defects that share a root cause, and name the cause.
- Settle every design choice a fix would otherwise guess at, and write it into `brief.md` as a decision. Rounds with settled choices had about 0.14 regressions per item. A round that sent an undiagnosed "it feels off" item had 0.63.
- Regrade severity against the invariants, regressions included. A realistic scenario that breaks an invariant is a major. A rare input that breaks one (an unusual config, file system, file name or environment) stays minor, and the ledger says why.
- **Pre-existing findings go to the backlog** (status `backlog`) unless they break the change's own promise or the owner pulls them in. The fix round carries only new findings, regressions and gate items. Show the backlog to the owner at each report.
- Fold in owner reports and live incidents, so they ship with the round.
- Overrule a refutation only with evidence, and say so in the ledger. An executed reproduction overrules a read-only refutation.
- **Two requirements that pull against each other** (a pendulum risk) go to the owner as a stated trade-off before the implementer sees them. Flag a mechanism that changed in two consecutive fix rounds as a pendulum candidate in the ledger, so its next regression fires R2 at once.

### 6. Fix round (implementer)

Write the fix prompt from the template in [references/prompts.md](references/prompts.md#fix). Its contract:

- Fix every confirmed item in the round, minors included, or reject one with a reason verified against the code, naming the requirement it conflicts with. Backlog items are not in the round.
- Fix a shared cause once, and say which items it closes.
- Write a test per item that fails before the fix and passes after it.
- Never weaken, delete, skip or loosen an assertion or fixture to pass.
- List every caller of a changed shared helper. Test the opposite requirement of any new guard, latch, timeout or retry.
- State the commit policy in one place, and only once.

Hand it to the implementer: run Codex with the prompt, launch a fresh subagent in the piece's worktree, or give it to the user.

**Several implementers in parallel** (one per area, each in its own worktree): give each group an explicit list of the files it owns and the files it must not touch. When one group's fix needs something from another group's files, write that interface into both prompts as a fixed name and signature before either starts, and have the consumer keep a fallback so its worktree compiles before the merge. A request for an interface that arrives mid-round goes to the owning group, never to the requester. Merge the branches one at a time and run the gates after each merge.

### 7. Snapshot the fix

Run `scripts/snapshot.sh` again with `--prev` pointing at the previous snapshot. The fix-check reads `delta.patch` and the pre-fix tree.

### 8. Fix-check (fix-checkers and a regression hunter)

Launch these in one message:

- **Fix-checkers:** one per 8 items, at least two, split by item number. Each item gets a verdict: `fixed`, `partial` (say what's left), `not-fixed`, `rejected-ok` or `rejected-wrong`. If an item's test still passes with the fix reverted in a throwaway copy, the item is `partial`.
- **One regression hunter:** works through the five-point checklist in [references/prompts.md](references/prompts.md#hunt). It covers shared paths, changed contracts, mirror failures, test integrity, and the report's coverage claims.
- **The gates:** run them yourself in parallel with the agents. A gate item closes when its check passes, whatever a checker says about it.

Merge duplicate regressions, send each that needs one to a refuter under the same rule as review findings (step 4), and regrade the survivors against the invariants. Record the depth of each one, so a regression of a regression is visible.

### 9. Decide

Apply the decision rules below, top to bottom. The first rule that matches picks the next step. Write the rule and the numbers behind it into the ledger.

### 10. Ship

Ship only when the definition of done holds. Run the gates yourself on the final tree, then ask the owner before any merge, push or deploy. Their approval covers only the step they approved. Write a status entry wherever the user keeps them (knowledge base, PR description, ticket).

## Decision rules

| # | Signal | Next step |
|---|---|---|
| R1 | The owner reports a problem, or a live incident happens, while a round is open | Fold it into the round. Restart the round if it started under about 10 minutes ago. |
| R2 | A regression mirrors the finding just fixed, or the same mechanism regressed in two fix-checks in a row (a pendulum) | Stop patching. Write both failure modes as tests, state the trade-off, and have the owner decide. Then one fix round. |
| R3 | The same finding failed its fix-check twice | Escalate it to the owner with both fix-check verdicts |
| R4 | Drift: a merge with the base, 3+ fix rounds since the last full review, merged without a review, or an unattended or public install next | Full re-review in place of the next fix-check |
| R4a | A fix round added a new mechanism (a new process, watcher, protocol or concurrency model) in one area | Area re-review: full lenses on that area, plus normal fix-checkers for every other group's items. A full re-review only if the mechanism crosses areas. |
| R5 | This is the 4th fix-check on the piece and it still found a major | Stop the patch loop. Full re-review, or re-plan the requirement with the owner. |
| R6 | Any blocker or major open, partial, not-fixed or rejected-wrong; a major regression; or a gate item still failing. Before the third fix-check, minor items count here too. | Fix round with the checker's evidence pasted in, then a fix-check |
| R7 | Minor regressions only, or (from the third fix-check on) only minor items left | One fenced fix round ("change nothing else"), then gates. Add a fix-check when the piece is tagged unattended, public, security or ground-truth. Minors still open after it go to the backlog with the owner's consent. |
| R8 | Fix-check clean: no open items, no regressions, gates pass | Ship (step 10) |
| R9 | The implementer rejected an item | The fix-check judges it. A rejection that upholds a stated invariant stands. Route the requirement to whoever owns it. Never send a narrower version of a rejected requirement back. |
| R10 | Two rounds would edit the same files | Queue the second |
| R11 | Usage is at the user's reserve threshold (default: no new full review past 70% of the window) | Take the snapshot now and schedule the review after the window resets |
| R12 | Six fix rounds without a clean fix-check | Stop and report to the owner. This is a safety cap. Round count never counts as done. |

What to expect: plan for two to three fix-checks per piece. The first fix-check found a regression 10 times in 11, and majors were gone by the third.

## Severity

Set severity against the owner's invariants, not in the abstract.

- **blocker:** the piece's core promise breaks on a normal path, or shipping causes damage that can't be undone. Fix first, and give a refutation a second refuter.
- **major:** a realistic scenario breaks an invariant. That covers wrong output, lost data, a privacy or security leak, a hang, an unattended service that can't recover, or a test that can't fail for a claim that matters. A major regression always gets another fix-check.
- **minor:** a real defect with limited reach. That covers an error reason thrown away, a log flood, docs drift, a vacuous test for a low-stakes claim, an edge case with a workaround, or an invariant broken only by a rare input. Fix it in the same round while the loop is young; late rounds fence or backlog it (R7). On unattended code, look twice at error-reporting minors: one preceded the case study's live incident.

Severity is about this change. A pre-existing defect keeps its severity for the backlog but doesn't start a fix round unless it breaks the change's own promise.

## Done

A piece is done when all of these hold:

1. Every confirmed finding from the last full review is `fixed`, or `rejected-ok` with its requirement routed to the owner.
2. The last fix-check was clean, or listed only minors that were fixed in one fenced round (with its own fix-check for risky tags).
3. No re-review trigger (R4 or R4a) is pending.
4. You ran the gates yourself on the final tree and saw them pass.
5. The risk tags' evidence is in hand. That means a real device for device features, side-by-side frames against the prototype for visual work, and scores holding on every answer key for measured work.
6. The ledger lists anything left open on purpose (backlog and deferred items), and the owner has seen it.

## The ledger

The loop's state lives in files, never only in this conversation. That lets a multi-day loop survive context compaction. The folder is `<workdir>/<piece>/` (default `$TMPDIR/agentic-review/<piece>/`, or wherever the user keeps review evidence):

- `brief.md`: purpose, invariants, risk tags, decisions, protected resources, checks.
- `ledger.json`: every finding. Each has an id (`F` review, `G` regression, `C` gate), severity as raised and as verified, lenses, verdicts with reasons, status, attempts, the parent of a regression, and a history line per check.
- `s<n>/`: one folder per snapshot.
- `prompts/` and `reports/`: every prompt sent and every report received.
- `log.md`: one line per decision, naming the rule that fired.
- `RESUME.md`: what is running right now and how to resume it after a pause (the template is in [references/prompts.md](references/prompts.md#resume)). Rewrite it whenever agents start or stop.
- `agents-<step>.txt`: the agent id and job of every agent launched for a step, so a paused agent can be resumed by id.

After compaction or a new session, read `brief.md`, `ledger.json`, `RESUME.md` and the end of `log.md` before doing anything else. The schema is in [references/ledger.md](references/ledger.md).

## Cost and pacing

Cost in the case study, counted as subagent tokens:

| Step | Agents | Tokens | Time |
|---|---|---|---|
| Full review | 15 to 26 | about 1.7M | about 9 min |
| Fix-check | 2 to 3 | about 0.27M | about 6 min |

A second data point, a whole-repo sweep run with Claude subagents as implementers (see [references/evidence.md](references/evidence.md#whole-repo-sweep)):

| Step | Agents | Share of a 5-hour window |
|---|---|---|
| Full re-review with fix-checkers | 16 to 18 | about 40% |
| Refuters, cheaper model | 13 to 37 | 5 to 10% |
| Fix round, 4 implementers in parallel | 4 to 5 | 15 to 20% |

- A full review costs about six fix-checks. That's why the full review runs at the start and after drift, and the fix-check runs every round in between. R4a keeps a one-area change from buying a full review.
- Run full reviews one at a time. Two at once took a usage window from 50% to 85% in 20 minutes.
- **Cap concurrency at about 8 agents.** Tests, git and probes from 16 to 20 agents drove the load average to 20 to 46, and over 100 test runs timed out for load alone. Agents then spend their time classifying flakes.
- **Gates under load:** run with a generous per-test timeout, and treat a timeout as a failure only after it repeats in an isolated rerun.
- **Start big phases near the top of a usage window.** A fix round paused halfway costs a resume and leaves worktrees mid-edit. Near the user's threshold, take the snapshot and write the next phase's prompts, and launch after the reset.
- **Pausing:** stop agents with TaskStop, write `RESUME.md`, and schedule one wake-up for just after the reset that checks the window really reset, restarts the watcher and resumes each agent by id with SendMessage. A stopped subagent keeps its context.
- Before the first review, start the user's usage watcher if they have one. Re-arm it when it expires, and stop it when the loop ends.
- Codex fix rounds don't count against this session's budget.

## Report to the user

At each stop, and whenever the owner must decide something:

- **Status:** a verdict line and the rule that fired.
- **Open items** by severity, each with what was executed and the path to its evidence.
- **Decisions needed:** escalations, pendulums, upheld rejections, spec-based refutations, unverified minors.
- **Totals:** rounds, reviews and fix-checks so far, with tokens and minutes.
- **Repo rule suggestions:** traps that cost time and that the repo's context files don't cover, given as file and exact text. Don't edit the repo's files for them unless asked.

Use the user's writing style. Keep refuted findings to one line each.

## Gotchas

- **Agents report back when they finish.** Don't poll or re-launch a reviewer that's still running. Use the wait to prepare the next snapshot or the gate run.
- **Review agents with side effects:** a checker's package install once changed a local clone. In the whole-repo sweep, a refuter found its hung fake process with `pgrep -f 'sleep 300'`, matched another Claude session's watcher loop, and killed that session; an implementer's `rm -rf probe` in the shared temp dir deleted another run's files. Repeat the read-only, kill and remove rules in every prompt, and give each agent its own scratch folder.
- **Shell aliases leak into agents.** On machines where `cp` and `rm` are aliased to verbose or interactive versions, tell agents to call `/bin/cp` and `/bin/rm`. The scripts already do.
- **The sandbox blocks native file watching and `ps`.** Watcher probes need native fs events, so they run outside the command sandbox; say so in the prompt. Scripts that need `ps` degrade instead of failing.
- **Wall-clock jumps.** A machine that slept makes agent durations and log times look wrong. Check `date` against the usage snapshot's `ts` before drawing conclusions.
- **A false baseline:** before calling a failure pre-existing, check that the base run had nothing stashed or patched.
- **Never push your own premise into a prompt** ("zero wins is very unlikely"). State the measured fact, or leave it out.
- **The snapshot is not the deployment.** OS permissions, network rules and real devices are invisible to a tree read. For unattended services, add a deployed smoke test as its own gate.
- **Merge rounds stay separate.** Preview a merge in a throwaway worktree to count conflicts, then make the merge its own round with a merge-lens review. Don't bundle it with fixes.
- **Measured work runs its own loop.** When the goal is a number (recall, latency), score each round against labelled ground truth. Check the labels before blaming the code, and retire a blind set once it's been seen. Run a full code review on the result when the targets hold.
