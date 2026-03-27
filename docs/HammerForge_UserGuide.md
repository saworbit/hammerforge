# HammerForge User Guide

Last updated: March 27, 2026

This guide covers the current HammerForge workflow in Godot 4.6: brush-based greyboxing, bake, entities, floor paint, and per-face materials/UVs.

## Quick Start
1. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
2. Open any 3D scene.
3. Click in the 3D viewport to auto-create `LevelRoot`.
4. Optional: Click Create Floor for a temporary collidable surface.
5. Draw brushes, then Bake for output geometry.

## LevelRoot
`LevelRoot` is required because it owns the containers and systems HammerForge uses:
- DraftBrushes, PendingCuts, CommittedCuts
- PaintLayers and Generated (floors/walls)
- Entities
- Baker and paint systems

If missing, HammerForge creates it automatically on first viewport click. LevelRoot stays active even when you select other scene nodes (sticky root discovery) -- you do not need to re-select it after clicking a camera, light, or other node.

## First-Run Tutorial
On first launch, an interactive tutorial wizard appears guiding you through 5 steps:

| Step | Goal | Trigger |
|------|------|---------|
| 1 | Draw your first room | Place any brush |
| 2 | Subtract a window | Place a brush with Subtract operation |
| 3 | Paint a floor | Paint cells on any layer |
| 4 | Place an entity | Drag or create an entity |
| 5 | Bake & preview | Run a bake |

Each step auto-advances when you complete the required action. A progress bar shows your position. You can skip individual steps or dismiss the entire tutorial. Progress persists across sessions — if you close the editor at step 3, it resumes there next time.

Check "Don't show again" when dismissing to hide it permanently. Reset by editing `user://hammerforge_prefs.json` and setting `"show_welcome": true` and `"tutorial_step": 0`.

## Dock Layout (4 tabs)
The dock has 4 tabs with collapsible sections for organized access to all controls. Each collapsible section has a visual separator and indented content; collapsed state persists across sessions. A "No LevelRoot" banner appears at the top when no root node is found.

### Mode Indicator
A colored banner between the toolbar and tabs always shows your current tool and gesture stage:
- **Draw** (blue) -- "Step 1/2: Draw base — 64 x 32 x 48" / "Step 2/2: Set height — 64 x 96 x 48" (live dimensions update as you drag)
- **Select** (green)
- **Extrude ▲** (green) / **Extrude ▼** (red) -- "Extruding..."
- **Paint** (orange)

When typing numeric input during a gesture, the value appears in brackets (e.g. "[64]").

### Toolbar
The compact toolbar shows icon + text labels (Draw, Select, Add, Sub, Paint, Ext Up, Ext Dn) with full descriptions in tooltips. A **?** button at the right end opens a searchable shortcut reference dialog where you can filter by action name or key binding.

### Brush tab
- **Toolbar**: Draw, Select, Add, Sub, Paint, Ext Up, Ext Dn (icon + text labels). Press **?** for searchable shortcuts dialog.
- **Shape**: choose from the palette. Sides for pyramids/prisms.
- **Size** X/Y/Z: defaults for new brushes.
- **Grid Snap**: snap increment with quick preset buttons (1, 2, 4, 8, 16, 32, 64).
- **Snap Modes**: G (Grid), V (Vertex — snap to brush corners), C (Center — snap to brush centers). Toggle independently; closest geometry within threshold beats grid snap.
- **Material**: active material picker.
- **Physics Layer**: collision layer for baked output.
- **Texture Lock**: UV alignment preserved on move/resize (enabled by default).
- **Selection Tools** (visible when brushes are selected):
  - Hollow (wall thickness spinner + button, Ctrl+H). Shows actionable error toast if thickness is too large.
  - Move to Floor (Ctrl+Shift+F) / Ceiling (Ctrl+Shift+C).
  - Tie/Untie brush entity class (populated from entity definitions).
  - Clip Selected (Shift+X). Shows actionable error toast if split position is invalid.
  - Carve (Ctrl+Shift+R): boolean-subtract from intersecting brushes.
  - Duplicate Array: count, X/Y/Z offset, Create/Remove Array buttons.

