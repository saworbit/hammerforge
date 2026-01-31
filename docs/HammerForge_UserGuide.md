# HammerForge User Guide (MVP)

This guide explains how to use HammerForge inside the Godot 4.6 editor. It covers the current MVP features: drag-based brush creation, draft add/subtract operations, selection, and baking.

## Quick Start
1. Enable the plugin: **Project ▶ Project Settings ▶ Plugins ▶ HammerForge**.
2. Open any 3D scene.
3. Click in the 3D viewport to start drawing.
   - HammerForge auto-creates a `LevelRoot` if it does not exist.
4. (Optional) Click **Create Floor** in the dock for a temporary collidable surface.
5. Use **Apply Cuts** to commit staged Subtract brushes (Bake also applies them).
   - Carve results are visible after Bake.
   - Use **Commit Cuts** to bake and keep the carve while removing the cut shapes.

## What is LevelRoot (and why it’s required)
`LevelRoot` is the main container node that HammerForge uses to manage your level data. It is required because it:

- Hosts the **DraftBrushes** and **PendingCuts** containers where all editable brushes live.
- Stores **CommittedCuts** when Freeze Commit is enabled (hidden subtract brushes that can be restored).
- Tracks brushes for **selection**, **undo/redo**, and **cleanup**.
- Owns the **Baker** that builds a temporary CSG tree at bake time to create a static mesh + collision.
- Ensures all generated nodes are saved with the scene (ownership in the editor).
- Can start as a single node; child helpers are created automatically if missing.

You normally don’t need to add it manually — HammerForge will auto-create it the first time you click in the viewport.

## Dock Controls
Sections can be collapsed using the toggle button in each header.

**Tool**
- **Draw**: create new brushes by click-dragging.
- **Select**: select existing brushes by clicking them. Press Delete to remove.

**Paint Mode**
- When enabled, left-click applies the active material instead of selecting.

**Active Material**
- Opens a file dialog to pick a Material resource (.tres or .material).

**Mode**
- **Add**: creates solid geometry.
- **Subtract**: creates a pending cut shape that does not carve until applied (carve is visible after Bake).

**Shape Palette**
- Choose from Box, Cylinder, Sphere, Cone, Wedge, Pyramid, Prisms, Ellipsoid, Capsule, Torus, and Platonic solids. Mesh-based shapes scale to brush size.

**Sides**
- Appears for pyramids/prisms to control the number of sides.

**Size**
- SizeX/SizeY/SizeZ are used as defaults and for axis-lock thickness.

**Grid Snap**
- Sets the grid snapping increment (0 disables snap).

**Quick Snap**
- Preset snap buttons (1/2/4/8/16/32/64) synced with Grid Snap.

**Physics Layer**
- Selects a preset collision layer mask for baked geometry.

**Freeze Commit**
- Keeps committed cut shapes in a hidden container so you can restore them later.
  - If disabled, committed cuts are deleted after bake and cannot be reused in future bakes.

**Show HUD**
- Toggles the on-screen shortcut legend in the 3D viewport.

**Show Grid**
- Toggles the editor grid (off by default).

**Follow Grid**
- Toggles the grid follow mode (requires Show Grid).

**Quadrant View (Native)**
- Use Godot’s **View → Layout → 4 View** for Top/Front/Side/3D.

**Debug Logs**
- Prints HammerForge events to the Output dock for troubleshooting.

**Create Floor**
- Adds a temporary CSGBox floor under LevelRoot for easy raycast placement.

**Apply Cuts**
- Converts pending Subtract brushes into active cuts used during Bake.
  - Tip: create a cut, switch to **Select**, position it with gizmos, then **Apply Cuts**.

**Clear Pending Cuts**
- Removes all pending Subtract brushes without carving.

**Commit Cuts (Bake)**
- Applies pending cuts, bakes the mesh, and removes applied subtract brushes.
- Hides draft brushes so the baked result is clearly visible.
- Use this if you want the carve to remain even after deleting the cut shapes.
- To keep editing, re-enable visibility on `DraftBrushes` (and `PendingCuts` if needed).
- Subtract preview materials do not carry into the baked mesh.

**Restore Committed Cuts**
- Moves hidden committed cuts back into DraftBrushes so they can be edited again.

**Bake**
- Builds a temporary CSG tree from DraftBrushes and bakes a static mesh + collision.

**Status**
- Shows bake progress (e.g., "Baking..." or "Ready").

**Live Brushes**
- Shows the draft brush count with performance warning colors.

**History (beta)**
- Shows recent HammerForge actions.
- **Undo** / **Redo** buttons call the editor's undo stack.
- Some actions (like bake output) may not fully restore in undo yet.

