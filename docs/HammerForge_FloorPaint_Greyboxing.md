# HammerForge Floor Paint Greyboxing

Last updated: February 15, 2026

This document describes the floor paint system: grid storage, tools, geometry synthesis, heightmap integration, reconciliation, and persistence. Surface paint (per-face splat layers) is documented separately and does not use the grid system.

## Overview
Floor Paint is a grid-based authoring tool that generates DraftBrush floors, walls, and optionally heightmap-displaced terrain meshes. It is optimized for editor responsiveness:
- Chunked bitset storage with per-cell material IDs and blend weights.
- Per-chunk regeneration (dirty chunk scope).
- Stable IDs + reconciliation to avoid node churn.
- Live preview while dragging.
- Optional heightmap displacement with four-slot blending.
- Region streaming for large worlds (region-based chunk loading).

## Data Model

HFPaintGrid
- Cell size, origin, basis (plane), and layer height.
- Converts between world and grid coordinates.

HFPaintLayer
- Chunked grid storage using a bitset per chunk.
- Per-chunk `material_ids` (PackedByteArray, 1 byte/cell) and blend weights (`blend_weights`, `blend_weights_2`, `blend_weights_3`).
- Optional `heightmap: Image` (FORMAT_RF) and `height_scale: float` for vertex displacement.
- Per-layer terrain slot settings: `terrain_slot_paths`, `terrain_slot_uv_scales`, `terrain_slot_tints`.
- Tracks dirty chunks for incremental regeneration.

HFChunkData (inner class of HFPaintLayer)
- `bits`: PackedByteArray bitset for cell occupancy.
- `material_ids`: PackedByteArray for per-cell material index (0-255).
- `blend_weights`: PackedByteArray for per-cell blend weight (slot B, 0-255 normalized).
- `blend_weights_2`: PackedByteArray for per-cell blend weight (slot C).
- `blend_weights_3`: PackedByteArray for per-cell blend weight (slot D).

HFPaintLayerManager
- Holds multiple layers and an active layer index.

HFTerrainRegionManager
- Groups chunks into regions for streaming and on-disk storage.
- Computes region bounds in cells/chunks and streaming radius.

HFStroke
- Captures cells, timing, bounding box, and intent hints.

## Tools
- Brush: stamp with radius.
- Erase: clears cells.
- Rect: filled rectangle.
- Line: Bresenham line.
- Bucket: flood fill (contiguous region).
- Blend: paint material blend weights on already-filled cells (does not fill new cells).

Brush Shape
- **Square**: fills every cell in the [-r, r] range (full box).
- **Circle**: clips corners using Euclidean distance (dx*dx + dy*dy > r*r).

Live preview
- During drag, preview writes into the layer and immediately regenerates affected chunks.
- On mouse-up, inference (if enabled) runs and a final regeneration happens.

## Geometry Synthesis

### Flat Floors (no heightmap)
- Greedy rectangle merge on the chunk occupancy grid.
- Each rect becomes one DraftBrush box.

### Heightmap Floors
When a layer has a heightmap assigned, floors use `HFHeightmapSynth` instead of greedy rects:
- Per filled cell: generate a quad (2 triangles) with 4 corner vertices.
- Each corner vertex is displaced vertically by `layer.get_height_at(corner_cell) * height_scale`.
- UV channel: tiled per cell (0-1 range). UV2 channel: position within chunk (for blend map sampling).
- Per-chunk blend image (Image FORMAT_RGBA8) built from cell blend weights (RGB = slots B/C/D).
- Output: MeshInstance3D nodes (not DraftBrush) stored under `Generated/HeightmapFloors`.

### Walls
- Extract boundary edges where a filled cell borders empty space.
- Merge horizontal edges by y/outward and contiguous x.
- Merge vertical edges by x/outward and contiguous y.
- Walls always use flat geometry (even when the layer has a heightmap).

## Stable ID Scheme

Floors
- hf:floor:v1:{layer}:{chunk}:{minx},{miny}:{w}x{h}

Walls
- hf:wall:v1:{layer}:{chunk}:{ax},{ay}->{bx},{by}:{outward}

This keeps IDs deterministic and scoped to the dirty chunk so reconciliation can be local.

## Reconciliation
1. Build an index for nodes whose `hf_chunk` is in the dirty scope (floors, walls, and heightmap floors).
2. Upsert nodes for all IDs in the new model.
3. Delete nodes in scope that were not regenerated.

Heightmap floor nodes are MeshInstance3D (not DraftBrush) and live under `Generated/HeightmapFloors`. The reconciler always applies a blend ShaderMaterial (with default terrain colors even when no textures are assigned).