### Paint tab (collapsible sections)
- **Floor Paint**: Brush, Erase, Rect, Line, Bucket, Blend tools. Brush shape (Square/Circle), radius, and layer picker. Rename button ("R") for custom layer display names.
- **Heightmap**: Import PNG/EXR or Generate procedural noise. Height Scale and Layer Y spinboxes. **Sculpt tools**: Raise, Lower, Smooth, Flatten buttons with strength/radius/falloff spinboxes for interactive terrain editing.
- **Blend & Terrain**: Blend Strength, Blend Slot (B/C/D), and Terrain Slot A-D texture pickers with UV scales.
- **Regions**: Region Streaming enable, Region Size, Stream Radius, Show Region Grid, memory stats.
- **Materials**: Palette with Add/Remove/Load Prototypes. Face Select Mode toggle. Assign to Selected Faces. The **Load Prototypes** button batch-loads 150 built-in SVG textures (15 patterns x 10 colors) for quick greyboxing.
- **UV Editor**: Per-face UV editing with drag handles, Reset Projected UVs, and Justify grid (Fit, Center, Left, Right, Top, Bottom in 3×2 layout).
- **Surface Paint**: Paint Target (Floor/Surface), layers, texture picker, radius/strength.

### Entities tab
- Create DraftEntity button.
- Entity palette with drag-and-drop placement.
- **Entity Properties** (collapsible): auto-generated typed controls based on entity definition.
- **Entity I/O** (collapsible): Output, Target, Input, Parameter fields. Delay (seconds) and Fire Once checkbox. Add Output / Remove buttons and connection ItemList. Connections auto-refresh when selecting an entity. **Show I/O Lines** checkbox to visualize connections in the viewport (green=standard, orange=fire_once, yellow=selected).

### Manage tab (collapsible sections)
- **Bake**: Bake button, Dry Run, Validate Level/Fix. Options: Merge Meshes, Generate LODs, Lightmap UV2, Texel Size, Navmesh (cell size, agent height), Use Face Materials, Quick Play.
- **Actions**: Create Floor, Apply/Clear/Commit/Restore Cuts, Clear Brushes.
- **File**: Save/Load .hflevel, Import/Export .map (Classic Quake / Valve 220), Export .glb.
- **Presets**: Save/rename presets grid.
- **History**: History panel (beta).
- **Settings**: Show HUD, Show Grid, Follow Grid, Debug Logs, Autosave path/toggle, Settings Export/Import.
- **Performance**: Brush count, paint memory, chunk count, last bake time.
- **Visgroups & Groups**: Visgroup list with [V]/[H] toggle, New/Add Sel/Rem Sel/Delete, Group Sel/Ungroup.
- **Cordon**: Enable checkbox, min/max spinboxes, Set from Selection.
- **Prefabs**: Save current selection as a `.hfprefab` file. Browse and drag-from the prefab library to instantiate groups of brushes and entities at a new position.

### Toast Notifications
Transient notifications appear in the dock for important events:
- **Save/load/export** results (success or failure).
- **Bake** completion or errors.
- **Operation errors** with actionable hints (e.g. "Wall thickness 6 is too large — Use a thickness less than 5").
- **Reference cleanup** reports (e.g. "Removed 2 I/O connection(s) targeting deleted brush 'door1'").
- **Autosave failures** (also shown as a persistent red warning label).
- Notifications auto-fade after 4-8 seconds depending on severity (INFO, WARNING, ERROR).

### Context Hints
Each tab shows a contextual hint at the bottom guiding you through the workflow:
- Brush tab: "Click and drag in the viewport to draw your first brush" → "Try: Hollow, Clip, or Extrude"
- Paint tab: "Draw some brushes first, then paint them here"
- Entities tab: "Drag an entity from the palette into the viewport"
- Manage tab: "When ready, use Bake to convert brushes into final geometry"

### Viewport Contextual Hints
When you switch tools, a brief instruction hint appears in the viewport overlay:
- **Draw**: "Click to place corner → drag to set size → release for height"
- **Select**: "Click brush to select, Shift+click to multi-select, drag to move"
- **Extrude Up/Down**: "Click a face to start extruding upward/downward"
- **Paint Floor**: "Click cells to paint, Shift+click to erase"
- **Paint Surface**: "Click brush faces to apply material"

