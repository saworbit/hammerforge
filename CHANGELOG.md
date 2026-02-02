# Changelog

All notable changes to this project will be documented in this file.
The format is based on "Keep a Changelog", and this project follows semantic versioning.

## [Unreleased]

### Added
- CAD-style brush creation: drag a base, then set height and commit with a second click.
- Modifier keys: Shift (square base), Shift+Alt (cube), Alt (height-only).
- Axis locks for drawing (X/Y/Z).
- Draw/Select tool toggle in the dock.
- Collapsible dock sections for Settings, Presets, and Actions.
- Physics layer presets for baked collision via dock dropdown.
- Live brush count indicator with performance warning colors.
- New SVG icon for LevelRoot in the scene tree.
- Paint Mode: pick an active material and click brushes to apply it in the viewport.
- Active material picker in the dock (resource file dialog for .tres/.material).
- Hover selection highlight (AABB wireframe) when using Select.
- Select tool now yields to built-in gizmos when a brush is already selected.
- Prefab factory for advanced shapes with dynamic shape palette.
- Added wedges, pyramids, prisms, cones, spheres, ellipsoids, capsules, torus, and platonic solids.
- Mesh prefab scaling now respects brush dimensions (capsule/torus/solids).
- Native 4-view layout guidance (uses Godot's built-in view layout).
- Multi-select (Shift-click), Delete to remove, Ctrl+D to duplicate.
- Nudge selected brushes with arrow keys and PageUp/PageDown.
- Auto-create `LevelRoot` on first click if missing.
- Create Floor button for quick raycast surface setup.
- Pending Subtract cuts with Apply/Clear controls (Bake auto-applies).
- Cylinder brushes, grid snap control, and colored Add/Subtract preview.
- Commit cuts improvements: multi-mesh bake, freeze/restore committed cuts, bake status, bake collision layer control.
- Viewport DraftBrush resize gizmo with face handles (undo/redo friendly).
- Gizmo snapping uses `grid_snap` during handle drags.
- Line-mesh draft previews for pyramids, prisms, and platonic solids.
- Chunked baking via `LevelRoot.bake_chunk_size` (default 32).
- Entities container (`LevelRoot/Entities`) and `is_entity` meta for selection-only nodes (excluded from bake).
- Entity definitions JSON loader (`res://addons/hammerforge/entities.json`).
- DraftEntity schema-driven properties with Inspector dropdowns (stored under `data/`, backward-compatible `entity_data/`).
- Create DraftEntity action button in the dock.
- Editor-only entity previews (billboards/meshes) driven by `entities.json`.
- Collision baking uses Add brushes only (Subtract brushes excluded).
- Playtest FPS controller with sprint, crouch, jump, head-bob, FOV stretch, and coyote time.
- Playtest button workflow: bake + launch current scene.
- Player start entity support (`entity_class = "player_start"`).
- Hot-reload signal for running playtests via `res://.hammerforge/reload.lock`.

### Fixed
- Selection picking now works for cylinders and rotated brushes.
- Height drag direction now matches mouse movement (up = taller).
- Guarded brush deletion to avoid "Remove Node(s)" errors.
- Dock instantiation issues caused by invalid parent paths.
- Commit cuts bake now neutralizes subtract materials so carved faces don't inherit the red preview.
- Playtest spawning now waits for runtime tree readiness to avoid transform warnings.
- Playtest now bakes before hiding draft geometry, so you can see brushes in-game.

### Documentation
- Added user guide and expanded LevelRoot explanation.
- Updated README, user guide, MVP guide, and spec for chunked baking and entity workflow.
