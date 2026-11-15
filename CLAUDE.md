# Game builder and designer manual

This repo holds a Godot 4 game in `game/` and two MCP servers that let Claude
build it: `godot` (scenes, nodes, running the project) and `blender` (modelling,
rigging, asset import). Follow this manual whenever a task touches the game.

## Setup state

- `bash tools/setup-mcp.sh` clones the servers into `tools/mcp-servers/` at
  pinned commits, builds them, and installs the Beehave add-on into
  `game/addons/beehave`. That directory is gitignored; re-run the script on a
  fresh checkout.
- `.mcp.json` registers both servers. `godot` needs a Godot 4 executable
  (`GODOT_PATH` or on `PATH`). `blender` needs Blender open with the
  "MCP for Blender" add-on running on `localhost:9876`.
- The server handshakes were tested in a cloud container with no Godot or
  Blender installed. The first task on a real machine is the connection check
  below; do not assume it passes.

### Connection check (run at the start of every session)

1. `godot` → `get_godot_version`. An error means `GODOT_PATH` is wrong.
2. `godot` → `get_project_info` with `projectPath` = absolute path of `game/`.
3. `blender` → `get_addon_status`. An error means Blender is closed or the
   add-on server is stopped (3D viewport → `N` → MCP for Blender → Start).

If a server is down, say so and stop. Do not fall back to hand-editing `.tscn`
files to imitate a tool that failed.

## MCP tools

### `godot` (Coding-Solo/godot-mcp, 14 tools)

Every project tool takes `projectPath` (absolute path to `game/`). Scene paths
are relative to the project, e.g. `scenes/levels/arena.tscn`.

| Tool | Use it for |
|---|---|
| `get_godot_version`, `get_project_info`, `list_projects` | Read-only checks. |
| `create_scene` (`scenePath`, `rootNodeType`) | New scene. Fails soft on an existing path; check first. |
| `add_node` (`scenePath`, `nodeType`, `nodeName`, `parentNodePath`, `properties`) | Add one node to a saved scene. |
| `save_scene` (`scenePath`, optional `newPath`) | Save, or save a variant under a new path. |
| `load_sprite` | 2D only: texture into a Sprite2D. |
| `export_mesh_library` | Turn a 3D scene of meshes into a MeshLibrary for GridMap. |
| `run_project`, `get_debug_output`, `stop_project` | Run the game, read errors and prints, stop it. |
| `launch_editor` | Open the editor for the user. Never needed for headless edits. |
| `get_uid`, `update_project_uids` | UID lookups and resave after moving files (Godot 4.4+). |

What this server cannot do: attach scripts, edit existing node properties,
delete nodes, bake navigation, or configure AnimationTrees. For those, write
GDScript or `.tres`/`.tscn` text with the normal file tools, then validate by
running the project. Prefer a `@tool` or one-off `--headless --script` GDScript
over hand-written `.tscn` for anything structural.

### `blender` (ahujasid/blender-mcp, 10 tools)

| Tool | Use it for |
|---|---|
| `get_addon_status` | Once per session. Shows Blender version and which asset sources and generators are on. |
| `get_scene_info` (`query`, `root`, `fields`, `limit`) | Read objects before changing anything. |
| `look` (`target`, `views`, `shading`) | Viewport renders. Use after every visible change. |
| `execute_blender_code` (`code`) | Run `bpy` Python. Small steps, print what you need. |
| `search_assets`, `import_asset` | Free libraries (e.g. Poly Haven) when enabled in the add-on. |
| `generate_3d`, `generate_gaussian_world` | AI generation. Only if `get_addon_status` shows a provider on; these can cost credits, so ask the user first. |
| `disable_telemetry` | Already off via `DISABLE_TELEMETRY=true` in `.mcp.json`. |
| `record_trajectory_feedback` | Do not call unless the user asks. |

`execute_blender_code` runs arbitrary Python inside the user's Blender. Never
use it for file deletion, network access, or anything outside the scene. Set
`BLENDER_MCP_SAFE_MODE=true` in `.mcp.json` to restrict scripts to `bpy`,
`bmesh`, `mathutils` and maths modules if the user wants a sandbox.

## Project layout

```
game/
  project.godot
  scenes/levels/        one .tscn per map
  scenes/characters/    player and NPC scenes
  scripts/ai/           behaviour-tree leaves, NPC controllers
  assets/characters/    .glb exports from Blender
  assets/environment/   level meshes, MeshLibraries
  addons/beehave/       installed by the setup script
```

Units are metres. A humanoid is about 1.8 tall. Physics layers: 1 world,
2 player, 3 npc. Navigation layer 1 is walkable.

## Map and level workflow

1. **Blockout.** `create_scene` with root `Node3D`. Add a `NavigationRegion3D`
   named `Nav`, and put all walkable geometry under it. Use `CSGBox3D` /
   `CSGCombiner3D` with `use_collision = true` for greybox floors, walls and
   ramps, or a `GridMap` fed by a MeshLibrary for modular kits.
2. **Scale check.** Doors at least 1.2 wide and 2.2 high, corridors at least
   2 wide, ramps at most 30 degrees, steps at most 0.3 high. These must agree
   with the NavigationMesh agent settings in the next step.