Hints auto-fade after 4 seconds. Once you dismiss a hint (by switching away), it won't appear again. Hint dismissal persists across sessions. To reset all hints, delete `user://hammerforge_prefs.json` or clear the `hints_dismissed` key.

### Subtract Preview
Enable **Subtract Preview** in Manage tab → Settings to see real-time wireframe overlays at the AABB intersection of additive and subtractive brushes. Red wireframe boxes show exactly where subtractive brushes will cut into additive geometry. The preview updates automatically when brushes are added, removed, or moved (with a 0.15s debounce for performance). This helps visualize the effect of subtract operations before baking.

### Status bar
- Shows current status ("Ready", "Baking...", errors in red, warnings in yellow).
- Errors auto-clear after 5 seconds, success messages after 3 seconds.
- Displays selection count ("Sel: N brushes") when brushes are selected, with a **clear (x)** button to deselect.
- Live brush count with color-coded performance warnings.
- Bake progress bar updates during chunked bakes.
- Performance panel shows active brushes, paint memory, bake chunks, and last bake time.
- **Autosave warning**: a red "Autosave failed!" label appears if a threaded save fails. Auto-hides after 30 seconds.

## Snap Modes
HammerForge supports three snap modes that can be combined:

| Mode | Button | Behavior |
|------|--------|----------|
| **Grid** | G | Snap to grid increments (default, always-on) |
| **Vertex** | V | Snap to the 8 corners of existing brushes |
| **Center** | C | Snap to the center point of existing brushes |

Toggle modes independently using the G/V/C buttons below the Grid Snap row in the Brush tab. When multiple modes are enabled, the closest candidate wins — a nearby brush corner will beat a farther grid point. The snap threshold (default 2.0 world units) determines how close you need to be to a geometry candidate for it to take effect.

**Tip:** Enable Vertex snap when aligning brushes edge-to-edge. Enable Center snap when centering a brush inside another.

## Undo/Redo
- All brush operations (draw, delete, nudge, resize, paint, hollow, clip) support undo/redo.
- **Command collation**: rapid repeated operations (nudging with arrow keys, resizing via gizmo, painting brushes) are merged into a single undo entry within a 1-second window. One undo press reverses the entire sequence.
- Multi-step operations (hollow, clip) use transactions for atomicity.

## Entity Definitions
Brush entity classes (func_detail, func_wall, trigger_once, trigger_multiple) and point entities are data-driven. Definitions are loaded from `entities.json` (if present) or fall back to built-in defaults.

To add custom entity types:
1. Create `res://addons/hammerforge/entities.json`.
2. Add entries with `classname`, `description`, `is_brush_entity`, and optional `color` and `properties`.
3. The dock entity palette and brush entity class dropdown will auto-populate from these definitions.

## Material Library
The material palette can be saved and loaded as a JSON library file:
- **Save**: preserves resource paths of all palette materials.
- **Load**: restores the palette from saved paths.
- **Usage tracking**: materials in use by brushes are tracked; `find_unused_materials()` identifies cleanup candidates.

## Prototype Textures
HammerForge includes 150 built-in SVG prototype textures organized as 15 patterns in 10 color variations. Click **Load Prototypes** in the Paint tab → Materials section to add them all to the palette. Patterns include solid, brick, checker, cross, diamond, dots, hex, stripes (diagonal/horizontal), triangles, zigzag, and directional arrows (up/down/left/right).

Open `docs/prototype_textures_preview.html` in a browser to browse all textures visually. For GDScript API usage, see `docs/HammerForge_Prototype_Textures.md`.

## Design Constraints (Summary)
- DraftBrush previews are lightweight. Final geometry comes from bake.
- Subtractive brushes are staged as Pending Cuts until applied.
- Floor paint is grid-based; heightmaps displace floors only.
- `.map` export/import is for blockouts and does not preserve per-face materials.

For details, see `docs/HammerForge_Design_Constraints.md`.

## Data Portability
- `.hflevel` is the source of truth for full-fidelity editing.
- `.map` exchange is limited to basic brushes and point entities.
- `.glb` export includes baked geometry only.

