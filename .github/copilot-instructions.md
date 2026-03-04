# Copilot Instructions for Terminal Stampede

## What this project is
Terminal Stampede is a cross-terminal multi-agent orchestration framework. It splits work across independent AI coding agents running in parallel tmux panes, coordinated through a filesystem-based message queue. Built with GitHub Copilot CLI but designed to work with any CLI coding agent (Aider, Claude Code, etc.).

## Architecture
Three files:
- `skills/SKILL.md` — Orchestrator skill (YAML frontmatter + markdown instructions, Copilot CLI format)
- `agents/stampede-agent.agent.md` — Worker agent (loaded per-session via `--agent`, Copilot CLI format)
- `bin/stampede.sh` — Bash launcher (tmux session management, PID tracking, CLI-agnostic)

## Key conventions
- **Filesystem as IPC.** All coordination through `.stampede/{run_id}/` directories inside the repo (queue, claimed, results, logs, pids). No databases, no HTTP, no Redis.
- **Atomic operations.** Task claiming via `mv` (POSIX rename). Result writing via `.tmp-` prefix then `mv`. Race-safe by design.
- **CLI-agnostic launcher.** `stampede.sh` defaults to Copilot CLI but supports `--agent-cmd` for any CLI agent.
- **Copilot-format skill/agents.** The SKILL.md and agent markdown files use Copilot CLI's format. Other CLI agents use the shell scripts directly.
- **Branch per task.** Workers create `stampede/{task_id}` branches. Never commit to main.
- **500-word result cap.** Worker summaries must be concise. Orchestrator context is limited.
- **Python for JSON.** All JSON operations use `python3 -c 'import json; ...'`. Never echo/printf JSON in bash.

## When editing these files
- SKILL.md must keep valid YAML frontmatter with the `tools:` list
- The worker agent must never include `ask_user` in its tools (it's autonomous)
- The launcher must use `-p` with `--autopilot` (not `-i`) for autonomous worker execution
- Keep the 24-landmine awareness — see SKILL.md's landmine reference table
