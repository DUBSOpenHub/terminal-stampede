# Copilot Instructions for Terminal Stampede

## What this project is
Terminal Stampede is a cross-terminal multi-agent orchestration framework for GitHub Copilot CLI. It splits work across independent AI agents running in parallel tmux panes, coordinated through a filesystem-based message queue.

## Architecture
Three files:
- `skills/SKILL.md` — Orchestrator skill (YAML frontmatter + markdown instructions)
- `agents/stampede-worker.agent.md` — Worker agent (loaded per-session via `--agent`)
- `bin/stampede.sh` — Bash launcher (tmux session management, PID tracking)

## Key conventions
- **Filesystem as IPC.** All coordination through `~/.copilot/stampede/{run_id}/` directories (queue, claimed, results, logs, pids). No databases, no HTTP, no Redis.
- **Atomic operations.** Task claiming via `mv` (POSIX rename). Result writing via `.tmp-` prefix then `mv`. Race-safe by design.
- **Agent, not skill, for workers.** Skills load globally. Agents load per-session. Workers must be agents for role isolation.
- **Branch per task.** Workers create `stampede/{task_id}` branches. Never commit to main.
- **500-word result cap.** Worker summaries must be concise. Orchestrator context is limited.
- **Python for JSON.** All JSON operations use `python3 -c 'import json; ...'`. Never echo/printf JSON in bash.

## When editing these files
- SKILL.md must keep valid YAML frontmatter with the `tools:` list
- The worker agent must never include `ask_user` in its tools (it's autonomous)
- The launcher must use `-p` with `--autopilot` (not `-i`) for autonomous worker execution
- Keep the 24-landmine awareness — see SKILL.md's landmine reference table
