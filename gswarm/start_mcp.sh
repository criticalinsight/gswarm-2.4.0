#!/bin/bash
# Start the Gswarm MCP Sidecar (Tidewave)
# This bridge allows AI Agents (like Cursor/Windsurf) to talk to the running Gswarm node.

# Ensure we are in the right directory
cd "$(dirname "$0")/gswarm_mcp"

# Set the node name to match the one in start_efficient.sh
# start_efficient.sh uses -sname gswarm
# So we need to connect to it using the same cookie (default ~/.erlang.cookie)

echo "🌊 Starting Tidewave MCP Sidecar..."
echo "🔌 Connecting to Gswarm node..."
echo "🚀 Listening on http://localhost:4001/tidewave/mcp"

# Run the mix project
elixir --sname gswarm_mcp -S mix run --no-halt
