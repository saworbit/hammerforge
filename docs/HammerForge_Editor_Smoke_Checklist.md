# HammerForge Editor Smoke Checklist

Last updated: April 12, 2026

This checklist covers the editor-only flows that are hard to validate in headless tests:
- tutorial banner startup before `LevelRoot` exists
- live dock/tab interaction while the tutorial is visible
- shortcut dialog behavior in the real dock
- prefab save + drag/drop + undo/redo
- subtract preview toggle in the viewport
- vertex editing: edge sub-mode, split, merge, wireframe overlay
- polygon tool: click vertices, close, extrude height, brush creation
- path tool: place waypoints, finalize, corridor + miter joint brushes, auto-stairs/railings/trim extras
- material browser: thumbnail grid, search, filters, favorites, hover preview, context menu
- texture picker: T key eyedropper for sampling face materials
- spawn system: validation debug overlay, Quick Play with missing/invalid spawn, Manage tab spawn controls
- context toolbar: floating toolbar shows/hides per selection, correct buttons per context
- command palette: search, fuzzy search, gray-out, action execution, Shift+?/F1/Ctrl+K toggle
- coach marks: first-use tool guides appear on tool activation, dismissal persistence
- operation replay: timeline display, hover details, replay undo/redo navigation
- example library: load examples, study annotations, search/filter
- convert selection to heightmap: brush selection → heightmap layer with terrain
- foliage & scatter: circle/spline preview, commit, clear, UI controls in Paint tab

## Prep

Reset HammerForge user prefs to a known state:

```bash
godot --headless -s res://tools/prepare_editor_smoke.gd --path .
```

To verify tutorial resume behavior instead of a fresh start:

```bash
godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --tutorial-step=3
```

Then open:

- `res://samples/hf_editor_smoke_start.tscn`

Enable the HammerForge plugin if it is not already enabled.

## Checklist

### 1. Fresh Tutorial Startup
- Open `hf_editor_smoke_start.tscn`.
- Confirm there is no `LevelRoot` in the scene tree yet.
- Confirm the HammerForge dock shows the tutorial immediately.
- Confirm the tutorial title, body text, and progress bar are populated.
- Confirm the four dock tabs remain visible and clickable while the tutorial is shown.
- Switch between `Brush`, `Paint`, `Entities`, and `Manage`; confirm the tutorial banner remains visible and the dock does not collapse or blank.

### 2. Late `LevelRoot` Hookup
- In the 3D viewport, create or trigger creation of `LevelRoot` using the normal plugin workflow.
- Confirm the tutorial remains on step 1 rather than resetting or disappearing.
- Confirm step 1 advances only after adding a brush, not merely because `LevelRoot` appeared.

### 3. Guided Step Flow
- Step 1: draw an additive room brush; confirm the tutorial advances.
- Step 2: draw a subtractive brush overlapping the room; confirm the tutorial advances only for subtraction.
- Step 3: switch to `Paint`, enable Paint Mode, and paint floor cells; confirm the tutorial advances.
- Step 4: switch to `Entities` and drag an entity into the viewport; confirm the tutorial advances.
- Step 5: switch to `Manage` and run Bake.
- Confirm `bake_finished(false)` does not complete the tutorial.
- Confirm only a successful bake completes the tutorial.
- Confirm the completion state auto-closes after the short delay.

### 4. Tutorial Resume
- Close Godot.
- Run `prepare_editor_smoke.gd` with `--tutorial-step=3`.
- Reopen `hf_editor_smoke_start.tscn`.
- Confirm the tutorial resumes at the saved step instead of restarting from step 1.

### 5. Shortcut Dialog
- Click the `?` shortcut button in the dock toolbar.
- Confirm the dialog opens at editor size without visual clipping.
- Type a filter such as `paint`; confirm only matching actions remain visible.
- Clear the filter; confirm categories repopulate correctly.
- Close the dialog with both Enter and Escape paths.

### 6. Prefab Save + Drag/Drop
- Select at least one brush or entity.
- In `Manage -> Prefabs`, save a prefab with a unique test name.
- Confirm the prefab list refreshes and the new item appears.
- Drag the prefab from the list into the 3D viewport.
- Confirm the prefab instances at the snapped placement point.
- If the prefab contains only entities, confirm the placement still succeeds.
- Undo the placement; confirm the full prefab placement is reverted.
- Redo the placement; confirm it is restored.

