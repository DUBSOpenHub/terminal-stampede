# I Split One Terminal Into 8 AI Brains. Here's What Happened.

I didn't set out to build a multi-agent orchestration framework. I was just trying to make my agents better, and this fell out of the process.

## It started with the arena

Working in the Copilot CLI, I kept wondering: when you ask two AI models to do the same task, how do you actually know which one did a better job? Not vibes. Not "this one feels smarter." Something measurable.

That became [Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon) — a skill that pits up to 14 AI models against each other in tournament elimination. Sealed judges, ELO ratings, evolution between rounds. I've run 37 of these now. The leaderboard has real data on which models are good at what.

## Then came the measuring stick

Running hackathons surfaced a new problem: the judges needed a consistent way to evaluate quality. That led to [Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec) — a sealed-envelope testing protocol. You give two models the same task, score them blind, and let the numbers talk. No peeking at who wrote what until after the verdict. Quality isn't subjective when you have a rubric.

## Then the factory

Once I could score quality, I wanted to build things with that same rigor. That became [Dark Factory](https://github.com/DUBSOpenHub/dark-factory) — an agentic build system where 6 specialist agents work through a checkpoint-gated pipeline, and a sealed test suite judges the output without the builders ever seeing the acceptance criteria. Shadow Score built into the build process.

## Then the scan visor

Dark Factory builds things, but how do you know the agents themselves are well-constructed? That led to [Agent X-Ray](https://github.com/DUBSOpenHub/agent-xray) — a scanner that reads any agent prompt and scores it across 6 dimensions. Think of it as a health check for your AI agents before you send them on a mission.

## The "what if" moment

But Havoc Hackathon has a constraint: every contestant runs as a sub-agent inside the same session. The orchestrator dispatches them, collects results, and scores them. They each get their own context, but they're managed processes — the orchestrator is the bottleneck, and contestants can't interact with the repo the way a real developer would (reading files, editing code, running tests, iterating on failures).

I was watching Hackathon #37 run — 8 models competing to build a multi-agent framework (meta, I know) — and I thought: what if each contestant had its own terminal? Not a sub-agent sharing my context, but a completely independent Copilot session with its own 200K tokens of working memory, its own tool access, its own ability to read files, edit code, and run tests.

I already had the pieces. Copilot CLI supports custom agents (`--agent`). tmux can split a terminal into arbitrary panes. Filesystems are already message queues if you squint.

## The prototype

The idea was simple:

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

The moment it clicked: I launched 8 agents on [ghost-ops](https://github.com/DUBSOpenHub/ghost-ops), my autonomous daemon project. Eight panes lit up, each with a gold ⚡ border showing the model and task. One agent was adding error handling to the watchdog module. Another was writing integration tests. Another was improving the ELO router. All simultaneously. All on their own git branches. All finishing while I watched.

Doing those same tasks one at a time would have meant sitting through each one sequentially, context-switching between them, losing momentum. Instead, every task ran in parallel and my wait time was just the longest single task, not the sum of all of them.

## What this connects to

Each tool I'd built before turned out to be a layer of the same stack:

- **[Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon)** maintains an ELO leaderboard across 15 models and 37 competitions. Stampede could use that data to route tasks to the right model.
- **[Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec)** measures output quality. Stampede could shadow-score results before accepting them.
- **[Dark Factory](https://github.com/DUBSOpenHub/dark-factory)** builds production code through a checkpoint pipeline. Stampede could parallelize the build phases.
- **[Agent X-Ray](https://github.com/DUBSOpenHub/agent-xray)** scans agents and scores their quality. Stampede could use those scores to decide which agents to deploy.
- **[Ghost Ops](https://github.com/DUBSOpenHub/ghost-ops)** runs autonomous missions on a schedule. Stampede could be a mission type — "every morning at 6am, dispatch 8 agents to sweep the codebase."

None of this was planned. Each tool solved a specific problem, and they happened to compose.

## What I'm still figuring out

This is an experiment, not a product. Things I don't know yet:

**Does the quality hold up?** Eight fast agents might produce eight mediocre results. I haven't done rigorous quality comparison between "one powerful session doing 8 tasks carefully" versus "eight lightweight sessions doing 1 task each quickly." That's a Shadow Score experiment waiting to happen.

**How far does the filesystem queue scale?** For 8-20 workers it's fine. For 100? Probably not. But 100 parallel AI agents on one repo is a problem I'm happy to have later.

**Is the orchestrator skill reliable as a live invocation?** I've been building manifests manually and calling the launcher directly. The skill file describes how to parse natural language commands, but it hasn't been battle-tested as a real "say stampede and it works" experience yet.

## The insight I keep coming back to

Every multi-agent framework I've seen treats agents as function calls. They're threads in a process, sharing memory, sharing an API connection, taking turns. That's concurrency.

Terminal Stampede treats agents as developers. Each one gets a desk (tmux pane), a full copy of the project (200K context), their own tools (bash, grep, edit), and a task written on a sticky note (JSON manifest). They work independently and drop their results in a shared folder when done. That's parallelism.

The distinction matters because the agent doesn't just think — it does. It reads code, edits files, runs tests, sees failures, and iterates. You can't do that well in a shared context. You need your own workspace.

The CLI was already the agent runtime. I just needed 8 of them.

---

*Built during [Havoc Hackathon #37](https://github.com/DUBSOpenHub/havoc-hackathon). Tested on [ghost-ops](https://github.com/DUBSOpenHub/ghost-ops). Code at [terminal-stampede](https://github.com/DUBSOpenHub/terminal-stampede).*
