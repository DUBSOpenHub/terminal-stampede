# What happens when you give AI agents their own terminals?

I didn't set out to build a multi-agent orchestration framework. I was just trying to make my agents better, and this fell out of the process.

## It started with scoring

A few weeks ago I was watching AI models write code and wondering: how do you actually know which one did a better job? Not vibes. Not "this one feels smarter." Something measurable.

That led to [Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec) — a sealed-envelope testing protocol. You give two models the same task, score them blind, and let the numbers talk. No peeking at who wrote what until after the verdict. Simple idea, but it changed how I thought about AI output. Quality isn't subjective when you have a rubric.

## Then came the arena

Once I could score models, the obvious next question was: what if I scored a bunch of them at once? That became [Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon) — a skill that pits up to 14 AI models against each other in tournament elimination. Sealed judges, ELO ratings, evolution between rounds. I've run 37 of these now. The leaderboard has real data on which models are good at what.

But Havoc Hackathon has a constraint: every contestant runs inside the same Copilot CLI session. They share one context window. The orchestrator launches them as sub-agents, waits for each one, scores them. It's concurrent but not parallel. Model 5 waits while Model 4 thinks.

## The "what if" moment

I was watching Hackathon #37 run — 8 models competing to build a multi-agent framework (meta, I know) — and I thought: what if each contestant had its own terminal? Not a sub-agent sharing my context, but a completely independent Copilot session with its own 200K tokens of working memory, its own tool access, its own ability to read files, edit code, and run tests.

I already had the pieces. Copilot CLI supports custom agents (`--agent`). tmux can split a terminal into arbitrary panes. Filesystems are already message queues if you squint.

## The prototype

The idea was dumb-simple:

1. Write task descriptions as JSON files in a `queue/` folder
2. Spin up N tmux panes, each running a Copilot session with a worker agent
3. Each worker grabs a task file by renaming it (atomic, race-safe)
4. Worker does the actual work on its own git branch
5. Worker drops a result file when done
6. An orchestrator polls for results and synthesizes

No server. No database. No framework. Just files and terminals.

I had Hackathon #37's contestants build it. Eight models, three files each, two elimination rounds. Then I synthesized the best elements from the top two finalists into a working prototype.

## What I learned by running it

The first few launches were rough. Workers would start but not claim tasks. The autopilot flag only works in prompt mode (`-p`), not interactive mode (`-i`) — a subtle CLI distinction that cost me three debug cycles. Workers would sometimes finish but not write a result because they hit the autopilot continuation cap. The orchestrator couldn't tell if a worker was thinking or dead.

Each failure mode had the same fix: keep it simple. PID checks instead of heartbeats. Generation counters instead of dedup logic. Atomic file renames instead of lock files. Every time I reached for complexity, the filesystem already had the answer.

The moment it clicked: I launched 8 agents on [ghost-ops](https://github.com/DUBSOpenHub/ghost-ops), my autonomous daemon project. Eight panes lit up, each with a gold ⚡ border showing the model and task. One agent was adding error handling to the watchdog module. Another was writing integration tests. Another was improving the ELO router. All simultaneously. All on their own git branches. All finishing in about 5 minutes.

A single session doing the same work would have taken 30-40 minutes.

## What this connects to

The tools I'd built before turned out to be layers of the same stack:

- **[Agent X-Ray](https://github.com/DUBSOpenHub/agent-xray)** scans agents and scores their quality. Terminal Stampede could use those scores to decide which agents to deploy.
- **[Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec)** measures output quality. Stampede could shadow-score results before accepting them.
- **[Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon)** maintains an ELO leaderboard across 15 models and 37 competitions. Stampede could use that data to route tasks to the right model — Opus for architecture, Haiku for docstrings, Sonnet for tests.
- **[Ghost Ops](https://github.com/DUBSOpenHub/ghost-ops)** runs autonomous missions on a schedule. Stampede could be a mission type — "every morning at 6am, dispatch 8 agents to sweep the codebase."

None of this was planned. Each tool solved a specific problem, and they happened to compose.

## What I'm still figuring out

This is an experiment, not a product. Things I don't know yet:

**Does the quality hold up?** Eight fast agents might produce eight mediocre results. I haven't done rigorous quality comparison between "one Opus session doing 8 tasks carefully" versus "eight Haiku sessions doing 1 task each quickly." That's a Shadow Score experiment waiting to happen.

**Where's the cost ceiling?** Right now it's cheap — Haiku workers at ~$0.25 per task. But if you dispatch 20 agents on a large repo multiple times a day, that adds up. The token-scoped context optimization (only send files the worker actually needs) isn't built yet.

**How far does the filesystem queue scale?** For 8-20 workers it's fine. For 100? Probably not. But 100 parallel AI agents on one repo is a problem I'm happy to have later.

**Is the orchestrator skill reliable as a live invocation?** I've been building manifests manually and calling the launcher directly. The skill file describes how to parse natural language commands, but it hasn't been battle-tested as a real "say stampede and it works" experience yet.

## The insight I keep coming back to

Every multi-agent framework I've seen treats agents as function calls. They're threads in a process, sharing memory, sharing an API connection, taking turns. That's concurrency.

Terminal Stampede treats agents as developers. Each one gets a desk (tmux pane), a full copy of the project (200K context), their own tools (bash, grep, edit), and a task written on a sticky note (JSON manifest). They work independently and drop their results in a shared folder when done. That's parallelism.

The distinction matters because the agent doesn't just think — it does. It reads code, edits files, runs tests, sees failures, and iterates. You can't do that well in a shared context. You need your own workspace.

The CLI was already the agent runtime. I just needed 8 of them.

---

*Built during [Havoc Hackathon #37](https://github.com/DUBSOpenHub/havoc-hackathon). Tested on [ghost-ops](https://github.com/DUBSOpenHub/ghost-ops). Code at [terminal-stampede](https://github.com/DUBSOpenHub/terminal-stampede).*
