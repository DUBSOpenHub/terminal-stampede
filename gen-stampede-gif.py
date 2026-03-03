#!/usr/bin/env python3
"""Generate a compelling GIF of 8 AI agents coding simultaneously in tmux panes."""

import math
from PIL import Image, ImageDraw, ImageFont

# ── Dimensions ──
WIDTH, HEIGHT = 1200, 720
COLS, ROWS = 4, 2
BORDER = 2
GAP = 3
HEADER_H = 16
STATUS_H = 20
PANE_W = (WIDTH - GAP * (COLS + 1)) // COLS
PANE_H = (HEIGHT - STATUS_H - GAP * (ROWS + 1)) // ROWS
CHAR_W = 6.7  # Menlo 10px char width
MAX_CHARS = int((PANE_W - 36) / CHAR_W)  # Usable chars per line

# ── Colors ──
BG = (13, 17, 23)
PANE_BG = (22, 27, 34)
GOLD = (255, 196, 0)
GREEN = (63, 185, 80)
CYAN = (121, 192, 255)
PURPLE = (188, 140, 255)
ORANGE = (255, 166, 87)
RED = (255, 107, 107)
WHITE = (230, 237, 243)
GRAY = (139, 148, 158)
DIM = (72, 79, 88)
KW = (255, 123, 114)
ST = (165, 214, 130)
CM = (110, 118, 129)
FN = (210, 168, 255)
TY = (121, 192, 255)
NM = (255, 196, 0)

# ── Fonts ──
try:
    FONT = ImageFont.truetype("Menlo", 10)
    FONT_HDR = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 10)
except Exception:
    FONT = ImageFont.load_default()
    FONT_HDR = FONT


def L(*tokens):
    """Build a line from (color, text) pairs. Each line is a list of tokens."""
    return list(tokens)


