---
name: agentic-review
description: Takes a change that you or an implementer agent built and runs it through review until it is ready to merge, at a depth that scales with the change. A light review is a diff read plus one or two lenses. A standard review is four lenses with refuters on the findings that need one. A full review adds extra lenses and a regression hunter. Only findings that break the state being shipped block a release, a round budget is set up front, and the rest goes on a follow-up list. Fixed rules pick each next step, the loop's state lives in files on disk, and nothing merges, pushes or deploys without approval. Use when the user asks to review a change or branch they own until it is clean, to run the review loop, to review, fix and re-check, for a light or quick review of their own change, for multi-round or adversarial review of their own work, or when Codex or another implementer finishes a piece that needs review before merge. Not for reviewing someone else's pull request, and not for review without fixes.
---

# Agentic review loop

One agent builds a small change. This session orchestrates: it runs the checks itself, freezes a snapshot, and sends fresh subagents to review it through lenses. The implementer fixes what blocks the release, or rejects an item with a reason. A fix-check then rules on each fixed finding. Everything else that was confirmed goes on a follow-up list for the owner.

The loop exists because fixing is where new defects come from. In the first case study, 95% of targeted findings were fixed, and 83% of fix rounds still introduced at least one new defect. The loop is sized because review has a cost that grows with every round. In a later case study, a feature that shipped switched off spent four hours in review, 42 findings were fixed, and one of them affected the state that shipped. The evidence for every rule here is in [references/evidence.md](references/evidence.md).

**Requirements:** `git`, a way to start fresh agents, and an implementer: Codex CLI, a subagent working in its own git worktree, or a person. Fresh agents come from the harness's own subagent tool (Claude Code's Agent tool, for example) or from `scripts/agent.sh`, which starts one from the shell through any agent CLI. The repo's own checks (tests, typecheck, build) must be runnable from this session. For a harness other than Claude Code, read [references/harnesses.md](references/harnesses.md) first.

**The user's own rules win.** When the user's instructions (AGENTS.md, CLAUDE.md, memory, the request) set a depth, a round budget, a worktree location, a usage-limit policy, a writing style, approval rules for outward steps, or a naming policy, follow them. The defaults below apply only where the user has none.

## Depth

Pick the depth when the piece is framed, and write it in `brief.md`. Start from the lightest depth that fits. Go up one level for each of these: the change touches authorization, delivery, stored data or money, the change runs unattended, or the change is over about 600 changed lines of source. A feature that ships switched off is reviewed for the switched-off state, which usually means one level lower.

| Depth | Use for | Review | Refuters | Fix-check | Subagent tokens |
|---|---|---|---|---|---|
| light | Docs, tests, small ordinary code, a change behind an off switch with no shared-path edits | The orchestrator reads the diff, plus one or two lenses (correctness, tests) | None. The orchestrator checks a major against the code itself | Only when a blocker or major was fixed: one checker | about 0.3M |
| standard | Ordinary features, changes to shared paths, anything that ships switched on with limited risk | Four default lenses | The findings that need one (step 4) and that would block | One checker per 8 fixed items, and a regression hunter when shared code changed | about 1M |
| full | Security, unattended or public code that ships switched on, data migrations | Four default lenses plus up to two extra | Every finding that needs one (step 4) | One checker per 8 items, at least two, plus a regression hunter | about 2M, plus about 0.5M per fix-check |

The owner can ask for a deeper review at any point. Never go deeper without asking.

## Roles

| Role | Who | Does | Never does |
|---|---|---|---|
| Owner | the user | Sets the goal, the invariants, the depth and the risk rules. Settles design trade-offs. Approves merges, pushes and deploys. Approves any round beyond the budget. | Write fix prompts |
| Orchestrator | this session | Writes every prompt, runs the gates, takes snapshots, launches reviewers and checkers, triages, decides the next step, keeps the ledger | Edit product code |
| Implementer | Codex, a subagent in its own worktree, or a person | Builds the piece and the fix round with red/green tests. Reports every command with its exit code. | Commit (unless the commit policy says so), weaken an assertion, see the reviewers' reasoning beyond the fix prompt, add a new mechanism inside a fix round |
| Lens reviewer | one fresh subagent per lens | Reads the snapshot through one lens and reports evidenced defects | See other lenses' output |
| Refuter | one fresh subagent per distinct finding that needs one (see step 4) | Tries to disprove one finding from the code, and says whether the base branch has it too | See other findings or which lens raised it |
| Fix-checker | fresh subagents, as the depth table says | Rules on each fixed finding and hunts regressions in the fix | Trust the fix report |

