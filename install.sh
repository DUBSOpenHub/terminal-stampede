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

# Install launcher
cp "$SCRIPT_DIR/bin/stampede.sh" "$BIN_DIR/stampede.sh"
chmod +x "$BIN_DIR/stampede.sh"
echo "  ✅ Launcher → $BIN_DIR/stampede.sh"

# Install monitor
cp "$SCRIPT_DIR/bin/stampede-monitor.sh" "$BIN_DIR/stampede-monitor.sh"
chmod +x "$BIN_DIR/stampede-monitor.sh"
echo "  ✅ Monitor → $BIN_DIR/stampede-monitor.sh"

# Check ~/bin is in PATH
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo ""
    echo "  ⚠️  ~/bin is not in your PATH. Add it:"
    echo "     echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc"
fi

echo ""
echo "🦬 Terminal Stampede installed!"
echo ""
echo "  Usage:"
echo "    stampede.sh --run-id run-YYYYMMDD-HHMMSS --count 8 --repo ~/your-project"
echo ""
echo "  Or in a Copilot CLI session:"
echo "    stampede 8 agents on ~/your-project"
