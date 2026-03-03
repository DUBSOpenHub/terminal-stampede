# Contributing to Terminal Stampede

Thanks for your interest in contributing! Terminal Stampede is an experiment in parallel AI agent orchestration, and contributions are welcome.

## Getting Started

1. Fork the repo
2. Clone your fork and create a branch: `git checkout -b my-feature`
3. Make your changes
4. Test locally: `./install.sh` and run the demo
5. Commit with a descriptive message
6. Open a pull request

## What to Contribute

- **Bug fixes** — especially edge cases in task claiming, PID tracking, or merge logic
- **CLI agent integrations** — tested `--agent-cmd` templates for Aider, Claude Code, or other tools
- **Documentation** — usage examples, troubleshooting, architecture explanations
- **Monitor/demo improvements** — better tmux layouts, status detection, visual polish

## Architecture

The codebase is intentionally small:

| File | Role |
|------|------|
| `bin/stampede.sh` | Launcher — tmux session, pane management, PID tracking |
| `bin/stampede-monitor.sh` | Live progress display |
| `bin/stampede-merge.sh` | Auto-merger with shadow scoring |
| `bin/stampede-demo.sh` | Zero-dependency visual demo |
| `skills/SKILL.md` | Orchestrator (Copilot CLI skill format) |
| `agents/stampede-worker.agent.md` | Worker agent (Copilot CLI agent format) |
| `agents/stampede-merger.agent.md` | Merger agent (Copilot CLI agent format) |
| `install.sh` | Installer |

## Conventions

- **Shell scripts** — `bash`, `set -euo pipefail`, shellcheck-clean
- **JSON** — always via `python3 -c 'import json; ...'`, never `echo`/`printf`
- **Atomic writes** — `.tmp-` prefix then `mv` for any result/state file
- **No external dependencies** — only `tmux`, `bash`, `python3`, `git`, `jq`, `openssl`

## Code of Conduct

Be kind. This is an experiment built for learning. All skill levels welcome.