Note: `_clear_generated()` must `remove_child()` before `queue_free()` so that a subsequent `reconcile()` call in the same frame does not find ghost nodes still in the tree.

## Persistence (.hflevel)
Paint layers serialize into the level save:
- grid settings (cell size, origin, basis, layer y)
- chunk size
- chunks with bitset data, `material_ids`, and `blend_weights` / `blend_weights_2` / `blend_weights_3`
- `heightmap_b64` (base64-encoded PNG) and `height_scale` per layer (optional, backward-compatible)
- `terrain_slot_paths`, `terrain_slot_uv_scales`, `terrain_slot_tints` per layer

Region streaming:
- Region index stored in `.hflevel` under `terrain_regions`.
- Per-region chunk data stored in `.hfr` files inside `<level>.hfregions/`.

## Pseudo-code

Greedy rectangles
```
function greedy_rectangles(filled, N):
    used = N x N bool
    rects = []
    for y in 0..N-1:
        for x in 0..N-1:
            if used[x][y] or not filled[x][y]: continue
            w = max width
            h = max height for that width
            mark used
            rects.append((x, y, w, h))
    return rects
```

Boundary edges
```
for each filled cell:
    if neighbor north empty -> emit horizontal edge
    if neighbor south empty -> emit horizontal edge
    if neighbor west empty  -> emit vertical edge
    if neighbor east empty  -> emit vertical edge
```

Merge edges
```
merge horizontal by (y, outward) and contiguous x
merge vertical by (x, outward) and contiguous y
```

## Heightmap I/O (`hf_heightmap_io.gd`)
- `load_from_file(path) -> Image`: loads PNG/EXR, converts to FORMAT_RF.
- `generate_noise(width, height, settings) -> Image`: procedural generation via FastNoiseLite.
- `encode_to_base64(image) -> String`: PNG buffer to base64 for save.
- `decode_from_base64(data) -> Image`: base64 to Image for load.

## Material Blending
The blend system uses a four-slot spatial shader (`hf_blend.gdshader`):
- `material_a`..`material_d`: four texture samplers with configurable UV scale.
- `blend_map`: sampled on UV2, RGB channels represent weights for slots B/C/D. Slot A is implicit base weight (`1 - (B+C+D)`).
- `color_a`..`color_d`: tint/fallback colors. When no textures are assigned, these provide immediate visual feedback. When textures are assigned, they act as a tint multiplier (set to white for unmodified texture color).
- `grid_opacity` (default 0.25) and `grid_color` (default black): cell-boundary grid overlay drawn using UV coordinates. Helps visualize terrain at low height scales.
- Per-chunk blend images are built from cell-level blend weights during mesh generation.
- The blend material is always applied to heightmap floor MeshInstance3D nodes (even without explicit blend textures).

## Auto-Connectors (`hf_connector_tool.gd`)
Generates transition geometry between layers at different Y heights:
- **Ramp**: SurfaceTool sloped quad strip from one cell to another.
- **Stairs**: horizontal treads + vertical risers when height difference exceeds step threshold.
- `ConnectorDef` specifies from/to layer indices, cells, width, and step height.

## Foliage Populator (`hf_foliage_populator.gd`)
Procedural scatter using MultiMeshInstance3D:
- Height range and slope filtering per cell.
- Configurable density (instances per cell with fractional probabilistic rounding).
- Random jitter, scale range, and optional Y-axis rotation.
- Output: MultiMeshInstance3D added to a parent node.

## Implementation Notes
- Chunk index must floor correctly for negative coordinates.
- Live preview should reconcile on every drag update.
- Radius 1 should produce a single cell (no cross pattern) regardless of brush shape.
- Generated flat floors/walls live under LevelRoot/Generated/Floors and /Walls.
- Generated heightmap floors live under LevelRoot/Generated/HeightmapFloors.
- When a layer has a heightmap, paint_tool routes to `HFHeightmapSynth` for floors and `HFGeometrySynth` for walls.
- Bake system collects heightmap MeshInstance3D nodes and duplicates them into baked output with trimesh collision (bypasses CSG).

## Known Limitations
- Greedy rects can change after edits, which can change IDs for floors.
- Walls are more stable because they follow boundary edges.
- Heightmap displacement is per-cell corner (4 vertices per cell); sub-cell terrain detail requires a denser grid.
- Blend shader supports four slots (A-D); more slots would require a different approach (texture arrays or atlasing).
- Connectors generate geometry but do not automatically detect optimal placement.
