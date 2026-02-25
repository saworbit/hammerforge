# Roadmap

Last updated: February 25, 2026

This roadmap is a directional plan. Items may change based on user feedback.

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

## Now
- Numeric input during drag (precise dimensions while drawing or extruding).
- Material atlasing for large scenes.

## Next (Wave 2 -- Hammer Tools)
- Clipping tool (split brushes along a plane).
- Vertex editing (move individual brush vertices).
- Entity I/O system (trigger/target connections between entities).
- Decals and trim tools.

## Later
- Multi-tool presets for common workflows.
- Additional bake pipelines (merge strategies, export helpers).
- Extended import/export formats.

## Out of Scope (for now)
- Real-time CSG of full scenes.
- Arbitrary mesh editing inside the editor.
