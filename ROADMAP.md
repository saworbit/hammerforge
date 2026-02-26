# Roadmap

Last updated: February 26, 2026

This roadmap is a directional plan. Items may change based on user feedback.
Priorities are informed by a Hammer Editor gap analysis — see GAP_ANALYSIS.md for details.

## Done (Wave 1 -- Hammer-Inspired Quick Wins)
- Visgroups (visibility groups) with per-group show/hide and dock UI.
- Brush/entity grouping with Ctrl+G/U and group-aware selection.
- Texture lock (UV alignment preserved on move/resize).
- Cordon (partial bake) with AABB filter and wireframe visualization.
- GUT unit test suite (47 tests) with CI integration.

## Done (Dock UX Overhaul)
- Consolidated 8 tabs to 4 (Brush, Paint, Entities, Manage).
- Collapsible sections throughout Paint and Manage tabs.
- "No LevelRoot" banner for user guidance.
- Toolbar shortcut labels on all tool buttons.
- Sticky LevelRoot discovery (deep recursive search, no re-selection needed).
- Bake options and editor toggles reorganized into Manage tab.

## Done (Code Quality Audit)
- Comprehensive duck-typing removal across baker, file system, plugin, and dock (~30 sites total).
- Signal-driven dock sync replacing 17 per-frame property writes.
- Input handler decomposed from 260-line monolith into 7 focused handlers.
- O(1) brush ID lookup and material instance caching.
- Extracted shared methods: chunk deserialization, chunk collection, heightmap model building.
- Fixed O(n²) region index capture.
- Persistent cordon mesh (no per-call ImmediateMesh allocation).
- External highlight shader (no inline GLSL).
- Named constants for magic numbers; bounded loops.

## Done (Wave 2a -- Core Hammer Tools)
- Hollow tool (convert solid brush to hollow room with configurable wall thickness). Ctrl+H.
- Numeric input during drag (precise dimensions while drawing or extruding).
- Brush entity conversion (Tie to Entity / Untie): tag brushes as func_detail, trigger volumes, func_wall, etc.
- Texture alignment panel: Justify (Fit/Center/Left/Right/Top/Bottom), Treat-as-One for multi-face.
- Move to Floor / Move to Ceiling (snap selection to nearest surface below/above). Ctrl+Shift+F/C.

## Done (Wave 2b -- Structural Tools)
- Clipping tool (split brushes along axis-aligned plane). Shift+X.
- Entity I/O system (Source-style input/output connections with parameter, delay, fire-once).
- Entity I/O dock UI (collapsible section in Entities tab with connection list).
- Brush entity visual indicators (color-coded overlays: cyan = func_detail, orange = triggers).

## Next (Wave 2b remaining + Wave 2c)
- Vertex editing (move individual brush vertices).
- Entity connection visualization (colored lines between connected entities in viewport).
- Carve tool (boolean-subtract one brush from all intersecting brushes).

## Later (Wave 2c -- Terrain & Workflow, full)
- Interactive terrain sculpting (viewport brush: raise/lower/smooth/noise on heightmaps).
- Decals and overlay tools.
- Path tool (click-to-place path_corner/path_track chains for NPC routes, cameras).
- Displacement sewing (stitch adjacent heightmap edges to share vertices).
- Material atlasing for large scenes.

## Future (Wave 3 -- Polish)
- Polygon tool (draw arbitrary convex shapes by clicking vertices, extrude to brush).
- Merge tool (combine two adjacent brushes into one convex brush).
- Multiple simultaneous cordons.
- Multi-tool presets for common workflows.
- Additional bake pipelines (merge strategies, export helpers).
- Extended import/export formats.

## Out of Scope (for now)
- Real-time CSG of full scenes.
- Arbitrary mesh editing inside the editor.
- 3D skybox preview (Godot uses WorldEnvironment natively).
- In-editor physics simulation (Godot has a built-in physics debugger).