## Shape Palette
HammerForge now uses a dynamic palette grid for shapes. Click a shape to make it active, then draw as normal.
Pyramids, prisms, and platonic solids use a lightweight line-mesh draft preview in the editor.

## Brush Creation (CAD-Style)
HammerForge uses a two-stage drag workflow:

1) **Base Drag**
   - Click and drag to define the base on the floor plane.

2) **Height Stage**
   - Release the mouse, then move up/down to set height.
   - Click again to commit the brush.
   - Moving the mouse **up** increases height; moving down decreases it.

### Modifier Keys
- **Shift**: forces the base to be square (X and Z equal).
- **Shift + Alt**: forces a cube (X, Y, Z equal).
- **Alt**: adjusts height only while dragging (base stays fixed).
- **Right-click**: cancels the current drag.
- **X/Y/Z**: axis locks while drawing (X or Z lock one axis, Y locks base size).

## Selection
1. Set **Tool = Select**.
2. Hover highlight shows the brush under the cursor.
3. Click a brush to select it. (If Paint Mode is enabled, clicks apply material instead.)
4. Shift-click to multi-select.
5. Press **Delete** to remove selected brushes.
6. Press **Ctrl+D** to duplicate selected brushes.
7. Use Ctrl+Arrow or Ctrl+PageUp/PageDown to nudge selected brushes by the grid size.
   - Ctrl+Arrow: X/Z move.
   - Ctrl+PageUp/PageDown: Y move.
8. Use the standard Godot transform gizmos (move/rotate/scale) on selected brushes.
9. Use the DraftBrush face handles (white circles) to resize; the yellow wireframe is only a guide.

## Material Painting (Paint Mode)
1. Click **Active Material** and pick a .tres or .material resource.
2. Enable **Paint Mode**.
3. Click brushes in the viewport to apply the active material.
4. Disable Paint Mode to return to selection.

## Subtract Tips
- Subtract brushes are staged until you click **Apply Cuts** (or Bake).
- Only overlapping areas will carve from Add brushes (visible after Bake).
- For clear results: add a large block first, then subtract smaller ones.
- Pending cuts appear as solid red geometry so you can position them before applying.
- Applied cuts are procedural; deleting them removes the carve unless you **Commit Cuts** (Bake).
- **Commit Cuts** hides draft brushes and leaves the baked mesh visible.
- If **Freeze Commit** is enabled, you can bring cuts back with **Restore Committed Cuts**.
- Subtract preview materials do not affect the baked mesh.

## Bake Output
When you press **Bake**, HammerForge builds a temporary CSG tree from DraftBrushes and creates:
- `BakedGeometry` (Node3D)
  - `MeshInstance3D` with the merged mesh
  - `StaticBody3D` with a trimesh collision shape (Add brushes only; Subtract brushes are excluded)

You can playtest with a CharacterBody3D or FPS controller after baking.

## Shortcut HUD
HammerForge can display a small on-screen cheat sheet inside the 3D viewport.

- Toggle it with **Show HUD** in the dock.
- The HUD is informational only; it does not change your active tool.
- It mirrors the main modifier keys and axis locks so new users can learn quickly.

## Quadrant Viewports (Native)
HammerForge now relies on Godot’s built-in multi-viewport layout.

Use **View → Layout → 4 View** in the editor to enable Top/Front/Side/3D.

## Dynamic Editor Grid
HammerForge adds a high-contrast editor-only grid plane for clearer placement.

- The grid is a shader-driven PlaneMesh for better performance than line meshes.
- It follows the active axis and can update as you move the mouse (toggleable).
- Snap spacing is tied directly to `grid_snap`.

### Grid Tuning (LevelRoot Inspector)
- `grid_visible`: show/hide the editor grid (default off).
- `grid_follow_brush`: keep the grid centered under the cursor (default off).
- `grid_plane_size`: size of the grid plane in world units.
- `grid_color`: tint/alpha for line visibility.
- `grid_major_line_frequency`: how often major lines appear (every 4 or 8 snaps).

## Troubleshooting
**No brushes appear**
- Make sure HammerForge is enabled.
- Select `LevelRoot` in the scene tree.
- Use **Create Floor** to ensure raycasts hit something.

**Subtract does nothing**
- Ensure your subtract brush overlaps an existing Add brush.
- Remember: carve results are visible after Bake.

**Dock not showing**
- Restart Godot after enabling the plugin.

**Can't drag the brush gizmo**
- Make sure a DraftBrush is selected.
- Drag the white circle handles (not the wireframe).
- Confirm the 3D viewport "Gizmos" toggle is enabled.

**Need diagnostics**
- Enable **Debug Logs** in the dock to print tool actions and bake/cut steps.

---

### Next Planned Features
- Numeric input during drag (exact sizing).
- Ortho views (Top/Front/Side).
- Per-face material tools and UV controls.
