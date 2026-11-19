# Running the loop in any agent harness

The loop is written as instructions and shell scripts. It needs four things from the harness that runs it. Read this when the orchestrator is not Claude Code, or when you want reviewers from a second model family.

## What the orchestrator needs

1. **Run shell commands and `git`** in the checkout and in the piece folder.
2. **Read and write files** in the piece folder (`brief.md`, `ledger.json`, prompts, reports).
3. **Start a fresh agent** with a prompt and get its final message back. Fresh means an empty context: no conversation history, no memory of earlier rounds.
4. **Wait for several agents at once.** Optional. Without it the lenses run one after another and the review takes longer.

Everything else in SKILL.md is the same in every harness.

## Starting a fresh agent

Use the harness's own subagent tool when it has one that starts with an empty context. Otherwise start the agent from the shell with `scripts/agent.sh`, which runs an agent CLI as a new process and saves its final message:

```bash
copy=$(bash <skill-dir>/scripts/scratch.sh <snapshot> lens-correctness --deps <checkout>)
bash <skill-dir>/scripts/agent.sh codex <piece-dir>/prompts/lens-correctness.md <piece-dir>/reports/lens-correctness.md --dir "$copy"
```

| Harness | Fresh agent | Notes |
|---|---|---|
| Claude Code | The Agent tool, as a new general-purpose agent. Never `fork`, which inherits the conversation | `agent.sh claude` also works and runs `claude -p` |
| Codex CLI | `agent.sh codex` | Runs `codex exec -s workspace-write`, so the agent can write only inside `--dir` |
| Cursor CLI | `agent.sh cursor` | Runs `cursor-agent -p --trust`. The agent has shell and write access, so give it its own scratch copy |
| opencode | `agent.sh opencode` | Runs `opencode run`. Needs a configured default model, or `--model provider/model` |
| Anything else | `agent.sh custom` | Set `AGENTIC_REVIEW_AGENT_CMD` to a command that reads the prompt on stdin and prints the final message |

Rules that hold whichever way an agent starts:

- **One agent, one scratch copy, one prompt file, one report file.** Write the prompt to `prompts/` before launching, so the ledger has what was sent.
- **Paste the machine rules** from [prompts.md](prompts.md#machine-rules) into every prompt. A CLI started from the shell does not inherit the orchestrator's permission settings.
- **Run several at once** with `&` and `wait`, and keep to about 8.
- **Extra options** go after `--`: `agent.sh claude p.md r.md --dir "$copy" -- --allowedTools "Read Grep Glob Bash"`.

## A second model family

Independence rule 6 asks for a different model on the second refutation of a high-severity claim. With `agent.sh` that is one command: an orchestrator on one family starts the second refuter through another family's CLI.

## The implementer

Any agent or person that can work in a git worktree and write the report in [prompts.md](prompts.md#report). Hand the fix prompt to a harness's own session, to `agent.sh` with `--dir <worktree>`, or to a person.

## Stopping and resuming

- **Native subagents:** stop and resume them with the harness's own controls. In Claude Code that is TaskStop and SendMessage, and a stopped subagent keeps its context.
- **Agents started with `agent.sh`:** stop the process whose pid you recorded. To resume, start it again from the same prompt file. It begins from the top, so keep each prompt to one job.

## Where the user's rules live

"The user's own rules win" means the instruction files the harness loads: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, a rules folder, or the request itself. Read them for a depth, a round budget, a worktree location, a usage policy, approval rules and a writing style before framing the piece.

## Usage limits

R9 and the pacing notes in SKILL.md were measured on Claude Code's usage windows. In a harness without them, keep the two rules that are about the machine: one full review at a time, and about 8 agents at once.
