# What If You Could Run 20 AI Agents in One Terminal?

I didn't plan to build a parallel agent runtime. I was exploring what CLI coding agents could do, and one experiment kept leading to the next.

## It started with the arena

Working in the terminal with AI coding agents, I kept wondering: when you ask two AI models to do the same task, how do you actually know which one did a better job? Not vibes. Not "this one feels smarter." Something measurable.

That became [Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon) — a skill that pits up to 14 AI models against each other in tournament elimination. Sealed judges, ELO ratings, evolution between rounds.

## Then came the measuring stick

Running hackathons surfaced a new problem: the judges needed a consistent way to evaluate quality. This was after I discovered that models were giving preference to their model families when judging. This discovery led me to me to create [Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec) — a sealed-envelope testing protocol. You give two models the same task, score them blind, and let the numbers talk. No peeking at who wrote what until after the verdict. Quality isn't subjective when you have a rubric.

## Then the factory

Once I could score quality, I wanted to build things with that same rigor. That became [Dark Factory](https://github.com/DUBSOpenHub/dark-factory) — an agentic build system where 6 specialist agents work through a checkpoint-gated pipeline, and a sealed test suite judges the output without the builders ever seeing the acceptance criteria. Shadow Score built into the build process.

## Then the scan visor

Dark Factory builds things, but how do you know the agents themselves are well-constructed? That led to [Agent X-Ray](https://github.com/DUBSOpenHub/agent-xray) — a scanner that reads any agent prompt and scores it across 6 dimensions. Think of it as a health check for your AI agents before you send them on a mission.

## The "what if" moment

But Havoc Hackathon has a constraint: every contestant runs as a sub-agent inside the same session. The orchestrator dispatches them, collects results, and scores them. They each get their own context, but they're managed processes — the orchestrator is the bottleneck, and contestants can't interact with the repo the way a real developer would (reading files, editing code, running tests, iterating on failures).

I was watching a hackathon run with competing models to build a multi-agent framework (meta, I know) — and I thought: what if each contestant had its own terminal? Not a managed sub-agent, but a completely independent CLI session with its own working memory, its own tool access, its own ability to read files, edit code, and run tests.

I already had the pieces. Copilot CLI supports custom agents (`--agent`). tmux can split a terminal into arbitrary panes. Filesystems are already message queues if you squint. And the same architecture would work with any CLI coding agent.

## The prototype

The idea was simple:

1. Write task descriptions as JSON files in a `queue/` folder
2. Spin up N tmux panes, each running a CLI agent session
3. Each agent grabs a task file by renaming it (atomic, race-safe)
4. Agent does the actual work on its own git branch
5. Agent drops a result file when done
6. An orchestrator polls for results and synthesizes

No server. No database. No framework. Just files and terminals.

I had a hackathon's contestants build it. Eight models, three files each, two elimination rounds. Then I synthesized the best elements from the top two finalists into a working prototype.

## What I learned by running it

The first few launches were rough. Agents would start but not claim tasks. The autopilot flag only works in prompt mode (`-p`), not interactive mode (`-i`) — a subtle CLI distinction that cost me three debug cycles. Agents would sometimes finish but not write a result because they hit the autopilot continuation cap. The orchestrator couldn't tell if an agent was thinking or dead.

Each failure mode had the same fix: keep it simple. PID checks instead of heartbeats. Generation counters instead of dedup logic. Atomic file renames instead of lock files. Every time I reached for complexity, the filesystem already had the answer. The simpler the system, the more reliable the output.

The moment it clicked: I launched 8 agents on [ghost-ops](https://github.com/DUBSOpenHub/ghost-ops), my autonomous daemon project. Panes lit up, each with a gold ⚡ border showing the model and task. One agent was adding error handling to the watchdog module. Another was writing integration tests. Another was improving the ELO router. All simultaneously. All on their own git branches. All finishing while I watched.

Doing those same tasks one at a time would have meant sitting through each one sequentially, context-switching between them, losing momentum. Instead, every task ran in parallel and my wait time was just the longest single task, not the sum of all of them.

## What this connects to

Each tool I'd built before turned out to solve a piece of the same problem:

- **[Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon)** maintains an ELO leaderboard across 15 models. Stampede uses that same idea — shadow-scoring every model's work across runs to build an empirical leaderboard for *your* codebase.
- **[Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec)** measures output quality. Stampede bakes it into the runtime — quality criteria are defined before agents run, measured silently after. The agents never know they're being scored.
- **[Dark Factory](https://github.com/DUBSOpenHub/dark-factory)** builds production code through a checkpoint pipeline. Stampede could parallelize the build phases.
- **[Agent X-Ray](https://github.com/DUBSOpenHub/agent-xray)** scans agents and scores their quality. Stampede could use those scores to decide which agents to deploy.
- **[Ghost Ops](https://github.com/DUBSOpenHub/ghost-ops)** runs autonomous missions on a schedule. Stampede could be a mission type — "every morning at 6am, dispatch 20 agents to sweep the codebase."

These aren't integrated yet — they're just experiments that turned out to be adjacent. But the shadow scoring and model leaderboard are already built into Stampede. Every run answers the question: which AI model is actually best for your codebase? Not from vendor benchmarks. Not from synthetic tests. From real work on your real repo.

## What I'm still figuring out

This is an experiment, not a product. Things I don't know yet:

**Does the quality hold up?** Twenty fast agents might produce twenty mediocre results. I haven't done rigorous quality comparison between "one powerful session doing all tasks carefully" versus "many lightweight sessions doing 1 task each quickly." That's a Shadow Score experiment waiting to happen.

**How far does the filesystem queue scale?** For 8-20 agents it's fine. For 100? Probably not. But 100 parallel AI agents on one repo is a problem I'm happy to have later.

## The insight I keep coming back to

Every multi-agent framework I've seen treats agents as function calls. They're threads in a process, sharing memory, sharing an API connection, taking turns. That's concurrency.

Terminal Stampede treats agents as developers. Each one gets a desk (tmux pane), a full copy of the project (their own context window), their own tools (bash, grep, edit), and a task written on a sticky note (JSON manifest). They work independently and drop their results in a shared folder when done. That's parallelism.

The distinction matters because the agent doesn't just think — it does. It reads code, edits files, runs tests, sees failures, and iterates. You can't do that well in a shared context. You need your own workspace.

And because every agent runs in a visible pane, you're not handing off control. You can watch them work, zoom into any pane, type into it, or just walk away. Most multi-agent systems give you logs when it's over. This one puts you in the room while it's happening.

The architecture is tool-agnostic. It was built with GitHub Copilot CLI, but the pattern works with any CLI agent that can take a prompt and write code — Aider, Claude Code, or whatever comes next. The runtime is tmux and the filesystem. Everything else is swappable.

## We pointed it at itself

To test it, we pointed stampede at its own repo. 8 agents ran simultaneously on the terminal-stampede codebase — adding error handling, creating docs, improving the agent prompts, updating the changelog. Nobody touched anything. They just ran.

8/8 success. ~6 minutes. Zero coordination failures. ~800 lines of real changes across 8 branches. The simplest possible architecture was also the most reliable. No frameworks, no servers, no message brokers. Just files on disk and terminals.

The terminal was already the agent runtime. I just needed 20 of them.

---

*Built during a [Havoc Hackathon](https://github.com/DUBSOpenHub/havoc-hackathon). Tested on [ghost-ops](https://github.com/DUBSOpenHub/ghost-ops) and itself. Code at [terminal-stampede](https://github.com/DUBSOpenHub/terminal-stampede).*
