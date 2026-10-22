---
description: "What HammerForge optimises for, stated plainly: draft brush previews rather than live CSG, cuts staged until applied, geometry made at bake time."
---

# HammerForge Design Constraints

Last updated: October 22, 2026

This document makes the current tradeoffs explicit so level designers and developers know what HammerForge optimizes for.

## Editing Model
- Live editing uses lightweight DraftBrush previews for speed. Final geometry is produced at bake time.
- Subtractive brushes are staged as Pending Cuts until applied or baked.
- Committed cuts can be frozen for restoration or cleared for performance.

## Brush Geometry
- Brush shapes are primitives and platonic solids, or a Custom convex solid made by a cut, a merge, the Polygon and Path tools, a vertex edit or Convert to Brushes. A brush is never an arbitrary mesh: Convert to Brushes refuses a concave or open one.
- A box, or any other primitive, is never thinner than 0.1 on a side, because it is built from its size. A Custom brush is built from its faces and keeps a thinner size. A piece a cut leaves under 0.1 is Custom for that reason.
- Subtractive operations only affect baked output, not the live DraftBrush meshes.
- Collision is generated from additive brushes only. A `func_clip` brush gives collision and no mesh, and a stair with Ramp collision bakes a slope in place of its steps' collision.

## Face Materials + UVs
- Face materials use a projection per face: Planar X, Y or Z, Box UV, the face's own plane (Face), or Cylindrical.
- UV editing is per face and not a full unwrap workflow.
- Preview complexity is capped. When a brush has many painted faces, the preview falls back to a simplified mesh to stay responsive.
- Prototype textures (150 built-in SVGs) are pre-packaged for greyboxing. They are not user-editable or extensible -- add custom materials via the Add button for project-specific textures.

## Floor Paint + Heightmaps
- Floor paint is grid-based and produces axis-aligned floors and walls.
- Heightmaps displace floors only. Walls remain flat.
- Heightmap blending uses four slots (A-D) with per-cell blend weights for B/C/D.
- Region streaming loads only nearby paint data; distant regions are written to their `.hfr` sidecar and then unloaded. A region whose write fails stays loaded rather than losing the paint.

## Import / Export Limits
- `.map` import/export preserves basic brush shapes and point entities. Axis-aligned brushes import as boxes, and a box thinner than 0.1 on a side is widened to 0.1. Rotated or complex brushes import as CUSTOM with face vertices rather than being forced to cylinders.
- Face materials still do not round-trip as Godot materials; Valve 220 can carry UV axes when FaceData is present.
- Face planes are converted between `FaceData` winding and `.map` plane winding in both directions, so exported hulls are not inside out and imported ones are not either.
- Input that does not parse is refused before the level is modified.
- `.glb` export includes only baked geometry.
- Per-project entity types overlay `res://hammerforge_entities.json` onto the plugin `entities.json` (same classname replaces).
- A world brush whose every face is a clip texture imports as `func_clip`, and a `func_clip` exports with every face named clip.

## Prefabs
- Prefabs capture brush and entity state as dictionaries — they do not store Node references or scene paths.
- Transforms are centroid-relative. The centroid is computed from all selected nodes at capture time.
- Brush IDs, group IDs, and visgroup membership are cleared on capture to avoid conflicts on instantiation.
- Entity I/O connections are remapped using a name map (old entity name → new entity name) on instantiation.
- Prefab files (`.hfprefab`) use JSON with `HFLevelIO` encoding for Godot types (Vector3, Transform3D, etc.).
- The subtract preview system does not render intersections for prefab preview — only placed brushes.

## Subtract Preview
- Subtract preview includes DraftBrushes (not only leftover CSGShape3D nodes) and uses each brush's mesh bounds. It is still not a live full-level CSG boolean.
- It cuts only what the bake cuts: a brush tied to an entity class is never cut, and a cutter tied to one cuts nothing (`HFBakeSystem.is_structural_brush()`).
- The preview is debounced (0.15s) to avoid rebuilding on every frame during rapid edits.
- Maximum 50 intersection overlays are rendered simultaneously. Beyond that, intersections are silently dropped.
- Up to 8 cuts at once get a live CSG intersection of their real shape. The rest, and any cut still waiting on its CSG result, are drawn as the wireframe of the overlap's bounds.

## Performance Considerations
- Export templates initialize only the runtime level core: brush, entity, bake, paint, and file systems. Authoring systems such as grid, drag, snap, selection, previews, prefab editing, validation, undo, displacement, and bevel remain editor-only.
- Chunked baking splits the baked mesh so the game can cull it piece by piece. It does not make a bake shorter: chunked at the recommended size, a bake took about as long as an unchunked one ([Performance and Limits](HammerForge_Performance.md#baking)).
- Very large paint layers should be split to reduce regeneration cost.