For full details, see `docs/HammerForge_Data_Portability.md`.

## Install + Upgrade
For install steps, upgrade guidance, and cache reset help, see `docs/HammerForge_Install_Upgrade.md`.

## Shortcut HUD
The on-screen shortcut overlay updates dynamically based on your current tool and mode. Toggle it via the Show HUD checkbox in the Manage tab → Settings section. It shows:

| Context | Shortcuts Shown |
|---------|----------------|
| Draw (idle) | Click+Drag, Shift/Alt modifiers, X/Y/Z axis lock, Ctrl+Scroll size, Ctrl+D, Delete |
| Draw (dragging base) | Shift: Square, Alt+Shift: Cube, Click: Height stage, Right-click: Cancel. Live dimensions shown in banner |
| Draw (adjusting height) | Mouse: Change height, Click: Confirm, Right-click: Cancel. Live dimensions shown in banner |
| Select | Click/Shift/Ctrl selection, Escape, Delete, Ctrl+D, Arrow nudge, Ctrl+H Hollow, Shift+X Clip, Ctrl+Shift+F/C Floor/Ceiling |
| Extrude Up/Down (idle) | Click face + drag, U/J tool switch, Right-click cancel |
| Extrude Up/Down (active) | Move mouse to set height, Release to confirm, Right-click cancel |
| Floor Paint | Click+Drag, B/E/R/L/K tool shortcuts |
| Surface Paint | Click+Drag, radius/strength info |

The HUD also shows current axis lock state (e.g. "[X Locked]").

## Customizable Keyboard Shortcuts

All keyboard shortcuts are data-driven and can be customized. The default bindings match the shortcuts shown throughout this guide.

**Default bindings:**

| Action | Default Key | Description |
|--------|-------------|-------------|
| Draw tool | D | Switch to Draw mode |
| Select tool | S | Switch to Select mode |
| Extrude Up | U | Switch to Extrude Up mode |
| Extrude Down | J | Switch to Extrude Down mode |
| Delete | Delete | Delete selected brushes |
| Duplicate | Ctrl+D | Duplicate selection |
| Group | Ctrl+G | Group selected brushes |
| Ungroup | Ctrl+U | Ungroup selection |
| Hollow | Ctrl+H | Convert brush to hollow room |
| Clip | Shift+X | Split brush along axis plane |
| Carve | Ctrl+Shift+R | Boolean-subtract from intersecting brushes |
| Move to Floor | Ctrl+Shift+F | Snap to nearest surface below |
| Move to Ceiling | Ctrl+Shift+C | Snap to nearest surface above |
| Measure | M | Ruler tool (click A, click B, shows distance) |
| Decal | N | Place decal on surface with live preview |
| Axis Lock X/Y/Z | X / Y / Z | Constrain to axis |
| Paint tools | B / E / R / L / K | Bucket / Erase / Ramp / Line / Blend |

**Rebinding:** Edit `user://hammerforge_keymap.json` (created on first run). Each entry maps an action name to `{"keycode": KEY_*, "ctrl": bool, "shift": bool, "alt": bool}`. Restart the plugin after editing.

**Toolbar labels** and **tooltips** update automatically from the keymap, so custom bindings are always reflected in the UI. Press the **?** button on the toolbar to open a searchable shortcut dialog showing all current keybindings grouped by category (Tools, Editing, Paint, Axis Lock).

## User Preferences

HammerForge stores cross-session preferences in `user://hammerforge_prefs.json`, separate from per-level settings.

Preferences include:
- Default grid snap size
- Autosave interval
- Recent file list (up to 10)
- Collapsed section states (which dock sections are expanded/collapsed)
- Last active tool
- HUD visibility
- Tutorial wizard visibility and progress step
- Dismissed viewport contextual hints

## Prefabs (Reusable Brush Groups)

Prefabs let you save a selection of brushes and entities as a reusable group and place copies anywhere in your level.

### Saving a Prefab
1. Select the brushes and/or entities you want to save.
2. Open Manage tab → Prefabs section.
3. Enter a name and click **Save as Prefab**.
4. The prefab is saved as a `.hfprefab` JSON file in `res://prefabs/`.

