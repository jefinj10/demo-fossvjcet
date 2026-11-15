#!/usr/bin/env bash
# Clones and builds the MCP servers and Godot add-ons this project uses.
# Run from anywhere: bash tools/setup-mcp.sh   (on Windows use Git Bash)
# Needs: git, Node.js 18+, uv (https://docs.astral.sh/uv/). Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVERS="$ROOT/tools/mcp-servers"
mkdir -p "$SERVERS"

# name | url | pinned ref (commit or tag audited on 2026-11-15)
fetch() {
  local name="$1" url="$2" ref="$3" dir="$SERVERS/$1"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  git -C "$dir" fetch -q --depth 1 origin "$ref"
  git -C "$dir" checkout -q --detach FETCH_HEAD
  echo "ok  $name @ $(git -C "$dir" rev-parse --short HEAD)"
}

fetch godot-mcp   https://github.com/Coding-Solo/godot-mcp   1209744fad78f3998f98c7394fd0f6ef50da5281
fetch blender-mcp https://github.com/ahujasid/blender-mcp    b6a2ce30c14636a562b5549684d9db6fc01f29ab
fetch beehave     https://github.com/bitbrain/beehave        refs/tags/v2.9.3

# Build the Godot MCP server (TypeScript -> build/index.js).
(cd "$SERVERS/godot-mcp" && npm install --no-audit --no-fund >/dev/null)
echo "ok  godot-mcp built"

# Install the Beehave behaviour-tree add-on into the Godot project.
mkdir -p "$ROOT/game/addons"
rm -rf "$ROOT/game/addons/beehave"
cp -R "$SERVERS/beehave/addons/beehave" "$ROOT/game/addons/beehave"
echo "ok  beehave installed to game/addons/beehave"

cat <<'EOF'

Next steps on your machine:
  1. Install Godot 4.x and Blender, then set GODOT_PATH to the Godot executable
     if it is not on your PATH.
  2. Install the Blender add-on:  uvx --from tools/mcp-servers/blender-mcp mcp-for-blender install-addon
     Open Blender; the add-on starts its server on localhost:9876.
  3. Start Claude Code in this folder and approve the "godot" and "blender"
     servers from .mcp.json. Check them with /mcp.
  4. In Godot: Project > Project Settings > Plugins > enable Beehave.
EOF
