# Agents

## Overview

Terminal Stampede ships three components: a **Stampede orchestrator skill**, a **worker agent** (stampede-agent), and a **merger agent** (stampede-merger). Together they form a complete parallel agent runtime — the skill parses your instructions and spawns agents, each worker claims tasks and writes code on isolated branches, and the merger auto-merges all branches with conflict resolution and Shadow Score quality measurement.

## Available Agents

### stampede-agent (Worker Agent)

- **Purpose**: Autonomous worker that claims tasks from the filesystem queue, executes them on an isolated git branch, writes results atomically, and loops until the queue is empty. Each instance runs in its own tmux pane with its own Copilot CLI context window. Supports up to 20 simultaneous instances.
- **Usage**: Spawned automatically by `stampede.sh`. Can also be invoked manually for a single task:
  ```
  # After installing, the launcher handles this:
  stampede.sh --count 6 --task "add unit tests to all modules"
  ```
- **Model**: Default model in your Copilot CLI session (configurable per-agent)
- **Location**: `agents/stampede-agent.agent.md` → installs to `~/.copilot/agents/stampede-agent.agent.md`

### stampede-merger (Merger Agent)

- **Purpose**: After all worker agents complete, this agent discovers all stampede branches, sorts them by output size (largest first as a quality proxy), merges them sequentially into a combined branch, resolves conflicts using AI with full task context, shadow-scores each agent's work across 3 layers, and produces a scored merge report.
- **Usage**: Run automatically after all agents finish, or invoke manually:
  ```bash
  ~/bin/stampede-merge.sh    # Triggers merger agent via Copilot CLI
  ```
- **Model**: Default model in your Copilot CLI session
- **Location**: `agents/stampede-merger.agent.md` → installs to `~/.copilot/agents/stampede-merger.agent.md`

### stampede (Orchestrator Skill)

- **Purpose**: Primary entry point for Terminal Stampede. Parses your natural language command, generates structured task files, monitors agent progress, detects stuck agents, and synthesizes final results. Drives the full Stampede workflow from a single command.
- **Usage**:
  ```
  run stampede "add error handling to all API endpoints"
  run stampede "write tests for every function in src/"
  stampede status        # Check live progress
  stampede merge         # Trigger the merger agent
  ```
- **Location**: `skills/stampede/SKILL.md` → installs to `~/.copilot/skills/stampede/SKILL.md`

## Shell Scripts

These scripts are installed to `~/bin/` and drive the tmux runtime:

| Script | Purpose |
|--------|---------|
| `stampede.sh` | Creates the tmux session, spawns agent panes, tracks PIDs |
| `stampede-monitor.sh` | Live progress display, stuck detection, runtime stats |
| `stampede-merge.sh` | Discovers branches, sorts by size, launches the merger agent |

## Configuration

- **Default agents**: 3 (configurable with `--count`, maximum 20)
- **Sweet spot**: 6–8 agents for most tasks
- **Task queue**: Filesystem-based atomic queue (`/tmp/stampede-tasks/` by default) — no Redis, no message broker
- **Task claiming**: Atomic file rename — no locks, no coordination server, no race conditions
- **Branch naming**: Each agent works on `stampede/<agent-id>/<task-id>` — fully isolated
- **Quality scoring**: Uses [Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec) — quality criteria defined before agents run, measured silently after
- **Observability**: Every agent runs in a visible tmux pane; type into any pane, kill it, or watch in real time
- **CLI agent compatibility**: Built for GitHub Copilot CLI; shell scripts work with Aider, Claude Code, or any CLI tool

## Install

```bash
git clone https://github.com/DUBSOpenHub/terminal-stampede.git
cd terminal-stampede && ./install.sh
```

Or add via Copilot CLI:
```
/skills add DUBSOpenHub/terminal-stampede
```
