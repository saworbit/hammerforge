# HammerForge Design Constraints

Last updated: February 15, 2026

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

## Floor Paint + Heightmaps
- Floor paint is grid-based and produces axis-aligned floors and walls.
- Heightmaps displace floors only. Walls remain flat.
- Heightmap blending uses two materials with per-cell blend weights.

## Import / Export Limits
- `.map` import/export preserves basic brush shapes and point entities, not full material or face data.
- Non-axis-aligned or complex `.map` brushes are approximated (typically as cylinders).
- `.glb` export includes only baked geometry.

## Performance Considerations
- Chunked baking improves scale but adds bake time per chunk.
- Very large paint layers should be split to reduce regeneration cost.