### Instantiating a Prefab
- Drag a prefab from the library list into the 3D viewport.
- The brushes and entities are placed at the drop position with new unique IDs.
- Entity I/O connections are automatically remapped to the new entity names.
- The operation supports undo/redo.

### What's Captured
- Brush geometry (shape, size, operation, material, transform relative to group centroid)
- Entity data (type, class, properties, I/O connections, transform relative to centroid)
- Brush IDs and group IDs are cleared on capture; new ones are assigned on instantiation.

### File Format
`.hfprefab` files are JSON with the same encoding as `.hflevel` (Vector3, Transform3D serialized via `HFLevelIO`). They are portable and can be shared between projects.

These persist across editor restarts. Per-level settings (cordon, texture lock, materials) remain in `.hflevel` files.

## Tool Availability (Poll System)

Some actions require specific conditions to run:
- **Hollow, Clip, Move to Floor/Ceiling** require at least one brush selected. When nothing is selected, these buttons are grayed out with an inline hint ("Select a brush to use these tools") visible in the Selection Tools section.
- **Face-dependent controls** (Assign to Selected Faces, UV editing) show "Enable Face Select Mode and click a face to edit" when no face is selected.
- **Extrude** requires a LevelRoot in the scene. In extrude mode, a semi-transparent face highlight (green for up, red for down) previews which face you'll select before clicking.
- **External tools** can define their own requirements via `can_activate()`.

The mode indicator banner always shows the current tool and gesture stage. The status bar shows selection count with a clear button.

## Brush Creation (CAD style)
1) Base drag: click and drag to define the base.
2) Height stage: release mouse, move up/down, click to commit.

Modifier keys
- Shift: square base.
- Shift + Alt: cube.
- Alt: height-only.
- X/Y/Z: axis locks (shown in HUD as "[X Locked]" etc.).
- Right-click: cancel.

General keyboard shortcuts
- Delete: remove selected brushes.
- Ctrl+D: duplicate selected brushes.
- Arrow keys: nudge selected brushes (XZ plane).
- PageUp/PageDown: nudge selected brushes (Y axis).
- Escape: clear selection.
- Ctrl+Scroll: adjust brush size.

Extrude shortcuts
- U: Extrude Up tool.
- J: Extrude Down tool.

Group shortcuts
- Ctrl+G: Group selected brushes/entities.
- Ctrl+U: Ungroup selected brushes/entities.

Paint tool shortcuts (active when Paint Mode is enabled)
- B: Brush tool.
- E: Erase tool.
- R: Rectangle tool.
- L: Line tool.
- K: Bucket fill tool.

## Visgroups (Visibility Groups)
Visgroups let you organize your map into logical groups and toggle their visibility.

1. Open the **Manage** tab in the dock.
2. Type a name in the Visgroup field and click **New** to create a visgroup.
3. Select brushes/entities in the viewport, then click **Add Sel** to add them to the visgroup.
4. Click the visgroup name in the list to toggle between **[V]** (visible) and **[H]** (hidden).

Notes:
- A node can belong to multiple visgroups. If ANY visgroup it belongs to is hidden, the node is hidden.
- Nodes not in any visgroup are always visible.
- Use **Rem Sel** to remove selected nodes from the visgroup, or **Delete** to remove the visgroup entirely.
- Visgroups persist in `.hflevel` saves and undo/redo state.

## Grouping
Groups let you persistently link brushes/entities so they select and move together.

1. Select the brushes/entities you want to group.
2. Press **Ctrl+G** (or click **Group Sel** in the Manage tab → Visgroups & Groups section).
3. Click any member of the group -- all members are selected automatically.
4. Press **Ctrl+U** (or click **Ungroup**) to dissolve the group.

Notes:
- Each node can belong to one group at a time.
- Groups persist in `.hflevel` saves and undo/redo state.

## Texture Lock
When Texture Lock is enabled, moving or resizing a brush automatically adjusts its face UVs so textures stay aligned.

1. Check **Texture Lock** in the Brush tab (enabled by default).
2. Move or resize brushes normally -- UV alignment is preserved.
3. Uncheck to disable (UVs will shift with transforms as before).