### 7. Subtract Preview
- Open `Manage -> Settings`.
- Toggle `Subtract Preview` on.
- Create an additive brush and a subtractive brush with real overlap.
- Confirm the red wireframe preview appears on the overlap volume.
- Move or resize either brush; confirm the preview updates.
- Toggle `Subtract Preview` off; confirm the wireframe is removed.

### 7b. Geometry Previews (Carve/Clip/Hollow)
- Select an additive brush overlapping another. Press Ctrl+Shift+R (Carve).
- Confirm **green wireframe** overlay appears showing the resulting slice pieces.
- Confirm a **confirmation dialog** appears ("Carve N brush(es)?").
- Click **Cancel**; confirm the preview disappears and no geometry changes.
- Repeat and click **OK**; confirm the carve executes and preview clears.
- Select a brush and press Shift+X (Clip).
- Confirm **cyan wireframe** for both halves and an **orange semi-transparent plane** at the split.
- Confirm a confirmation dialog appears. Cancel and verify nothing changes. OK and verify the split.
- Select a brush and press Ctrl+H (Hollow).
- Confirm **yellow wireframe** shows 6 wall pieces overlaid on the original brush.
- Confirm a confirmation dialog appears. Cancel and verify the original is unchanged.
- OK and confirm the brush is replaced by 6 wall brushes.

### 7b-2. Bulk Delete Confirmation
- Select 3+ brushes (marquee or Shift+click).
- Press Delete.
- Confirm a **confirmation dialog** appears ("Delete N brushes? This can be undone with Ctrl+Z.").
- Cancel; confirm nothing is deleted.
- Repeat and OK; confirm all selected brushes are deleted.
- Ctrl+Z; confirm all brushes are restored.
- Select 1-2 brushes and press Delete; confirm immediate deletion (no dialog).

### 7b-3. Carve UV Preservation
- Apply a distinct grid texture to a large additive brush.
- Place a smaller brush overlapping the textured brush.
- Carve (Ctrl+Shift+R) the small brush. Confirm in the dialog, then confirm the carver is deleted and the target splits into slice pieces.
- Inspect each surviving slice: confirm the grid texture is aligned with the original — no visible seams or jumps at slice boundaries.
- Undo the carve; confirm the original brush and carver are restored.

### 7c. Merge Brushes
- Create two box brushes with different materials, side by side.
- Select both brushes (Shift+click or marquee). Press **Ctrl+Shift+M** (or click "Mrg" in context toolbar).
- Confirm: originals deleted, one merged brush appears at the first brush's position with faces from both.
- Select the merged brush and bake; confirm both materials are visible on the baked mesh (no material loss).
- Undo; confirm both original brushes are restored with their materials.
- Create two brushes, rotate one 90 degrees, then merge. Confirm the rotated brush's geometry is correctly oriented in the merged result.
- Try merging a single brush; confirm an error toast appears ("Select at least 2 brushes").
- Try merging an additive brush with a subtractive brush; confirm rejection ("all brushes must have the same operation type").

### 7d. Face Winding Migration (Old Saves)
- Open a `.hflevel` file saved before the CW winding fix (April 6, 2026 or earlier).
- Confirm all brush faces render with textures visible from outside (not inside-out).
- Select a brush, enable Face Select Mode, and click each face — confirm the face normal gizmo (if visible) points outward.
- Bake the level; confirm baked geometry is textured correctly (not inside-out or black).
- Save the level. Re-open it; confirm faces still render correctly (migration should have written `winding_version: 1`).
- Create a new brush in the same level; confirm its faces also render correctly alongside the migrated ones.

### 8. Vertex Editing (Edge Sub-Mode)
- Select a brush and enter vertex mode (V key or the V toggle button in the toolbar).
- Confirm vertex crosses and edge wireframe lines appear on the brush.
- Click a vertex to select it (orange cross). Shift+click to multi-select.
- Drag to move vertices; confirm convexity enforcement (invalid moves revert).
- Press E to toggle to edge sub-mode; confirm edges become clickable.
- Click an edge; confirm it highlights orange and both endpoints are selected.
- Select a single edge and press Ctrl+E; confirm the edge is split (9 vertices on box).
- Undo the split; confirm 8 vertices return.
- Select 2 vertices and press Ctrl+W; confirm merge (or rejection if non-convex).
- Press E again to return to vertex sub-mode.

