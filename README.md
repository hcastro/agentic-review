# agentic-review

A Claude Code plugin that reviews a change until it is ready to merge.

Fresh subagents review a frozen snapshot of the change through lenses, at a depth that scales with the change: light, standard or full. Findings that need it go to a refuter before anyone acts on them. The implementer fixes what would break the state being shipped, and a fix-check rules on each fix. Everything else that was confirmed goes on a follow-up list. A round budget is set up front, fixed rules pick each next step, and nothing merges or pushes without your approval.

The full README, with diagrams, is in progress.

## Install

```sh
claude plugin marketplace add hcastro/agentic-review
claude plugin install agentic-review@agentic-review
```

## License

MIT
