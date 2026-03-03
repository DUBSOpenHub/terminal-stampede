# Changelog

## 1.2.0 — 2026-03-02

### Added
- **Auto-merger agent** (`stampede-merger.agent.md`): merges all stampede branches into a single `stampede/merged-{run_id}` branch, resolves conflicts using AI with task context, skips irreconcilable changes
- **3-layer shadow scoring**: rates each agent's work silently during and after merge
  - Layer 1 (Runtime): timing, stuck events, file counts — captured by monitor
  - Layer 2 (Merge): conflict friendliness — captured during merge
  - Layer 3 (Quality): completeness, scope adherence, code quality, test impact — AI evaluation post-merge
- **Weighted scoring**: Completeness 30%, Scope 25%, Quality 20%, Test 15%, Conflict 10% — normalized to /50
- **Cross-run model leaderboard**: scores persist to `~/.stampede/model-stats.json`
- **Merge launcher** (`stampede-merge.sh`): discovers branches from results, sorts by file count, runs merger agent
- **Runtime stats capture** in monitor: writes `runtime-stats.json` for Layer 1 scoring
- Merge hint in monitor completion ceremony

### Changed
- Monitor alerts: bell sounds once per stuck agent (not every 5s loop)
- Stuck agents display in red box-drawing frame instead of plain text
- Architecture diagram updated with merger step
- Install script now installs merger agent + merge script

### Fixed
- Model ID format: `claude-sonnet-4.5` (dots, not hyphens) in SKILL.md

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
- Orchestrator skill (`SKILL.md`) with natural language parsing, task decomposition, polling, dead agent recovery, crash recovery, conflict detection
- Agent (`stampede-worker.agent.md`) with atomic task claiming, git branch isolation, autonomous code work, structured JSONL logging
- Launcher (`stampede.sh`) with 8-prerequisite validation, tmux tiled layout, monitor pane, PID tracking via process tree walking, auto-open Terminal, teardown mode
- Gold ⚡ pane borders with model + task labels
- Filesystem-based IPC with atomic `mv` operations
- Support for 1-20 parallel agents (sweet spot: 6-8)

### Architecture
- Zero infrastructure: tmux + CLI agents + filesystem
- Agents for tasks (per-session isolation), skill for orchestrator (always available)
- Branch per task prevents git conflicts
- 500-word result cap prevents context explosion
- `--max-autopilot-continues 30` prevents quota runaway
