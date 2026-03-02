# Changelog

## 1.1.0 — 2026-03-02

### Changed
- Rewrote README intro with four key differentiators: zero infrastructure, human in the loop, tmux as runtime, CLI portability
- Reframed value proposition around parallel vs sequential workflow (no specific time/cost claims)
- Replaced static screenshot with animated GIF from real 8-agent run
- Added "We Pointed It at Itself" section with self-referential benchmark results
- Blog accuracy fixes: corrected sub-agent vs independent session distinction
- Removed stale hackathon number references

### Removed
- Cost references from README (comparison table, design decisions)
- "Nobody else has built this" uniqueness claim
- Unused static screenshot (docs/stampede-demo.png)
- Accidental Swift/CSS UI files that leaked into main

## 1.0.0 — 2026-03-01

Initial release. Built during a Havoc Hackathon.

### Features
- Orchestrator skill (`SKILL.md`) with natural language parsing, task decomposition, polling, dead worker recovery, crash recovery, conflict detection
- Worker agent (`stampede-worker.agent.md`) with atomic task claiming, git branch isolation, autonomous code work, structured JSONL logging
- Launcher (`stampede.sh`) with 8-prerequisite validation, tmux tiled layout, monitor pane, PID tracking via process tree walking, auto-open Terminal, teardown mode
- Gold ⚡ pane borders with model + task labels
- Filesystem-based IPC with atomic `mv` operations
- Support for 1-20 parallel agents (sweet spot: 6-8)

### Architecture
- Zero infrastructure: tmux + Copilot CLI + filesystem
- Agent for workers (per-session isolation), skill for orchestrator (always available)
- Branch per task prevents git conflicts
- 500-word result cap prevents context explosion
- `--max-autopilot-continues 30` prevents quota runaway