## Independence rules

These apply to every reviewer, refuter and fix-checker. They are what make several passes worth more than one.

1. **Fresh subagents only.** Start each as a new agent with an empty context: the harness's subagent tool (in Claude Code, the Agent tool as a new general-purpose agent), or `scripts/agent.sh` from the shell. Never use a mode that inherits this session's conversation, such as Claude Code's `fork`, and never continue an earlier reviewer for a new round. A refuter that wrote the findings defends them.
2. **No build story in the brief.** A reviewer gets the snapshot paths, the one-paragraph purpose, the invariants and the known-issues list. Leave out how the change was built, what you think of it, and the PR description or commit messages. Framing a change as safe cut vulnerability detection by 16 to 93 points in one study.
3. **The implementer's report goes to the fix-check only.** Lens reviewers and refuters never see it. Fix-checkers get it with "do not trust it" and attack its coverage claims first.
4. **Reviewers read a frozen snapshot**, never the live checkout. Make one with `scripts/snapshot.sh` before every review and every fix-check.
5. **Read-only on code and machine.** Reviewers and checkers run probes only in their own copy from `scripts/scratch.sh`, which gives each agent one absolute path. No installs into shared folders, no edits, no git writes. They kill only processes whose pid they recorded (`scripts/fake-tool.sh` and `scripts/kill-recorded.sh`), never by name or pattern, and remove only paths they created. Probes that could reach a clipboard tool run behind `scripts/fakebin.sh`. These rules go in every reviewer, refuter and checker prompt word for word: other sessions share the machine.
6. **Vary the reviewer.** When a second model family is available, use it for the second refutation of a high-severity claim. `scripts/agent.sh` starts a reviewer through another CLI (Claude Code, Codex, Cursor, opencode) in one command. Models favor output that resembles their own.

Several pieces at once: run their loops in parallel when they touch different files. Design and build for one piece can run while another is in review. Never run two full reviews at the same time.

## The loop

```
frame -> build -> gates -> snapshot -> REVIEW -> refute -> triage
                                                              |
                         blocking findings                    v
                +---- FIX-CHECK <- snapshot <- fix round <----+
                |                                             |
                v                                             v
        budget spent or clean                    nothing blocking
                |                                             |
                +-----> gates -> owner approves -> ship, follow-up list
```

### 0. Frame the piece (owner and orchestrator)