### 9. Polygon Tool
- Press P to activate the Polygon tool.
- Click 4+ points on the ground plane; confirm cyan outline preview appears.
- Confirm concave vertex placements are rejected (e.g. try to create an L-shape).
- Press Enter (or click near the first point) to close the polygon.
- Move mouse up/down to set height; confirm green vertical edges + top outline preview.
- Click to confirm; confirm a brush appears in DraftBrushes.
- Undo; confirm the brush is removed.
- Redo; confirm the brush returns.
- Press Escape during vertex placement; confirm last point is removed. Press again to cancel entirely.

### 10. Path Tool
- Press semicolon (;) to activate the Path tool.
- Click 3+ waypoints on the ground plane; confirm cyan polyline with width indicators.
- Press Enter to finalize the path.
- Confirm corridor brushes appear (one per segment + miter joints at corners).
- Confirm all brushes share a group (click one, all select).
- Undo; confirm all path brushes are removed in one step.
- Redo; confirm they return.
- Test with only 2 waypoints (straight corridor, no miters).
- Press Escape during waypoint placement; confirm last waypoint is removed.

### 11. Material Browser + Texture Picker
- Open the **Paint** tab → **Materials** section.
- Click **Refresh Prototypes**; confirm the thumbnail grid populates with 150 texture previews.
- Type "brick" in the search bar; confirm the grid filters to brick-pattern materials only.
- Click a color swatch (e.g. red); confirm only red materials remain. Click "All" to reset.
- Select the "Favorites" view toggle; confirm it is empty initially.
- Right-click a thumbnail → "Toggle Favorite"; switch to Favorites view and confirm the item appears.
- Switch back to "Prototypes" view. Click a thumbnail to select a material.
- With a brush selected (but no faces), **double-click** a thumbnail; confirm all faces of the selected brush(es) update (whole-brush fallback).
- With **no brush or face selected**, double-click a thumbnail; confirm a toast "No brushes selected — select a brush first".
- Enable **Face Select Mode**, click a face on a brush, then double-click a thumbnail or click **Assign to Selected Faces**; confirm only the selected face material changes.
- Hover a different thumbnail in the grid; confirm the selected face temporarily previews that material. Move the mouse away; confirm the preview reverts.
- Right-click a thumbnail → "Apply to Whole Brush"; confirm all faces of the selected brush(es) update.
- Right-click a thumbnail → "Copy Name"; paste elsewhere to confirm clipboard content.
- Press **T** (Texture Picker); click a face in the viewport. Confirm the browser selection updates to match that face's material.
- Press **T** on a face with no material; confirm a toast message appears ("Face has no material assigned").
- **Reimport resilience**: select a brush, switch to the Paint tab, scroll through thumbnails (triggering any lazy texture reimport). Confirm the brush selection label in the dock footer still shows "Sel: 1 brush" — the selection must not be cleared by reimport.

### 12. Spawn System + Quick Play Validation
- Delete all `player_start` entities (or start with a fresh scene).
- Click **Quick Play**; confirm a toast warns "No player_start found — auto-creating default spawn".
- Confirm the playtest launches and the player spawns above the brush centroid.
- Stop the playtest. Move the auto-created `player_start` inside a solid brush.
- Click **Quick Play**; confirm a dialog appears listing "Spawn inside solid geometry".
- Click **Fix & Play**; confirm the spawn snaps to a valid floor position and playtest launches.
- Stop the playtest. Place `player_start` high above geometry (floating in space).
- Click **Quick Play**; confirm a warning dialog about floating/no floor.
- Click **Cancel**; confirm playtest does not launch and a "Quick Play cancelled" toast appears.
- Open **Manage → Spawn** section.
- Click **Validate Spawn**; confirm the debug overlay appears (capsule, floor ray, markers) for ~10 seconds.
- Check **Preview Spawn Debug**; confirm the overlay stays persistent.
- Uncheck **Preview Spawn Debug**; confirm the overlay is cleaned up.
- Place two `player_start` entities. Set `primary = true` on the second one via Entity Properties.
- Click **Quick Play**; confirm the player spawns at the primary-flagged entity (not the first one).
- Set `angle = 90` on the primary spawn; playtest and confirm the player faces 90 degrees rotated.

