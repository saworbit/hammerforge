# HammerForge Design Constraints

Last updated: March 27, 2026

This document makes the current tradeoffs explicit so level designers and developers know what HammerForge optimizes for.

## Editing Model
- Live editing uses lightweight DraftBrush previews for speed. Final geometry is produced at bake time.
- Subtractive brushes are staged as Pending Cuts until applied or baked.
- Committed cuts can be frozen for restoration or cleared for performance.

## Brush Geometry
- Brush shapes are primitives and platonic solids, not arbitrary meshes.
- Subtractive operations only affect baked output, not the live DraftBrush meshes.
- Collision is generated from additive brushes only.

## Face Materials + UVs
- Face materials use planar projection per face.
- UV editing is per face and not a full unwrap workflow.
- Preview complexity is capped. When a brush has many painted faces, the preview falls back to a simplified mesh to stay responsive.
- Prototype textures (150 built-in SVGs) are pre-packaged for greyboxing. They are not user-editable or extensible -- add custom materials via the Add button for project-specific textures.

## Floor Paint + Heightmaps
- Floor paint is grid-based and produces axis-aligned floors and walls.
- Heightmaps displace floors only. Walls remain flat.
- Heightmap blending uses four slots (A-D) with per-cell blend weights for B/C/D.
- Region streaming loads only nearby paint data; distant regions are unloaded.

## Import / Export Limits
- `.map` import/export preserves basic brush shapes and point entities, not full material or face data.
- Non-axis-aligned or complex `.map` brushes are approximated (typically as cylinders).
- `.glb` export includes only baked geometry.

## Prefabs
- Prefabs capture brush and entity state as dictionaries — they do not store Node references or scene paths.
- Transforms are centroid-relative. The centroid is computed from all selected nodes at capture time.
- Brush IDs, group IDs, and visgroup membership are cleared on capture to avoid conflicts on instantiation.
- Entity I/O connections are remapped using a name map (old entity name → new entity name) on instantiation.
- Prefab files (`.hfprefab`) use JSON with `HFLevelIO` encoding for Godot types (Vector3, Transform3D, etc.).
- The subtract preview system does not render intersections for prefab preview — only placed brushes.

## Subtract Preview
- Subtract preview shows wireframe AABB intersections, not true CSG geometry. It is an approximation that helps visualize where subtractive brushes overlap with additive ones.
- The preview is debounced (0.15s) to avoid rebuilding on every frame during rapid edits.
- Maximum 50 intersection overlays are rendered simultaneously. Beyond that, intersections are silently dropped.
- The preview uses `ImmediateMesh` with `PRIMITIVE_LINES` — zero GPU memory allocation beyond vertex buffers.

## Performance Considerations
- Chunked baking improves scale but adds bake time per chunk.
- Very large paint layers should be split to reduce regeneration cost.