# ── Code per agent: each line is a list of (color, text) tokens ──
# Lines are kept short enough to fit pane width (~35 chars)
AGENTS = [
    {
        "label": "Agent-1", "task": "error-handling", "color": ORANGE,
        "lines": [
            L((KW, "function "), (FN, "handleErr"), (WHITE, "(e, ctx) {")),
            L((KW, "  if "), (WHITE, "(e.status === "), (NM, "429"), (WHITE, ") {")),
            L((CM, "    // rate limit backoff")),
            L((KW, "    const "), (WHITE, "d = Math.min(")),
            L((NM, "      2"), (WHITE, "**ctx.retry * "), (NM, "1000"), (WHITE, ",")),
            L((NM, "      30000")),
            L((WHITE, "    );")),
            L((KW, "    return "), (FN, "retry"), (WHITE, "(ctx, d);")),
            L((WHITE, "  }")),
            L((KW, "  if "), (WHITE, "(e.status >= "), (NM, "500"), (WHITE, ") {")),
            L((FN, "    log"), (WHITE, ".error("), (ST, "'fail'"), (WHITE, ", {")),
            L((WHITE, "      status: e.status,")),
            L((WHITE, "      trace: e.stack,")),
            L((WHITE, "      run: ctx.runId")),
            L((WHITE, "    });")),
            L((KW, "    throw new "), (TY, "AgentError"), (WHITE, "(")),
            L((ST, "      `${ctx.id}: ${e.status}`")),
            L((WHITE, "    );")),
            L((WHITE, "  }")),
            L((KW, "  return "), (FN, "fallback"), (WHITE, "(ctx);")),
            L((WHITE, "}")),
        ],
    },
    {
        "label": "Agent-2", "task": "test-suite", "color": GREEN,
        "lines": [
            L((FN, "describe"), (WHITE, "("), (ST, "'TaskQueue'"), (WHITE, ", () => {")),
            L((FN, "  it"), (WHITE, "("), (ST, "'atomic claim'"), (WHITE, ", async () => {")),
            L((KW, "    const "), (WHITE, "q = "), (KW, "new "), (TY, "Queue"), (WHITE, "(d);")),
            L((KW, "    await "), (WHITE, "q."), (FN, "add"), (WHITE, "([")),
            L((WHITE, "      { id: "), (ST, "'t1'"), (WHITE, " },")),
            L((WHITE, "      { id: "), (ST, "'t2'"), (WHITE, " },")),
            L((WHITE, "    ]);")),
            L((CM, "    // race two workers")),
            L((KW, "    const "), (WHITE, "[a, b] = "), (KW, "await")),
            L((TY, "      Promise"), (WHITE, ".all([")),
            L((WHITE, "        q."), (FN, "claim"), (WHITE, "("), (ST, "'w1'"), (WHITE, "),")),
            L((WHITE, "        q."), (FN, "claim"), (WHITE, "("), (ST, "'w2'"), (WHITE, "),")),
            L((WHITE, "    ]);")),
            L((FN, "    expect"), (WHITE, "(a).not."), (FN, "toBe"), (WHITE, "(b);")),
            L((FN, "    expect"), (WHITE, "(q.size)."), (FN, "toBe"), (WHITE, "("), (NM, "0"), (WHITE, ");")),
            L((WHITE, "  });")),
            L(),
            L((FN, "  it"), (WHITE, "("), (ST, "'handles empty'"), (WHITE, ", () => {")),
            L((KW, "    const "), (WHITE, "q = "), (KW, "new "), (TY, "Queue"), (WHITE, "(d);")),
            L((FN, "    expect"), (WHITE, "(q."), (FN, "claim"), (WHITE, "("), (ST, "'w'"), (WHITE, "))")),
            L((WHITE, "      ."), (FN, "toBeNull"), (WHITE, "();")),
            L((WHITE, "  });")),
            L((WHITE, "});")),
        ],
    },
    {
        "label": "Agent-3", "task": "architecture-docs", "color": CYAN,
        "lines": [
            L((CM, "## Architecture")),
            L(),
            L((WHITE, "Each agent runs in its own")),
            L((WHITE, "tmux pane with 200K tokens.")),
            L(),
            L((CM, "### Filesystem Bus")),
            L(),
            L((DIM, "```")),
            L((WHITE, ".stampede/{run}/")),
            L((WHITE, "  queue/     # pending")),
            L((WHITE, "  claimed/   # in-progress")),
            L((WHITE, "  results/   # completed")),
            L((WHITE, "  merged/    # final")),
            L((DIM, "```")),
            L(),
            L((WHITE, "Atomic `mv` prevents races.")),
            L((WHITE, "No locks. No servers.")),
            L(),
            L((CM, "### Branch Strategy")),
            L(),
            L((WHITE, "One branch per agent.")),
            L((WHITE, "AI merger resolves conflicts.")),
            L((WHITE, "Shadow scores rank quality.")),
        ],
    },
    {
        "label": "Agent-4", "task": "cli-parser", "color": PURPLE,
        "lines": [
            L((KW, "def "), (FN, "parse_args"), (WHITE, "(argv):")),
            L((ST, '    """Parse stampede CLI."""')),
            L((WHITE, "    p = "), (TY, "ArgParser"), (WHITE, "(")),
            L((WHITE, "        prog="), (ST, "'stampede'")),
            L((WHITE, "    )")),
            L((WHITE, "    p."), (FN, "add"), (WHITE, "(")),
            L((ST, "        '--agents'"), (WHITE, ",")),
            L((WHITE, "        type="), (TY, "int"), (WHITE, ",")),
            L((WHITE, "        default="), (NM, "8")),
            L((WHITE, "    )")),
            L((WHITE, "    p."), (FN, "add"), (WHITE, "(")),
            L((ST, "        '--model'"), (WHITE, ",")),
            L((WHITE, "        default="), (ST, "'haiku-4.5'"), (WHITE, ",")),
            L((WHITE, "        choices="), (TY, "MODELS")),
            L((WHITE, "    )")),
            L((WHITE, "    p."), (FN, "add"), (WHITE, "(")),
            L((ST, "        '--repo'"), (WHITE, ",")),
            L((WHITE, "        type="), (TY, "Path"), (WHITE, ",")),
            L((WHITE, "        required="), (KW, "True")),
            L((WHITE, "    )")),
            L((KW, "    return "), (WHITE, "p."), (FN, "parse"), (WHITE, "(argv)")),
        ],
    },
    {
        "label": "Agent-5", "task": "monitor-ui", "color": GOLD,
        "lines": [
            L((FN, "render_bar"), (WHITE, "() {")),
            L((KW, "  local "), (WHITE, "w=$(tput cols)")),
            L((KW, "  local "), (WHITE, "done=$1 total=$2")),
            L((KW, "  local "), (WHITE, "pct=$((done*100/total))")),
            L(),
            L((CM, "  # gold progress bar")),
            L((KW, "  local "), (WHITE, "fill=$((pct*w/100))")),
            L((KW, "  printf "), (ST, "'\\e[38;5;220m'")),
            L((KW, "  for "), (WHITE, "i in $(seq $fill)")),
            L((KW, "  do "), (FN, "printf "), (ST, "'\\u2588'")),
            L((KW, "  done")),
            L((KW, "  printf "), (ST, "'\\e[38;5;240m'")),
            L((KW, "  for "), (WHITE, "i in $(seq $((w-fill)))")),
            L((KW, "  do "), (FN, "printf "), (ST, "'\\u2591'")),
            L((KW, "  done")),
            L((KW, "  printf "), (ST, "\" ${pct}%%\\e[0m\"")),
            L((WHITE, "}")),
            L(),
            L((FN, "watch_fleet"), (WHITE, "() {")),
            L((KW, "  while "), (FN, "has_active"), (WHITE, "; "), (KW, "do")),
            L((FN, "    render_bar "), (WHITE, "$(count_done) $N")),
            L((KW, "    sleep "), (NM, "2")),
            L((KW, "  done")),
            L((WHITE, "}")),
        ],
    },
    {
        "label": "Agent-6", "task": "merge-engine", "color": RED,
        "lines": [
            L((KW, "async fn "), (FN, "merge"), (WHITE, "(")),
            L((WHITE, "    branches: "), (TY, "Vec"), (WHITE, "<"), (TY, "Branch"), (WHITE, ">,")),
            L((WHITE, "    target: &"), (TY, "str"), (WHITE, ",")),
            L((WHITE, ") -> "), (TY, "Result"), (WHITE, "<"), (TY, "Report"), (WHITE, "> {")),
            L((KW, "    let mut "), (WHITE, "rpt = "), (TY, "Report"), (WHITE, "::new();")),
            L(),
            L((KW, "    for "), (WHITE, "b "), (KW, "in "), (WHITE, "&branches {")),
            L((KW, "        match "), (FN, "git_merge"), (WHITE, "(b) {")),
            L((TY, "            Ok"), (WHITE, "(s) => {")),
            L((WHITE, "                rpt."), (FN, "success"), (WHITE, "(")),
            L((WHITE, "                    b, s.ins,")),
            L((WHITE, "                    s.del")),
            L((WHITE, "                );")),
            L((WHITE, "            }")),
            L((TY, "            Err"), (WHITE, "(e) => {")),
            L((KW, "                let "), (WHITE, "fix =")),
            L((FN, "                    ai_resolve"), (WHITE, "(&e)?;")),
            L((WHITE, "                rpt."), (FN, "conflict"), (WHITE, "(")),
            L((WHITE, "                    b, fix")),
            L((WHITE, "                );")),
            L((WHITE, "            }")),
            L((WHITE, "        }")),
            L((WHITE, "    }")),
            L((TY, "    Ok"), (WHITE, "(rpt)")),
            L((WHITE, "}")),
        ],
    },
    {
        "label": "Agent-7", "task": "security-scan", "color": GREEN,
        "lines": [
            L((KW, "class "), (TY, "SecurityAudit"), (WHITE, ":")),
            L((ST, '    """Scan for secrets."""')),
            L(),
            L((KW, "    def "), (FN, "scan"), (WHITE, "(self, run):")),
            L((KW, "        for "), (WHITE, "f "), (KW, "in "), (FN, "glob"), (WHITE, "(")),
            L((WHITE, "            run / "), (ST, "'results/*'")),
            L((WHITE, "        ):")),
            L((KW, "            with "), (FN, "open"), (WHITE, "(f) as h:")),
            L((WHITE, "                txt = h."), (FN, "read"), (WHITE, "()")),
            L(),
            L((KW, "            for "), (WHITE, "p "), (KW, "in "), (WHITE, "self."), (TY, "RULES"), (WHITE, ":")),
            L((KW, "                if "), (WHITE, "p."), (FN, "match"), (WHITE, "(txt):")),
            L((WHITE, "                    self."), (FN, "flag"), (WHITE, "(")),
            L((WHITE, "                        f.name,")),
            L((WHITE, "                        p.name,")),
            L((ST, "                        'critical'")),
            L((WHITE, "                    )")),
            L(),
            L((KW, "        return "), (WHITE, "self."), (FN, "report"), (WHITE, "()")),
            L(),
            L((KW, "    def "), (FN, "flag"), (WHITE, "(self, f, r, s):")),
            L((WHITE, "        self.issues."), (FN, "append"), (WHITE, "({")),
            L((WHITE, "            "), (ST, "'file'"), (WHITE, ": f,")),
            L((WHITE, "            "), (ST, "'severity'"), (WHITE, ": s")),
            L((WHITE, "        })")),
        ],
    },
    {
        "label": "Agent-8", "task": "changelog", "color": ORANGE,
        "lines": [
            L((CM, "# Changelog")),
            L(),
            L((CM, "## [1.2.0] - 2026-03-03")),
            L(),
            L((CM, "### Added")),
            L((WHITE, "- Model leaderboard tracking")),
            L((WHITE, "- Shadow scoring (3 layers)")),
            L((WHITE, "- AI conflict resolution")),
            L((WHITE, "- Cross-run comparison")),
            L(),
            L((CM, "### Changed")),
            L((WHITE, "- Atomic file rename for claims")),
            L((WHITE, "- Monitor refresh: 2s")),
            L((WHITE, "- Result cap: 500 words")),
            L(),
            L((CM, "### Fixed")),
            L((WHITE, "- Race in task claiming")),
            L((WHITE, "- Stuck agent detection")),
            L((WHITE, "- Branch cleanup on fail")),
            L(),
            L((CM, "## [1.1.0] - 2026-02-28")),
            L(),
            L((CM, "### Added")),
            L((WHITE, "- Fleet health monitoring")),
            L((WHITE, "- Auto-recovery for workers")),
        ],
    },
]