### 12a. Bake Optimizations + Quick Play Modes
- Select 2-3 brushes. Click **Bake Selected**; confirm only those brushes are baked and previously baked geometry is preserved (not replaced).
- Modify a brush (move/resize). Click **Bake Changed**; confirm only the modified brush is rebaked. Unmodified geometry stays intact.
- Set Preview Mode to **Wireframe**; click Bake. Confirm baked output renders as cyan wireframe overlay.
- Set Preview Mode to **Proxy**; click Bake. Confirm baked output renders as semi-transparent grey.
- Set Preview Mode back to **Full**; click Bake. Confirm normal material rendering resumes.
- Click **Check Bake Issues** on a clean level; confirm no issues reported.
- Create a brush with near-zero thickness (e.g. 0.01 on Y axis). Click **Check Bake Issues**; confirm a severity-2 "degenerate brush" issue appears.
- Create a subtract brush floating in empty space (not intersecting any additive). Click **Check Bake Issues**; confirm a severity-1 "floating subtract" warning.
- Import a legacy .map file with known vertex drift (or create two adjacent brushes with edges offset by ~0.005 units). Click **Check Bake Issues**; confirm a severity-1 "micro-gap" warning appears for the near-coincident cross-brush vertices.
- Enter vertex mode on a brush and drag a vertex slightly off-plane (quad with 4th vertex drifted ~0.05 on the normal axis). Click **Check Bake Issues**; confirm a severity-1 "non-planar" warning appears for that face.
- Check the **bake estimate label** updates after each bake (shows estimated time for next bake).
- Click **Play from Camera**; confirm the player spawns at the editor camera position with matching yaw. Stop playtest; confirm the spawn entity is back in its original position.
- Move the camera to an invalid position (inside geometry). Click **Play from Camera**; confirm the fix dialog appears and spawn is restored on cancel.
- Select a subset of brushes. Click **Play Selected Area**; confirm only the selected area is baked. Stop playtest; confirm the cordon returns to its previous state (enabled/disabled, original AABB).
- With cordon disabled, click **Play Selected Area**, then stop. Confirm cordon is still disabled afterward.

### 12b. Auto-Connectors (Terrain Bake)
- Create two paint layers at different Y heights (e.g. layer 0 at Y=0, layer 1 at Y=4). Paint adjacent cells so at least one cell in each layer borders the other.
- Open **Manage → Bake** section. Check **Auto Connectors**.
- Set Mode to **Ramp**. Click **Bake**. Confirm `AutoConnector_*` MeshInstance3D nodes appear in the baked output connecting the two height levels with sloped geometry.
- Undo the bake. Set Mode to **Stairs**, Step H to 0.5. Bake again. Confirm stair-step geometry appears instead of a smooth ramp.
- Set Mode to **Auto**. Bake. Confirm the system chooses ramps for small height differences and stairs for larger ones (threshold = step height).
- Set Width to 3. Bake. Confirm connectors are wider (3 cells).
- Uncheck **Auto Connectors**. Bake. Confirm no `AutoConnector_*` nodes appear.
- Select a subset of brushes. Click **Bake Selected**. Confirm no auto-connectors are generated (selection-only bakes skip connectors).
- With Auto Connectors enabled + NavMesh enabled, bake. Confirm both `AutoConnector_*` collision shapes and `BakedNavmesh` region exist, and navmesh uses STATIC_COLLIDERS parsed geometry type.

### 12c. Occluder Generation (Automated Culling)
- Draw 3-4 large brushes forming walls and a floor (total visible surface > 4 units²).
- Open **Manage → Bake** section. Check **Generate Occluders**. Leave Min Area at 4.0.
- Click **Bake**. In the Scene tree, expand `BakedGeometry` → confirm an `Occluders` node exists containing `Occluder_0`, `Occluder_1`, etc. (OccluderInstance3D nodes).
- Set Min Area to 10000. Bake again. Confirm the `Occluders` node is gone (all surfaces below threshold).
- Set Min Area back to 4.0 and bake with Chunk Size > 0 (default 32). Confirm occluders are still generated despite meshes being nested inside `BakedChunk_*` intermediary nodes.
- Uncheck **Generate Occluders**. Bake. Confirm no `Occluders` node appears.
- Re-enable Generate Occluders. Click **Check Bake Issues**. Confirm an "Occlusion: N occluders covering ~X%" info entry appears in the results.