Write `brief.md` in the piece folder: one paragraph on what the change does, three to six invariants, the risk tags, the depth, the state that ships, the round budget, protected resources, settled design decisions, and the checks that cover the change. Use the template in [references/prompts.md](references/prompts.md#brief).

- **Concrete invariants.** "A missing race event is acceptable; a wrong one never is." Abstract invariants cost more regressions per item than concrete ones.
- **The state that ships.** Say what will be live after the release: the feature on, the feature off behind a default, a migration applied. Blocking is judged against this state.
- **Round budget.** The default is one fix round and one fix-check. Write a different number only when the owner gives one.
- **Risk tags:** `unattended`, `public`, `security`, `ground-truth`, `prototype` (an approved design exists), `none`. They feed the depth and choose extra lenses.
- **Size it.** One paragraph should describe it. Findings per review stay between about 7 and 19 whatever the size, so a large change gets sampled. Above about 1,500 changed lines, split the piece, or split the review by area with a lens set per area.
- **Mechanical guards** for any invariant that matters, such as a test or a preload that fails when a test touches a live directory. A sentence in a prompt doesn't stop an implementer's test run.

Confirm the brief with the user before the first build or review, unless the user has said to carry on without stopping.

### 1. Build (implementer)

The implementer works on its own branch from the latest base, in a worktree at the user's worktree location. It uses red/green tests and writes a report that follows the contract in [references/prompts.md](references/prompts.md#report): per item, every command with its exit code, and a coverage-claims list. Give it the checks it will be judged by, so it can run them itself.

When the change already exists (the user built it, or it came from elsewhere), skip to step 2.

### 2. Gates (orchestrator)

Run the checks that cover the change yourself. Never take the implementer's green on trust.

- **Scale the checks.** Before a review and after a fix round, run the fast ones: format, typecheck and the tests for the changed area. Run the full suite, and any check that costs money or model calls, once, on the commit that will ship.
- On a failure, decide first whether the product or the check is wrong. Rerun the failing check on the base, on the same machine. Classify the result: introduced, pre-existing or environment. Only an introduced failure goes to the implementer, as a gate item.

### 3. Snapshot (orchestrator)

```bash
bash scripts/snapshot.sh <checkout> <base-ref> <piece-dir>/s<step> [--prev <piece-dir>/s<prev-step>]
```

This writes a frozen `tree/`, `change.patch` against the merge base (untracked files included), `delta.patch` since the previous snapshot, and `snapshot.json` with the commit, the file counts and whether a merge is involved. It never touches the checkout's index or working tree. Copying costs no model usage, so near a usage limit take the snapshot now and run the review after the reset. Take it before linking dependencies into the checkout, so the link is not in the patch.

Each agent gets its runnable copy from `scripts/scratch.sh <snapshot> <agent-id> --deps <checkout>`: the tree plus the checkout's `node_modules`, cloned on APFS and reflink file systems, so a dozen agents don't each copy the dependency folder. Put the exact command in the agent's prompt. The same `scripts/` folder holds `mutate.sh` (break production lines one at a time and report caught or survived), `fakebin.sh` (fake clipboard tools) and `fake-tool.sh` with `kill-recorded.sh` (a fake git or delta that records its pids, and a kill that touches only those). Point agents at them so they don't write their own. `agent.sh` is for the orchestrator: it starts one fresh agent through an agent CLI and saves its final message.

### 4. Review (lens reviewers, then refuters)

Launch the lenses for the chosen depth in a single message, so they run in parallel. Use the lens prompts in [references/prompts.md](references/prompts.md#lenses).

- **Default lenses:** correctness, failure handling, safety and security, tests and design. Light depth uses correctness and tests.
- **Extra lenses** (full depth, up to two), picked from the risk tags and the diff: timing and state, blast radius, compatibility, performance and cost, operations, public surface, UI and accessibility, eval integrity, and design fidelity whenever an approved prototype exists.
- **Every review adds a merge lens** when the change contains a merge.
- **Coverage findings are capped.** The tests lens can remove guards one at a time with `mutate.sh` and report every survivor. Ask it for at most five, the ones that guard an invariant in the state that ships, ranked.

As each lens returns:
1. Merge duplicates across lenses into distinct defects, and record which lenses found each. Agreement between lenses predicts severity: multi-lens defects were major or worse 68% of the time, single-lens ones 25%.
2. Send each distinct defect that needs it to its own refuter with the refuter prompt. The refuter gets the claim (title, file:line, scenario) and traces the code itself, without the lens's argument.
   - **Needs a refuter:** every blocker and major, every finding raised from reading alone, and anything lenses disagree on.
   - **Confirmed by its evidence, no refuter:** a finding that two or more lenses each reproduced by running code, or a minor whose lens quotes an executed reproduction or a mutation that survives. Record `reasonClass: "executed-by-lens"`.
   - **At standard depth,** skip the refuter for a finding that would be deferred either way. At light depth there are no refuters: check a major against the code yourself.
   - Refuters for minors can run on a cheaper model.
3. Every refuter also checks the base branch and labels the finding **new** (the change introduced or exposed it) or **pre-existing** (the base behaves the same). Lens reviewers label it when they can tell.

Verdicts and their rules:
- **confirmed:** the refuter traced the failing path. It also corrects the severity, since reviewers inflate.
- **refuted:** a refutation of a blocker or major must cite an executed probe or test. A refutation from reading alone is `unverified`. In the data, read-only refuters refuted 26% of what they saw, and refuters that ran code refuted 7%.
- **unverifiable:** only a run that can't be done safely here would decide it. A blocking major or blocker stays open as "write the failing test first". Anything else is deferred.
- **Second refuter** (full depth): a blocker or major that comes back refuted or unverifiable goes to a second, independent refuter, from another model family when available. It survives if either one confirms it.
- **Spec-based refutations:** tag them `intended-by-spec` and quote the line. Revisit them when the spec changes.

Record every finding in the ledger (see below).

### 5. Triage (orchestrator)

This is the judgment step. Do it in minutes, from the ledger:

- **Mark each confirmed finding blocking or deferred.** A finding blocks when it breaks an invariant in the state that ships, when shipping it would do damage that can't be undone, or when it is a gate failure the change introduced. Everything else is deferred (status `deferred`): minors, defects in a state that is not being shipped, and missing tests for guards that hold today. A deferred finding keeps its evidence and goes on the follow-up list.
- **Pre-existing findings go to the backlog** (status `backlog`) unless they break the change's own promise or the owner pulls them in. Show the backlog to the owner at each report.
- Group blocking defects that share a root cause, and name the cause.
- Settle every design choice a fix would otherwise guess at, and write it into `brief.md` as a decision. Rounds with settled choices had about 0.14 regressions per item. A round that sent an undiagnosed "it feels off" item had 0.63.
- Regrade severity against the invariants, regressions included. A realistic scenario that breaks an invariant is a major. A rare input that breaks one (an unusual config, file system, file name or environment) stays minor, and the ledger says why.
- **A fix that needs a new mechanism is a new piece.** A new check with its own rules, a new stored field, a new authorization path, a new process or protocol: stop, tell the owner, and frame it as its own piece with its own review. A fix round removes a defect. In the later case study, a guard designed inside a fix round produced two of the next review's major findings.
- Fold in owner reports and live incidents, so they ship with the round.
- Overrule a refutation only with evidence, and say so in the ledger. An executed reproduction overrules a read-only refutation.
- **Two requirements that pull against each other** (a pendulum risk) go to the owner as a stated trade-off before the implementer sees them. Flag a mechanism that changed in two consecutive fix rounds as a pendulum candidate in the ledger, so its next regression fires R2 at once.
- Tell the owner now what blocks and what is deferred. Do not wait for the end of the loop.

When nothing blocks, go to step 10.

### 6. Fix round (implementer)

Write the fix prompt from the template in [references/prompts.md](references/prompts.md#fix). Its contract:

- Fix every item in the round, which are the blocking ones, or reject one with a reason verified against the code, naming the requirement it conflicts with. Deferred and backlog items are not in the round.
- Fix a shared cause once, and say which items it closes.
- Write a test per item that fails before the fix and passes after it.
- Never weaken, delete, skip or loosen an assertion or fixture to pass.
- Change nothing the items do not need. If a fix seems to need a new mechanism, stop and say so.
- List every caller of a changed shared helper. Test the opposite requirement of any new guard, latch, timeout or retry.
- State the commit policy in one place, and only once.

Hand it to the implementer: run Codex with the prompt, launch a fresh subagent in the piece's worktree, or give it to the user.

**Several implementers in parallel** (one per area, each in its own worktree): give each group an explicit list of the files it owns and the files it must not touch. When one group's fix needs something from another group's files, write that interface into both prompts as a fixed name and signature before either starts, and have the consumer keep a fallback so its worktree compiles before the merge. A request for an interface that arrives mid-round goes to the owning group, never to the requester. Merge the branches one at a time and run the gates after each merge.

### 7. Snapshot the fix

Run `scripts/snapshot.sh` again with `--prev` pointing at the previous snapshot. The fix-check reads `delta.patch` and the pre-fix tree.

### 8. Fix-check

Launch what the depth table says, in one message:

- **Fix-checkers:** split by item number. Each item gets a verdict: `fixed`, `partial` (say what's left), `not-fixed`, `rejected-ok` or `rejected-wrong`. If an item's test still passes with the fix reverted in a throwaway copy, the item is `partial`.
- **A regression hunter** (standard depth when shared code changed, full depth always): works through the five-point checklist in [references/prompts.md](references/prompts.md#hunt). It covers shared paths, changed contracts, mirror failures, test integrity, and the report's coverage claims.
- **The fast gates:** run them yourself in parallel with the agents. A gate item closes when its check passes, whatever a checker says about it.

Merge duplicate regressions, send each that needs one to a refuter under the same rule as review findings (step 4), and regrade the survivors with the blocking rule of step 5. A regression that does not break the state that ships is deferred. Record the depth of each one, so a regression of a regression is visible.

### 9. Decide

Apply the decision rules below, top to bottom. The first rule that matches picks the next step. Write the rule and the numbers behind it into the ledger.

### 10. Ship

Run the full gates yourself on the final tree, then ask the owner before any merge, push or deploy. Their approval covers only the step they approved. Give the owner the follow-up list with the release: each deferred finding in one line, with what it affects and when it should be done (before a switch is turned on, or whenever). Write a status entry wherever the user keeps them (knowledge base, PR description, ticket).

## Decision rules

| # | Signal | Next step |
|---|---|---|
| R1 | The owner reports a problem, or a live incident happens, while a round is open | Fold it into the round. Restart the round if it started under about 10 minutes ago. |
| R2 | A regression mirrors the finding just fixed, or the same mechanism regressed in two fix-checks in a row (a pendulum) | Stop patching. Write both failure modes as tests, state the trade-off, and have the owner decide. Then one fix round. |
| R3 | A fix needs a new mechanism, or a fix round added one (a new check with its own rules, process, watcher, protocol or authorization path) | Stop the round. Tell the owner and frame the mechanism as its own piece, with its own review at the depth it warrants. |
| R4 | Nothing blocks: no blocking finding is open, no regression blocks, and the gates pass | Ship (step 10) with the follow-up list |
| R5 | A blocking item is `partial`, `not-fixed` or `rejected-wrong`, a regression blocks, or a gate item still fails, and the round budget has rounds left | One fix round with the checker's evidence pasted in, then a fix-check |
| R6 | The same, and the round budget is spent | Stop. Report to the owner: what still blocks, the evidence, and the options (one more round, ship with the feature switched off, re-plan). The owner picks. |
| R7 | The implementer rejected an item | The fix-check judges it. A rejection that upholds a stated invariant stands. Route the requirement to whoever owns it. Never send a narrower version of a rejected requirement back. |
| R8 | Two rounds would edit the same files | Queue the second |
| R9 | Usage is at the user's reserve threshold (default: no new review past 70% of the window) | Take the snapshot now and schedule the review after the window resets |

A second full review of the same piece happens only when the owner asks for one, or when the change now contains a merge with the base. When the owner asks, an area re-review (full lenses on the area that changed, normal fix-checkers for the rest) is the first choice.

What to expect: most pieces ship after one fix round. In the first case study the first fix-check found a regression 10 times in 11, which is why the round after it needs the owner's yes.

## Severity

Set severity against the owner's invariants, not in the abstract.

- **blocker:** the piece's core promise breaks on a normal path, or shipping causes damage that can't be undone. Give a refutation a second refuter.
- **major:** a realistic scenario breaks an invariant. That covers wrong output, lost data, a privacy or security leak, a hang, an unattended service that can't recover, or a test that can't fail for a claim that matters.
- **minor:** a real defect with limited reach. That covers an error reason thrown away, a log flood, docs drift, a vacuous test for a low-stakes claim, an edge case with a workaround, or an invariant broken only by a rare input. On unattended code, look twice at error-reporting minors: one preceded the first case study's live incident.

Severity and blocking are different questions. A major in a state that is not being shipped is deferred. A minor that corrupts data in the shipped state blocks.

Severity is about this change. A pre-existing defect keeps its severity for the backlog but doesn't start a fix round unless it breaks the change's own promise.

## Done

A piece is done when all of these hold:

1. Every blocking finding is `fixed`, or `rejected-ok` with its requirement routed to the owner.
2. The fix-check found nothing that blocks, or the owner chose how to proceed under R6.
3. You ran the full gates yourself on the final tree and saw them pass.
4. The risk tags' evidence is in hand, or the owner agreed to supply it by using the feature. That means a real device for device features, side-by-side frames against the prototype for visual work, and scores holding on every answer key for measured work.
5. The owner has the follow-up list: every deferred finding, the backlog, and anything left open on purpose.

## The ledger

The loop's state lives in files, never only in this conversation. That lets a multi-day loop survive context compaction. Keep the folder somewhere a restart doesn't wipe, such as `~/Logs/<piece>-review/` or wherever the user keeps review evidence:

- `brief.md`: purpose, invariants, risk tags, depth, the state that ships, round budget, decisions, protected resources, checks.
- `ledger.json`: every finding. Each has an id (`F` review, `G` regression, `C` gate), severity as raised and as verified, whether it blocks, lenses, verdicts with reasons, status, attempts, the parent of a regression, and a history line per check.
- `s<n>/`: one folder per snapshot.
- `prompts/` and `reports/`: every prompt sent and every report received.
- `log.md`: one line per decision, naming the rule that fired.
- `RESUME.md`: what is running right now and how to resume it after a pause (the template is in [references/prompts.md](references/prompts.md#resume)). Rewrite it whenever agents start or stop.
- `agents-<step>.txt`: the agent id and job of every agent launched for a step, so a paused agent can be resumed by id.

After compaction or a new session, read `brief.md`, `ledger.json`, `RESUME.md` and the end of `log.md` before doing anything else. The schema is in [references/ledger.md](references/ledger.md).

## Cost and pacing

Cost in the first case study, counted as subagent tokens:

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

- A light review is a few minutes. A standard review is about 10 minutes of agents. A full review with its refuters is 20 to 30 minutes, and each fix-check adds 10 to 15.
- The implementer's fix round usually takes longer than the review, and it reruns checks and brings its own regressions. That is why one round is the default.
- Run full reviews one at a time. Two at once took a usage window from 50% to 85% in 20 minutes.
- **Cap concurrency at about 8 agents.** Tests, git and probes from 16 to 20 agents drove the load average to 20 to 46, and over 100 test runs timed out for load alone. Agents then spend their time classifying flakes.
- **Gates under load:** run with a generous per-test timeout, and treat a timeout as a failure only after it repeats in an isolated rerun.
- **Start big phases near the top of a usage window.** A fix round paused halfway costs a resume and leaves worktrees mid-edit. Near the user's threshold, take the snapshot and write the next phase's prompts, and launch after the reset.
- **Pausing:** stop the agents, write `RESUME.md`, and schedule one wake-up for just after the reset that checks the window really reset, restarts the watcher and resumes each agent. In Claude Code, stop with TaskStop and resume by id with SendMessage, and a stopped subagent keeps its context. An agent started with `agent.sh` starts again from its prompt file.
- Before the first review, start the user's usage watcher if they have one. Re-arm it when it expires, and stop it when the loop ends.
- Codex fix rounds don't count against this session's budget.

## Report to the user

After triage, and whenever the owner must decide something:

- **Status:** a verdict line and the rule that fired.
- **Blocking items** by severity, each with what was executed and the path to its evidence.
- **Follow-up list:** the deferred findings and the backlog, one line each.
- **Decisions needed:** budget spent, pendulums, a fix that needs a new mechanism, upheld rejections, spec-based refutations.
- **Totals:** rounds, reviews and fix-checks so far, with tokens and minutes.
- **Repo rule suggestions:** traps that cost time and that the repo's context files don't cover, given as file and exact text. Don't edit the repo's files for them unless asked.

Use the user's writing style. Keep refuted findings to one line each.

## Gotchas

- **Agents report back when they finish.** Don't poll or re-launch a reviewer that's still running. Use the wait to prepare the next snapshot or the gate run.
- **Review agents with side effects:** a checker's package install once changed a local clone. In the whole-repo sweep, a refuter found its hung fake process with `pgrep -f 'sleep 300'`, matched another Claude session's watcher loop, and killed that session; an implementer's `rm -rf probe` in the shared temp dir deleted another run's files. Repeat the read-only, kill and remove rules in every prompt, and give each agent its own scratch folder.
- **A scratch path that moves.** `$TMPDIR` can differ between a sandboxed and an unsandboxed command. A failed `cd` then sends the next write into the live checkout. Use the absolute path `scratch.sh` prints, tell each agent to check that a `cd` succeeded before any write, and tell it to delete only its own folder.
- **Shell aliases leak into agents.** On machines where `cp` and `rm` are aliased to verbose or interactive versions, tell agents to call `/bin/cp` and `/bin/rm`. The scripts already do.
- **The sandbox blocks native file watching and `ps`.** Watcher probes need native fs events, so they run outside the command sandbox; say so in the prompt. Scripts that need `ps` degrade instead of failing.
- **Wall-clock jumps.** A machine that slept makes agent durations and log times look wrong. Check `date` against the usage snapshot's `ts` before drawing conclusions.
- **A false baseline:** before calling a failure pre-existing, check that the base run had nothing stashed or patched.
- **Never push your own premise into a prompt** ("zero wins is very unlikely"). State the measured fact, or leave it out.
- **The snapshot is not the deployment.** OS permissions, network rules and real devices are invisible to a tree read. For unattended services, add a deployed smoke test as its own gate.
- **Offline cases prove nothing about a model.** When behavior depends on a model's judgment, a case counts only after a live run. Run every case of the touched feature, several times.
- **An installed copy can be stale.** When the skill is installed by copy, compare it with its source repository before a long loop.
- **Merge rounds stay separate.** Preview a merge in a throwaway worktree to count conflicts, then make the merge its own round with a merge-lens review. Don't bundle it with fixes.
- **Measured work runs its own loop.** When the goal is a number (recall, latency), score each round against labelled ground truth. Check the labels before blaming the code, and retire a blind set once it's been seen. Run a review on the result when the targets hold.