# ── Per-agent timing: (start_delay_frames, lines_per_frame) ──
TIMING = [
    (0, 0.55),   # Agent 1 - starts immediately
    (1, 0.50),   # Agent 2 - slight delay
    (0, 0.60),   # Agent 3 - fast
    (2, 0.45),   # Agent 4 - slow start
    (1, 0.52),   # Agent 5
    (2, 0.48),   # Agent 6
    (0, 0.58),   # Agent 7
    (1, 0.53),   # Agent 8
]


def pane_rect(col, row):
    x = GAP + col * (PANE_W + GAP)
    y = GAP + row * (PANE_H + GAP)
    return x, y, x + PANE_W, y + PANE_H


def visible_lines(agent_idx, frame):
    delay, speed = TIMING[agent_idx]
    raw = max(0, (frame - delay)) * speed
    total = len(AGENTS[agent_idx]["lines"])
    return min(int(raw) + 1, total)  # +1 so frame 0 already shows line 1


def agent_progress(agent_idx, frame):
    total = len(AGENTS[agent_idx]["lines"])
    vis = visible_lines(agent_idx, frame)
    return min(100, int(vis / total * 100))


def draw_frame(frame, total_frames):
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(img)
    line_h = 13
    max_vis = (PANE_H - HEADER_H - 12) // line_h

    for idx, agent in enumerate(AGENTS):
        col, row = idx % COLS, idx // COLS
        x1, y1, x2, y2 = pane_rect(col, row)
        pct = agent_progress(idx, frame)
        vis = visible_lines(idx, frame)
        total_lines = len(agent["lines"])
        done = vis >= total_lines

        # ── Border with glow ──
        if done:
            bc = GREEN
        else:
            pulse = int(15 * math.sin(frame * 0.4 + idx * 0.8))
            bc = tuple(min(255, max(0, c + pulse)) for c in agent["color"])

        # Glow layers
        for g in range(2, 0, -1):
            gc = tuple(max(0, c - 70 * g) for c in bc)
            draw.rectangle([x1 - g, y1 - g, x2 + g, y2 + g], outline=gc)
        draw.rectangle([x1, y1, x2, y2], outline=bc, width=BORDER)
        draw.rectangle([x1 + BORDER, y1 + BORDER, x2 - BORDER, y2 - BORDER], fill=PANE_BG)

        # ── Header ──
        hx, hy = x1 + BORDER + 1, y1 + BORDER + 1
        draw.rectangle([hx, hy, x2 - BORDER - 1, hy + HEADER_H], fill=(30, 36, 46))

        # Agent label (no emoji - use colored dot)
        draw.ellipse([hx + 4, hy + 4, hx + 12, hy + 12], fill=agent["color"])
        draw.text((hx + 16, hy + 2), agent["label"], fill=WHITE, font=FONT)
        draw.text((hx + 70, hy + 2), agent["task"], fill=GRAY, font=FONT)

        # Status
        sx = x2 - BORDER - 50
        if done:
            draw.text((sx, hy + 2), "done", fill=GREEN, font=FONT)
        else:
            # Mini progress bar
            bar_w = 30
            bar_x = sx
            bar_y = hy + 6
            filled = int(pct / 100 * bar_w)
            draw.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 4], fill=DIM)
            if filled > 0:
                draw.rectangle([bar_x, bar_y, bar_x + filled, bar_y + 4], fill=GOLD)

        # ── Code lines ──
        code_x = x1 + 6
        code_y0 = hy + HEADER_H + 4
        lines = agent["lines"]
        show = min(vis, len(lines))
        scroll = max(0, show - max_vis)

        for li in range(scroll, show):
            y = code_y0 + (li - scroll) * line_h
            if y + line_h > y2 - 4:
                break

            tokens = lines[li]
            if not tokens:
                continue

            # Line number
            draw.text((code_x, y), f"{li+1:>2}", fill=DIM, font=FONT)

            # Tokens
            tx = code_x + 20
            for color, text in tokens:
                # Clip text to pane
                avail = int((x2 - BORDER - 4 - tx) / CHAR_W)
                if avail <= 0:
                    break
                t = text[:avail]
                draw.text((tx, y), t, fill=color, font=FONT)
                tx += int(len(t) * CHAR_W)

            # Cursor on the last visible line (blink every other frame)
            if li == show - 1 and not done and frame % 2 == 0:
                draw.rectangle([tx + 1, y, tx + 6, y + 11], fill=GOLD)

    # ── Status bar ──
    sy = HEIGHT - STATUS_H
    draw.rectangle([0, sy, WIDTH, HEIGHT], fill=(20, 24, 30))
    # Thin gold line
    draw.line([(0, sy), (WIDTH, sy)], fill=(80, 65, 0), width=1)

    done_n = sum(1 for i in range(8) if agent_progress(i, frame) >= 100)
    elapsed = frame * 0.12

    draw.text((10, sy + 4), "terminal-stampede", fill=GOLD, font=FONT)
    draw.text((WIDTH // 2 - 55, sy + 4), f"{done_n}/8 agents complete", fill=WHITE, font=FONT)
    draw.text((WIDTH - 70, sy + 4), f"{elapsed:.1f}s", fill=GRAY, font=FONT)

    # Animated dots when not all done
    if done_n < 8:
        dots = "." * ((frame % 3) + 1)
        draw.text((WIDTH // 2 + 60, sy + 4), dots, fill=GOLD, font=FONT)

    return img


def main():
    total_frames = 55
    frames = []

    print("Generating stampede GIF frames...")
    for f in range(total_frames):
        frames.append(draw_frame(f, total_frames))

    # Hold final frame
    for _ in range(12):
        frames.append(frames[-1])

    output = "assets/stampede-agents.gif"
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=90,
        loop=0,
        optimize=True,
    )
    size_kb = __import__("os").path.getsize(output) // 1024
    print(f"Saved {output}  ({len(frames)} frames, {size_kb} KB)")


if __name__ == "__main__":
    main()