### 13. Context Toolbar + Command Palette
- Select a brush in the viewport. Confirm the floating context toolbar appears at the top of the 3D viewport showing "1 brush" with Extrude/Hollow/Clip/Carve/Merge/Duplicate/Delete buttons.
- Select multiple brushes; confirm the label updates to "N brushes".
- Click the "Hol" button in the toolbar; confirm hollow executes on the selected brush.
- Click "Dup"; confirm a duplicate brush is created.
- Switch to Draw tool (D key). Confirm the toolbar shows shape buttons (Box/Cyl/Sph/Cone) and an "Add" toggle.
- Click the "Sub" toggle; confirm the operation mode switches to Subtract.
- Begin a drag (click+hold in viewport). Confirm the toolbar switches to "Drawing" context with live dimension display and X/Y/Z axis lock buttons.
- Right-click to cancel the drag. Confirm the toolbar returns to Draw idle context.
- Enable Face Select Mode. Select one or more faces. Confirm the toolbar shows face count, UV justify buttons, and "All" (Apply to Whole Brush) button.
- Click a justify button (e.g. "Fit"); confirm UV justify applies to selected faces.
- Click "Stretch"; confirm UVs fill 0..1 on both axes (non-uniform).
- Click "Tile" on a non-square face; confirm the shorter axis fills 0..1 and the longer axis tiles.
- Enter Vertex mode (V key). Confirm the toolbar shows Vtx/Edge/Merge/Split/Exit buttons.
- Click "Exit"; confirm vertex mode is deactivated.
- Select an entity (if available). Confirm the toolbar shows "1 entity" with I/O and Props buttons.
- Deselect all (Esc); confirm the toolbar hides when no context applies.
- Press **Shift+?** (or F1) in the 3D viewport. Confirm the command palette appears with a search field and categorized action list.
- Type "hollow" in the search; confirm only the Hollow action is visible.
- Clear the search; confirm all actions reappear.
- With no brush selected, confirm "Hollow", "Clip", "Carve" entries are grayed out.
- Select a brush; press **Shift+?** again. Confirm "Hollow" is now enabled (not grayed out).
- Click "Hollow" in the palette (or press Enter); confirm hollow executes and the palette closes.
- Press **Esc** while the palette is open; confirm it closes without executing anything.
- Toggle paint mode on; press **Shift+?**. Confirm paint tools (Bucket, Erase, Ramp, etc.) are now enabled.

### 14. Coach Marks (First-Use Tool Guides)
- Press **P** to activate the Polygon tool for the first time. Confirm a floating coach mark overlay appears with step-by-step instructions.
- Read the steps; confirm they describe the Polygon workflow (click vertices → close → set height → confirm).
- Click **Got it**; confirm the overlay dismisses.
- Press **P** again; confirm the coach mark reappears (since "Don't show again" was not checked).
- Press **P** once more, check **"Don't show again"**, and click **Got it**.
- Press **P** again; confirm the coach mark does NOT appear.
- Press **V** to enter Vertex mode; confirm a different coach mark appears (Vertex Editing guide).
- Press **Ctrl+H** (Hollow) with a brush selected; confirm the Hollow coach mark appears.
- Restart Godot. Press **P**; confirm the Polygon coach mark is still dismissed (persisted via user prefs).
- Reset by clearing `coach_dismissed_*` keys from `user://hammerforge_prefs.json`.

### 15. Operation Replay Timeline
- Press **Ctrl+Shift+T**; confirm the operation replay timeline appears (initially empty or with a "Hover an operation to see details" message).
- Draw a brush; confirm a "+" icon appears in the timeline.
- Delete the brush; confirm an "x" icon appears.
- Undo the delete; confirm the timeline still shows both operations.
- Hover an icon in the timeline; confirm the detail label shows the operation name and elapsed time (e.g. "Draw Brush (5s ago)").
- Click an icon, then click **Replay**; confirm the editor undoes/redoes to reach that point in history with a toast ("Replay: undid N steps" or "Replay: redid N steps").
- Draw several more brushes to accumulate 5+ timeline entries. Confirm the timeline scrolls horizontally.
- Press **Ctrl+Shift+T** again; confirm the timeline hides.

