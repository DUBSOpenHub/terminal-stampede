#!/usr/bin/env bash
set -euo pipefail

# Terminal Stampede Installer
# ⚡ 8 AI agents. One terminal. All at once.

echo "🦬 Installing Terminal Stampede..."
echo ""

# Paths
SKILL_DIR="$HOME/.copilot/skills/stampede"
AGENT_DIR="$HOME/.copilot/agents"
BIN_DIR="$HOME/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create directories
mkdir -p "$SKILL_DIR" "$AGENT_DIR" "$BIN_DIR"

# Install orchestrator skill
cp "$SCRIPT_DIR/skills/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "  ✅ Orchestrator skill → $SKILL_DIR/SKILL.md"

# Install worker agent
cp "$SCRIPT_DIR/agents/stampede-worker.agent.md" "$AGENT_DIR/stampede-worker.agent.md"
echo "  ✅ Agent → $AGENT_DIR/stampede-worker.agent.md"

# Install merger agent
cp "$SCRIPT_DIR/agents/stampede-merger.agent.md" "$AGENT_DIR/stampede-merger.agent.md"
echo "  ✅ Merger agent → $AGENT_DIR/stampede-merger.agent.md"

# Install launcher
cp "$SCRIPT_DIR/bin/stampede.sh" "$BIN_DIR/stampede.sh"
chmod +x "$BIN_DIR/stampede.sh"
echo "  ✅ Launcher → $BIN_DIR/stampede.sh"

# Install monitor
cp "$SCRIPT_DIR/bin/stampede-monitor.sh" "$BIN_DIR/stampede-monitor.sh"
chmod +x "$BIN_DIR/stampede-monitor.sh"
echo "  ✅ Monitor → $BIN_DIR/stampede-monitor.sh"

# Install merger script
cp "$SCRIPT_DIR/bin/stampede-merge.sh" "$BIN_DIR/stampede-merge.sh"
chmod +x "$BIN_DIR/stampede-merge.sh"
echo "  ✅ Merger → $BIN_DIR/stampede-merge.sh"

# Install demo
cp -f "$SCRIPT_DIR/bin/stampede-demo.sh" "$BIN_DIR/stampede-demo" 2>/dev/null || ln -sf "$SCRIPT_DIR/bin/stampede-demo.sh" "$BIN_DIR/stampede-demo"
chmod +x "$BIN_DIR/stampede-demo"
echo "  ✅ Demo → $BIN_DIR/stampede-demo"

# Check ~/bin is in PATH
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    export PATH="$HOME/bin:$PATH"
fi

echo ""
echo "🦬 Terminal Stampede installed!"
echo ""
echo "  Launching demo..."
echo ""
sleep 1

# Auto-launch the demo
exec "$BIN_DIR/stampede-demo"
