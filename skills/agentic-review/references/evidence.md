# Why the loop works this way

Case-study numbers come from a four-day project (GameCast, Oct 14 to 18, 2026): 72 workflow runs, 17 full reviews, 18 checked fix rounds, 320 proposed findings. External results come from published papers and vendor write-ups. Sample sizes are small; treat thresholds as starting points to tune on your own repos.

## Independence

- **Same-context self-review degrades.** Without an outside signal, a model correcting its own work gets worse (Huang et al., ICLR 2024: GPT-4 on GSM8K 95.5 → 91.5 → 89.0). Once confident, more reflection stops producing new ideas (Liang et al., EMNLP 2024).
- **Review history adds noise.** Multi-turn review had 62% more false positives than a single pass; reviewers invented findings once the real errors ran out (Song 2026, small study).
- **Independent passes see different things.** Five runs of the same model overlapped on only 27 correct findings (SWR-Bench, PKU). The gain from several passes comes from that spread.
- **Framing biases reviewers.** Telling a reviewer a change was safe cut vulnerability detection by 16 to 93 points; removing the PR metadata restored most of it (Mitropoulos et al. 2026). Hence no build story, no PR text and no implementer report in hunter prompts.
- **Models favor their own output** (Panickssery et al., NeurIPS 2024), and mixing model families is the change that most reliably helps multi-agent debate (Zhang et al. 2025).
- **Case study:** 15 implementer claims were later disproved, about two thirds of them coverage claims ("covered by tests", "can never"). None was a false exit code.

## Refuting findings

- Refuters removed 22% of proposed findings (69 of 320): 27% of minors, 9% of majors, 0 of 1 blocker. The top reasons: nothing breaks today (24 of 60), the spec asks for it (16), it can't happen (12), the evidence was wrong (8).
- **Reading-only refutations are weak.** Refuters that only read refuted 26%; refuters that ran code refuted 7%. 80 of 83 refutations were reading judgments. Adversarial review "catches reasoning errors but not empirical errors" (Refute-or-Promote, Agarwal 2026). In that study, ten reviewers unanimously endorsed a vulnerability that didn't exist, and only running a test caught it.
- **Refuters err too.** In 6 duplicate clusters one refuter killed what another confirmed. A refuted leak came back a day later as a major once the spec changed.
- **Precision comes from a verify step that checks evidence.** Anthropic's code review, with a verification pass after parallel bug hunters, reports under 1% of findings marked incorrect.

## Fix rounds and fix-checks

- 200 items checked: 190 fixed (95%), 9 partial, 0 not fixed. 15 of 18 fix rounds (83%) introduced at least one regression: 40 distinct, 6 major.
- Regressions fall with each fix-check on a piece: the first fix-check found one 10 times in 11, and majors were gone by the third.
- Fixed items regress in the field too: 14.8% to 24.4% of post-release OS fixes were incorrect, 39% for concurrency fixes (Yin et al. 2011).
- **Sequential loops stop paying after one or two rounds.** Self-Refine saw most gains in the first iterations. Fix attempts lose 60 to 80% of their effectiveness within 2 to 3 tries, and a fresh start recovers it (Debugging Decay Index, 2025). Hence the escalation after two failed fix-checks.
- **Settled choices cut regressions.** Rounds with settled design choices or grouped shared causes had about 0.14 regressions per item. An undiagnosed owner-feel round had 0.63. Nine pendulum regressions (a fix swinging into the mirror failure) caused 3 of the 6 majors.
- **Agents game tests.** Frontier agents edit or delete tests to pass them (METR 2025, ImpossibleBench). In the case study, the one fix prompt without the anti-weakening rule is where the implementer changed two fixtures to hide a regression.

## Full reviews and re-reviews