### 16. Command Palette Fuzzy Search
- Press **Ctrl+K**; confirm the command palette opens (same as Shift+? and F1).
- Type "hollow"; confirm exact match shows the Hollow action.
- Clear and type "hllow" (typo); confirm the "Did you mean: Hollow?" suggestion appears and the Hollow entry is visible.
- Clear and type "extrd"; confirm fuzzy matches for Extrude Up/Down appear.
- Press **Enter**; confirm the first fuzzy match executes.
- Press **Ctrl+K** again; type "zzzqq" (no match at all); confirm no entries and no suggestion shown.

### 17. Example Library
- Open **Manage** tab. Expand the **Examples** section (collapsed by default).
- Confirm 5 example cards are visible with titles, difficulty badges, and descriptions.
- Type "corridor" in the search bar; confirm only the "Corridor with Doorway" card is visible.
- Clear the search. Type "advanced"; confirm only the "Simple Arena" card is visible.
- Clear the search. Click **Study This** on "Simple Room"; confirm the annotation panel appears with numbered design notes.
- Click **Close** on the annotation panel; confirm it disappears.
- Click **Load** on "Simple Room"; confirm existing brushes are cleared and the example's brushes appear in the viewport at their correct positions (not piled at the origin).
- Click **Load** on "Jump Puzzle Platforms"; confirm the room brushes are cleared and platform brushes appear at staggered heights with a player_start entity.
- Undo is not supported for example loads (they bypass undo/redo). Confirm a toast "Loaded 'Jump Puzzle Platforms': N objects" appeared.

### 18. Convert Selection to Heightmap
- Draw 2-3 brushes at different heights.
- Select all brushes. Switch to Paint tab → Heightmap section.
- Click **Convert Selection → Heightmap**. Confirm a toast appears ("Converted N brushes to heightmap layer 'Converted Terrain'").
- Confirm the Paint layer dropdown now shows the new layer as active.
- Confirm terrain geometry appears in the viewport where the brushes were.

### 19. Foliage & Scatter
- In Paint tab → Foliage & Scatter section, click the mesh picker and select any `.tres` or `.obj` mesh.
- Set density to 2.0, radius to 5.0. Click **Preview**. Confirm dot instances appear in the viewport around the center of your selection.
- Change preview mode to Wireframe; click **Preview** again; confirm wireframe preview replaces dots.
- Click **Scatter** to commit. Confirm a toast appears ("Scattered N instances") and the preview is replaced by a permanent MultiMeshInstance3D.
- Click **Clear**. Confirm the preview node is removed from the viewport.
- Switch shape to Spline. Select 3+ nodes/brushes. Click **Preview**. Confirm scatter instances follow the path defined by the selected node positions.
- With only 1 node selected in Spline mode, click **Preview**. Confirm a warning toast appears and no preview is created.

### 20. Path Tool Extras
- Activate the Path tool (;). In the tool settings, set path_extra to **Stairs**.
- Place 2 waypoints at different Y heights (use grid snap or numeric input). Press Enter.
- Confirm step brushes are generated along the sloped segment.
- Undo. Change path_extra to **Railing**. Repeat the path. Confirm top rails and posts appear on both sides.
- Undo. Change path_extra to **Trim**. Repeat. Confirm edge strips appear alongside the path.

### 21. Measure Tool (Multi-Ruler)
- Press **M** to activate the Measure tool.
- Click two points in the viewport; confirm a ruler line appears with distance and dX/dY/dZ labels.
- Hold **Shift** and click a third point; confirm a second ruler chains from the last endpoint and an angle label appears at the shared vertex.
- Confirm up to 20 rulers can exist (draw several). Older rulers are evicted when the cap is reached.
- Right-click near a ruler; confirm it is set as snap reference (line turns white, HUD shows "Align: ON").
- Press **A**; confirm align mode toggles off.
- Press **Delete**; confirm the last ruler is removed.
- Press **Escape**; confirm all rulers are cleared.