Notes:
- Works with PLANAR_X, PLANAR_Y, PLANAR_Z, and BOX_UV projections.
- CYLINDRICAL projection is not compensated (complex; future enhancement).
- Persists in `.hflevel` settings.

## Cordon (Partial Bake)
The cordon restricts bake output to an AABB region, useful for iterating on a specific area of a large map.

1. Open the **Manage** tab in the dock.
2. Check **Enable Cordon** to activate.
3. Set the min/max coordinates with the spinboxes, or select brushes and click **Set from Selection**.
4. A yellow wireframe shows the cordon bounds in the viewport.
5. Bake -- only brushes intersecting the cordon AABB are included.

Notes:
- Disable cordon to bake the entire map.
- Cordon settings persist in `.hflevel` saves.

## Extrude (Up / Down)
The Extrude tools let you extend an existing brush by clicking one of its faces and dragging to create a new brush.

1. Press **U** (Extrude Up) or **J** (Extrude Down), or click the toolbar buttons.
2. Move the mouse over brush faces -- a **semi-transparent hover highlight** shows which face you'll select (green for up, red for down).
3. Click on a brush face -- a semi-transparent preview appears.
4. Drag the mouse vertically to set the extrude height (grid-snapped). The mode indicator shows "Extruding..." with numeric input if you type.
5. Release the mouse to commit the new brush.

Notes
- **Extrude Up** shows a green preview; **Extrude Down** shows a red preview.
- The new brush inherits the source brush's material.
- The extruded brush is a standard DraftBrush (box) and works with Bake, materials, and undo/redo.
- Right-click cancels the extrude in progress.

## Floor Paint
1. Enable Paint Mode.
2. Open the **Paint** tab → **Floor Paint** section.
3. Choose tool, brush shape (Square or Circle), radius, and layer.
4. Paint in the viewport.

Notes
- **Brush Shape**: Square fills a full box of cells; Circle clips corners using Euclidean distance.
- Live preview updates while dragging.
- Bucket fills a contiguous region (click filled to erase).
- Generated geometry appears under `LevelRoot/Generated`.
- Generated flat floors/walls are DraftBrush nodes and are included in Bake.

### Region Streaming (Large Worlds)
Region streaming keeps large paint grids responsive by loading only nearby regions.
1. Enable **Streaming** in the Paint tab → Regions section.
2. Set **Region Size** (cells) and **Stream Radius** (regions).
3. Toggle **Show Region Grid** to visualize loaded regions.
4. Paint normally; regions auto-load around the cursor.

Notes
- Region data is saved to `.hfr` files in `<level>.hfregions/`.
- The `.hflevel` stores a region index and layer settings.

### Heightmap Terrain
Heightmaps add vertical displacement to painted floors:
1. Paint cells on a layer using Brush/Rect/Line/Bucket.
2. Click **Import** to load a PNG/EXR heightmap, or **Generate** for procedural noise.
3. Adjust **Height Scale** to control displacement amplitude.
4. Adjust **Layer Y** to set the base height of the layer.

When a layer has a heightmap, its floors are generated as displaced MeshInstance3D nodes (not DraftBrush). These live under `Generated/HeightmapFloors` and are baked directly (bypassing CSG) with trimesh collision shapes.

### Material Blending
The Blend tool paints per-cell material blend weights on filled cells:
1. Fill cells first (Brush/Rect/etc.).
2. Switch to the **Blend** tool.
3. Choose a **Blend Slot** (B/C/D).
4. Adjust **Blend Strength** (0.0-1.0) in the dock.
5. Paint over filled cells to set blend weights.

Blend weights drive a four-slot shader (`hf_blend.gdshader`). Slot A is the implicit base, while slots B/C/D are controlled by the blend map (RGB) sampled on the UV2 channel.

Terrain slots:
- Use **Slot A-D** texture pickers to assign textures for the terrain blend shader.
- **Slot Scale** controls per-slot UV tiling.

## Face Materials and UVs
1. Open the **Paint** tab → **Materials** section.
2. Click **Load Prototypes** to load all 150 built-in textures, or click `Add` to load a custom material resource (example: `materials/test_mat.tres`).
3. Enable `Face Select Mode`.
4. Use the Select tool and click faces in the viewport.
5. Click `Assign to Selected Faces`.