- A full review costs about six fix-checks (1.69M against 0.27M tokens, median). They find different things: three re-reviews found 27 distinct defects, 6 major, and only 2 overlapped earlier fix-check regressions.
- Lens yield: tests-and-design 67 confirmed (43 found by no other lens), correctness 54 (22 major or worse), failure 47 (36 solo), safety 22. A standalone "design" lens lost 7 of 8 findings to refuters.
- Multi-lens defects were major or worse 68% of the time; single-lens defects 25%.
- Late rounds shift: stateful timing and recovery is 17% of first-review defects and 35% of regressions; security findings were almost all early (12 in first reviews, 1 in re-reviews).
- Independent passes help up to about five (SWR-Bench: "diminishing returns beyond n=5"). Four to six lenses sit in that range.

## Size

- Confirmed findings per review stayed between 7 and 19 across a 39-fold range of change size (248 to 9,650 lines). A large change gets sampled.
- Human review limits agree: reviewers stop finding defects past about 400 lines per sitting and 500 lines per hour (SmartBear/Cisco); Google's median change is 24 lines.

## What the loop missed

Four defects reached the owner after reviewed code merged, within about 36 hours:

- An OS privacy rule on the deployed machine that no tree read could see.
- A missing request timeout that two reviews didn't raise.
- A UI that matched the brief and missed the approved prototype.
- A test run that broke a shared live directory despite a prompt invariant.

Hence the deployed smoke test, the design-fidelity lens and mechanical guards.

## Whole-repo sweep

A second run, Oct 27 to 28, 2026: a terminal app (`branch-review`) reviewed as one piece across the whole repo, three fix rounds, Claude subagents as implementers in four parallel file-ownership groups. The change grew from about 8,500 to 14,000 changed lines. About 130 agents ran in total, over three usage windows.

- **It never converged, and scope was the main reason.** Confirmed findings per review ran 51, then about 59, then about 30. Each fix round fixed most of what it got (32 of 51 fully in round 1, 62 of 63 in round 2), and each re-review found a new layer. At least six confirmed findings were pre-existing on the base (a delta line-length cut, non-UTF-8 contents and names, header-only files, a debounce that starves). With no backlog rule they became fix-round items and widened the next round. Hence the `base` label, the backlog status and the late-round minor rule (R7).
- **Drift fired every round.** Each round added a new mechanism in one area (a forked refresh process, a native watcher, an asynchronous refresh), so R4 bought three full reviews and the cheap fix-check never ran alone. Hence R4a.
- **The refresh limit was a three-round pendulum** (fixed timeout, then a no-progress limit, then gaps in that limit's progress reports). R2 fired only on the third regression. Hence the pendulum-candidate flag.
- **Severity drifted upward.** "A minor that breaks an invariant is a major", applied to seven broad invariants, promoted about ten rare-input findings (a whole-second file system, a relative TMPDIR, a file named like the range). Refuters downgraded many majors the other way. Hence "realistic scenario".
- **Refuters mostly confirmed.** 74 refuters ran across two reviews; 4 refuted outright and a few narrowed a claim. Most of the minors they confirmed already carried an executed reproduction from the lens. Hence `executed-by-lens`.
- **A read-only refutation was wrong.** A focus-after-refresh defect refuted by reading in the second review was reproduced by a run in the third.
- **The machine was the bottleneck.** 16 to 20 concurrent agents running tests and probes held the load average at 20 to 46; over 100 test runs timed out for load alone, and each agent copied the tree and `node_modules` again. Hence the concurrency cap, `scratch.sh` and the shared probe scripts.
- **Prompt-only safety failed twice.** A refuter killed another Claude session by matching `sleep 300` with `pgrep -f`, and an implementer's `rm -rf` deleted another run's probe folder. Hence `fake-tool.sh`, `kill-recorded.sh` and the machine-rules block in every prompt.
- **Explicit interfaces worked.** Parallel groups that had a fixed name and signature for what they needed from each other merged without conflicts; the one mid-round interface request came from a gap in the prompt.