### 22. Undo History Browser
- Open **Manage → History** section.
- Perform 3-4 operations (draw, delete, move). Confirm entries appear in the history browser with color-coded icons.
- Hover an entry; confirm an enlarged thumbnail preview appears.
- Double-click an older entry; confirm the editor undoes to that point in history.
- Click the **Undo** button in the history header; confirm it undoes one step. Click **Redo**; confirm it redoes.
- With nothing to undo, confirm the Undo button is disabled. With nothing to redo, confirm Redo is disabled.

### 23. Performance Monitor
- Open **Manage → Performance** section.
- Confirm it shows: Health label, Active Brushes (with ProgressBar), Entities, Vertices (est), Paint Memory, Bake Chunks, Last Bake, Rec. Chunk Size.
- Draw 5+ brushes; confirm the brush count and vertex estimate update.
- Create entities; confirm the entity count updates.
- With many brushes (>50), confirm the Health label turns yellow ("Consider Chunking").

### 24. Theme Sync
- Switch Godot to a light theme (Editor Settings → Interface → Theme → Base Color).
- Confirm all HammerForge panels (context toolbar, coach marks, toasts, command palette, operation replay) adapt to light colors.
- Switch back to dark theme; confirm panels revert to dark colors.

### 25. Export Playtest Build
- Open **Manage → Bake** section. Click **Export Playtest Build**.
- If no spawn exists, confirm a toast about auto-creating a default spawn, and confirm the spawn creation is undoable.
- Confirm the level bakes and a playtest scene launches.
- If entities have I/O connections, confirm the exported scene contains an `HFIODispatcher` child node.
- Stop the playtest. Undo; confirm the auto-created spawn is removed.

### 26. Displacement Surfaces
- Draw a box brush. Enter Face Select Mode, select a top face (quad).
- Open **Brush tab → Displacement** section. Set Power = 3. Click **Create**.
- Confirm the face becomes a subdivided grid (toast: "Displacement created (power 3)").
- Enable Paint Mode. Choose Paint Mode = Raise, Radius = 4, Strength = 1.
- Click and drag on the face. Confirm vertices rise under the brush.
- Switch to Paint Mode = Smooth. Paint over the raised area. Confirm it smooths out.
- Click **Noise**. Confirm the surface gets noisy (toast: "Noise applied to displacement").
- Click **Smooth**. Confirm the surface smooths out (toast: "Displacement smoothed").
- Change **Elevation** via the spinbox. Confirm the grid height changes.
- Click **Destroy**. Confirm the face reverts to a flat quad (toast: "Displacement removed").
- Undo (Ctrl+Z) and confirm the displacement reappears.

### 27. Edge Bevel and Face Inset
- Draw a box brush. Press V for Vertex mode, then E for Edge sub-mode.
- Click an edge to select it (should highlight orange).
- Open **Brush tab → Bevel** section. Set Segments = 3, Radius = 2.
- Click **Bevel Edge**. Confirm the sharp edge is replaced with 3 intermediate faces (toast: "Beveled 1 edge(s)").
- Undo; confirm the edge returns to normal.
- Switch to Face Select Mode. Select a face.
- In the **Bevel** section, set Inset = 2, Height = 0.
- Click **Inset Face**. Confirm the face shrinks inward with connecting side quads (toast: "Face inset applied").
- Set Inset to a very large value (larger than the face). Click **Inset Face**. Confirm error toast.
- Undo; confirm the face returns to normal.

### 28. I/O Runtime Signal Translation
- Create two entities (e.g. `button1` and `door1`).
- Wire an I/O connection: button1 output `OnPressed` → door1 input `Open`.
- Enable **Bake Wire I/O** in LevelRoot Inspector.
- Bake the level. Confirm the baked container has an `HFIODispatcher` child in the scene tree.
- Export a Playtest Build. Confirm the exported scene also contains an `HFIODispatcher` node.

### 29. Viewport Context Menu
- Select a brush. Press **Space**; confirm a context menu appears at the cursor with brush-specific items (Extrude Up, Extrude Down, Hollow, Clip, Carve, Duplicate, Delete).
- Hover over **Grid Snap**; confirm a submenu appears with snap values (1, 2, 4, 8, 16, 32, 64).
- Click a grid snap value (e.g. 8); confirm the dock's grid snap updates to 8.
- Enable Face Select Mode. Select a face. Press **Space**; confirm the menu shows UV operations instead of brush operations.
- Hover over **UV Operations**; confirm a submenu with Fit, Center, Stretch, Tile, etc.
- Deselect all. Switch to Draw tool. Press **Space**; confirm the menu shows shape and Add/Subtract items.
- Begin a drag (click+hold). Press **Space**; confirm the menu does NOT open (idle guard).
- Select an entity. Press **Space**; confirm entity-specific items appear (I/O Connect, Properties, etc.).
- Confirm **Highlight Connected** appears as a check item and toggles state when clicked.