3. **NavMesh.** Give `Nav` a `NavigationMesh` resource: `agent_radius` 0.4,
   `agent_height` 1.8, `agent_max_climb` 0.3, `agent_max_slope` 35,
   `geometry_parsed_geometry_type` = static colliders. Bake with a script
   (`NavigationRegion3D.bake_navigation_mesh()`), since the MCP server has no
   bake tool. Re-bake after any geometry change.
4. **Spawn points.** `Marker3D` nodes under a `Spawns` node, in groups
   `player_spawn` and `npc_spawn`, placed 0.1 above the floor. Add patrol
   routes as `Marker3D` children of a `Patrols` node.
5. **Final geometry.** Replace greybox with Blender meshes exported as `.glb`
   into `assets/environment/`. Name collision meshes with the `-col` or
   `-colonly` suffix in Blender so Godot generates `StaticBody3D` on import.
6. **Validate.** All of these before calling a map done:
   - `run_project`, then `get_debug_output` shows no errors.
   - A script confirms the baked navmesh has polygons and that
     `NavigationServer3D.map_get_path` returns a non-empty path between every
     pair of spawn points.
   - A downward raycast from each spawn hits the world layer within 0.5.
   - No walkable mesh is missing a collider.

## Humanoid and NPC pipeline

1. **Mesh.** In order of preference: an asset the user supplies; a free CC0
   model through `search_assets` / `import_asset`; `generate_3d` if a provider
   is enabled and the user approved the cost; or a base mesh built with `bpy`.
   Mixamo and AccuRIG have no API. If the user wants either, ask them to upload
   the mesh there and drop the rigged FBX into `assets/characters/`.
2. **Rig in Blender.** Enable Rigify, add the Human meta-rig, scale it to the
   mesh, generate the rig, parent with automatic weights. Apply all transforms
   first. Check with `look` in a bent pose before exporting.
3. **Animations.** At minimum `idle`, `walk`, `run`, `attack`, `hit`, `die`
   as separate Actions, looping ones suffixed `-loop` so Godot loops them on
   import.
4. **Export.** glTF binary to `game/assets/characters/<name>.glb`: +Y up,
   apply modifiers, include only deform bones, all Actions. Target under
   20k triangles and one material per NPC.
5. **Character scene.** `CharacterBody3D` root (layer npc, mask world), with
   `CollisionShape3D` (capsule 0.4 x 1.8), the imported model, an
   `AnimationTree`, and a `NavigationAgent3D` whose radius and height match the
   navmesh agent. Use Godot's humanoid `BoneMap` retarget on import so
   animations are shareable across characters.
6. **Animation state machine.** `AnimationTree` with an
   `AnimationNodeStateMachine` root: a `locomotion` BlendSpace1D
   (idle/walk/run driven by speed), plus `attack`, `hit`, `die` states.
   Gameplay code only sets parameters and calls `travel()`; it never plays
   clips directly.
7. **Behaviour AI (Beehave).** Add a `BeehaveTree` under the NPC with a
   `Blackboard`. Standard combat tree: a selector over
   `die` → `attack if target in range` → `chase target` (sets
   `NavigationAgent3D.target_position`) → `patrol` → `idle`. Leaves live in
   `scripts/ai/` and extend `ActionLeaf` / `ConditionLeaf`. Perception is an
   `Area3D` for range plus a raycast for line of sight.
8. **Dialogue.** Default is authored dialogue in a resource file. For local
   LLM dialogue, install NobodyWho from the Godot Asset Library with a small
   GGUF model, give each NPC a fixed persona prompt and a short allowed-topic
   list, and keep the behaviour tree in charge of actions; the model only
   produces lines. LimboAI is an alternative to Beehave if the user wants a
   visual tree editor; it is also an Asset Library install.
9. **Test.** A `scenes/levels/npc_test.tscn` with a flat navmesh, one NPC and
   one target. Run it and confirm from debug output that the NPC reaches each
   state.

## Safety and verification guardrails

- **Read before write.** `get_project_info` or `get_scene_info` before any
  change, and state what will change.
- **Never overwrite silently.** Check whether a scene, `.glb` or `.blend`
  exists before writing to its path. For an existing file, save a variant
  (`save_scene` with `newPath`) or get the user's go-ahead.
- **Commit first.** Make sure `git status` is clean, or commit, before a
  structural change to a scene hierarchy, so it can be reverted. Blender files
  are not diffable: save a numbered copy before destructive mesh edits such as
  applying modifiers, decimating or joining.
- **Small steps.** One logical change per `execute_blender_code` call, then
  `look`. One batch of nodes, then `run_project` and `get_debug_output`.
- **Ask before heavy or costly work.** Navmesh bakes on large maps, lightmap
  bakes, high-poly generation, anything that calls a paid generator, and
  anything likely to run longer than a minute.
- **Stay inside the project.** No writes outside this repo, no deleting files
  through `bpy` or GDScript, no installing add-ons the user has not approved.
- **Always stop what you start.** Call `stop_project` after `run_project`.
- **Report honestly.** If a check in this manual was skipped or failed, say so
  in the summary.
