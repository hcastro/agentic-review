# agentic-review

A Claude Code plugin that reviews a change until it is ready to merge.

Fresh subagents review a frozen snapshot of the change through several lenses. Each finding goes to its own refuter before anyone acts on it. The implementer fixes what survives, and a fix-check after every round rules on each finding and hunts for regressions the fix introduced. Fixed rules pick each next step, and nothing merges or pushes without your approval.

The full README, with diagrams, is in progress.

## Install

```sh
claude plugin marketplace add hcastro/agentic-review
claude plugin install agentic-review@agentic-review
```

## License

MIT