### 30. Radial Menu
- Press **`` ` ``** (backtick) in the 3D viewport; confirm a radial pie menu appears centered at the cursor with 8 labeled sectors.
- Move the mouse into the "Box" sector; confirm it highlights.
- Move the mouse to a different sector; confirm the highlight follows.
- Move the mouse into the center dead zone; confirm no sector is highlighted.
- Move the mouse outside the outer ring; confirm no sector is highlighted.
- Left-click on a highlighted sector (e.g. "Measure"); confirm the action executes and the menu closes.
- Press **`` ` ``** again; confirm the menu reopens (reopen test).
- Press **Escape** while the menu is open; confirm it closes without executing.
- Press **`` ` ``** to open, then press **`` ` ``** again; confirm it toggles closed.
- Right-click while the menu is open; confirm it closes without executing.
- Open the radial while a drag is in progress; confirm it does NOT open (idle guard).

### 31. Quick Property Popups
- In the viewport, tap **G** twice quickly (G G); confirm a small popup appears at the cursor with a "Grid Snap" SpinBox showing the current snap value.
- Type a new value (e.g. 4) and press **Enter**; confirm the grid snap updates and the popup closes.
- Tap **G G** again; press **Escape**; confirm the popup closes without changing the value.
- Tap **G G** again; click somewhere outside the popup; confirm it dismisses (click consumed, no brush placed).
- Select a brush. Tap **B** twice (B B); confirm a popup appears with 3 SpinBoxes (X, Y, Z).
- Enable paint mode. Tap **R** twice (R R); confirm a popup appears with a "Paint Radius" SpinBox.

### 32. Brush Wireframe Color Coding
- Draw a new additive brush; confirm it has a **green** wireframe overlay and green-tinted fill.
- Change the brush operation to Subtract; confirm the wireframe changes to **red**.
- Tie the brush to `func_detail` (brush entity); confirm the wireframe/overlay shifts to **bright blue**.
- Tie to `trigger_once`; confirm **medium blue** overlay.
- Tie to `func_wall`; confirm **muted blue** overlay.
- Untie the brush; confirm it returns to green (additive) wireframe.
- Draw a brush with per-face materials; confirm the green wireframe tracks the geometry after face preview rebuild.

### 33. Grid Size Indicator and Hotkeys
- With LevelRoot active, confirm the shortcut HUD (top-right) shows "Grid: 16" (or current snap value).
- Change the grid snap via the dock SpinBox; confirm the HUD label updates and **flashes** briefly (yellow-white → fade).
- Press **`]`**; confirm the grid doubles (e.g. 16 → 32) and the HUD flashes.
- Press **`[`**; confirm the grid halves (e.g. 32 → 16) and the HUD flashes.
- Press **`[`** repeatedly until minimum (0.125); confirm it stops halving and displays "Grid: 0.125" exactly (not "0.13").
- Press **`]`** repeatedly until maximum (512); confirm it stops doubling.
- Double-tap **G G** to open quick-property popup; change value; confirm HUD updates with flash.
- Perform a state restore (undo a bulk operation); confirm the HUD picks up the restored grid snap.

### 34. Cleanup / Persistence
- Dismiss the tutorial with and without `Don't show again` checked.
- Restart Godot and confirm the `show_welcome` preference behaves as expected.
- Reopen the dock and confirm no layout corruption remains after closing the tutorial and shortcut dialog.

## Expected Outcome

If all steps pass, the remaining risk on the tutorial/prefab/shortcut/subtract-preview/vertex-editing/polygon/path/material-browser/spawn-system/context-toolbar/command-palette/terrain-scatter/measure-tool/history-browser/performance-monitor/theme-sync/export-playtest/displacement/bevel/auto-connectors/validation-weld-planarity/io-runtime/viewport-context-menu/radial-menu/quick-property/wireframe-colors/grid-indicator feature set is low and limited mainly to edge cases outside this smoke path.