UV editing:
- Open the **Paint** tab → **UV Editor** section after selecting a face.
- Drag UV points to edit.
- Use `Reset Projected UVs` to regenerate UVs from projection.

Notes:
- Face data is stored per DraftBrush face.
- Materials and UVs persist in `.hflevel` saves.

## Surface Paint (3D)
1. Enable Paint Mode.
2. Open the **Paint** tab → **Surface Paint** section and set `Paint Target = Surface` (if needed).
3. Pick a layer and assign a texture.
4. Paint in the viewport.

Notes:
- Radius is in UV space (0.0 to 1.0).
- Surface paint updates the DraftBrush preview immediately.
- Surface paint is separate from floor paint layers.
- If paint affects the floor, set `Paint Target = Surface` in the Surface Paint section.

## Entities (early)
- Place nodes under `LevelRoot/Entities` or set meta `is_entity = true`.
- Entities are selectable and excluded from bake.
- Entity palette supports drag-and-drop placement.

Entity definitions live in `res://addons/hammerforge/entities.json`.
Example (billboard preview):

```json
{
  "light_point": {
    "class": "OmniLight3D",
    "preview": {
      "type": "billboard",
      "path": "res://addons/hammerforge/icon.png",
      "color": "#ffff00"
    },
    "properties": [
      {"name": "range", "type": "float", "default": 10.0},
      {"name": "energy", "type": "float", "default": 1.0},
      {"name": "color", "type": "color", "default": "#ffffff"}
    ]
  }
}
```

## Bake Output
Bake creates `BakedGeometry`:
- If chunked baking is enabled, it adds `BakedChunk_x_y_z` nodes.
- Each chunk has a MeshInstance3D and StaticBody3D (trimesh) for collision.

Generated flat floor paint brushes are included in the CSG bake. Heightmap floor meshes are duplicated directly into the baked output with trimesh collision shapes (they bypass CSG since they are already ArrayMesh).

Use Face Materials (optional):
- Enables per-face material baking without CSG.
- Subtract brushes are ignored in this mode.

## Save/Load (.hflevel)
- Save .hflevel stores brushes, entities, settings, materials palette, face data, and paint layers.
- Paint layer data includes per-chunk `material_ids`, `blend_weights` (+ _2/_3), optional `heightmap_b64`, `height_scale`, and terrain slot settings.
- Load .hflevel restores them. Missing heightmap/material fields default to zero (backward-compatible).
- Autosave can write to a configurable path.

## Capturing Exit-Time Errors
PowerShell command:

```powershell
Start-Process -FilePath "C:\Godot\Godot_v4.6-stable_win64.exe" `
  -ArgumentList '--editor','--path','C:\hammerforge' `
  -RedirectStandardOutput "C:\Godot\godot_stdout.log" `
  -RedirectStandardError "C:\Godot\godot_stderr.log" `
  -NoNewWindow
```

## Troubleshooting
No brushes appear
- Ensure HammerForge is enabled.
- Select LevelRoot.
- Use Create Floor so raycasts hit something.

Subtract does nothing
- Subtract only affects Add brushes and is visible after Bake.
- Pending cuts appear in bright orange-red; once applied they turn standard red.

Paint preview looks wrong
- Regenerate by deleting `LevelRoot/Generated` and paint again.

Dock not showing
- Restart Godot after enabling the plugin.

Face selection not working
- Enable Face Select Mode in the Paint tab → Materials section.
- Use the Select tool (not Draw).

Material fails to load
- Material `.tres` files must not have a UTF-8 BOM. If Godot reports "Expected '['" on a `.tres` file, re-save it without BOM (or create a fresh one via FileSystem -> New Resource -> StandardMaterial3D).

Heightmap mesh not appearing
- Ensure the active layer has a heightmap assigned (use Import or Generate in the Paint tab → Heightmap section).
- Confirm cells are painted first -- heightmap only displaces filled cells.

Blend shader shows only one slot
- Paint blend weights using the Blend tool on already-filled cells.
- Set a Blend Slot (B/C/D) and assign textures to Slot A-D.
- Verify the blend_map texture is generated (requires cells with non-zero blend weights).
