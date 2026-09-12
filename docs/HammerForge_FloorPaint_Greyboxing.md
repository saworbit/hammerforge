---
description: "Grid-based floor painting and greyboxing in HammerForge: heightmaps, multi-material blending, auto-connectors and foliage scatter."
---

# HammerForge Floor Paint Greyboxing

Last updated: September 10, 2026

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
- Chunked grid storage using a bitset per chunk. A chunk is allocated on the first cell painted in it and dropped when its last cell is erased, so erasing paint gives the memory back and an all-zero chunk is never saved. Erasing over unpainted ground allocates nothing.
- Per-chunk `material_ids` (PackedByteArray, 1 byte/cell) and blend weights (`blend_weights`, `blend_weights_2`, `blend_weights_3`).
- Optional per-cell wall height overrides used by the paint-then-raise workflow.
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
- Sculpt Raise: raises heightmap terrain under the cursor (requires layer with heightmap).
- Sculpt Lower: lowers heightmap terrain under the cursor.
- Sculpt Smooth: averages terrain to reduce jaggedness (3x3 kernel).
- Sculpt Flatten: captures reference height on first click, lerps terrain toward it.

### Viewport input

- **Shift+P** toggles Paint mode. A first room needs no dock interaction: press **R** for Rect, then LMB-drag the walkable footprint.
- **LMB-drag** uses the selected Floor Paint tool. **Alt+LMB** temporarily erases occupancy without changing that tool.
- **Shift+LMB-drag** locks a Brush, Erase, Line, or Blend stroke to the first dominant grid axis. The axis stays fixed for the stroke, so diagonal pointer jitter cannot flip it.
- **Ctrl/Cmd+LMB** samples the cell material for the Blend tool and does not start an undoable stroke.
- **Y** starts a height gesture for the last Brush or Rect footprint. Move vertically to set its wall height, then click to confirm. This is a clearly chained **Raise Paint Walls** undo after the paint stroke.
- **X** and **Z** toggle grid-origin mirroring for subsequent paint. Both are off by default and can be combined; all mirrored copies commit with the source stroke as one undo entry.
- **H** stamps a room from the last Rect dimensions: filled floor plus raised boundary walls, committed as one undo entry.
- Painting against an adjacent layer at a different Y height shows a ramp or stair ghost. **Enter** confirms it as a persistent `ConnectorDef`; **Esc** dismisses it.
- **Esc** cancels the active stroke or raise gesture and removes transient footprint/connector ghosts. Plain **RMB** is never a Floor Paint input; at rest it remains Godot's 3D camera control.
- The existing viewport banner reports the hovered cell and brush footprint, then live unique-cell count and world-space width/depth while painting.
- A changed press-drag-release is one **Paint Floor** undo entry. Lost-release recovery closes that same entry; no-op strokes and material picks create none.

Sculpt tools operate directly on heightmap Image pixels (not cell bits). Configurable: strength (0.1–10.0), radius (1–50 cells), falloff (0.0–1.0 Gaussian curve). Available in dock Paint tab → Heightmap section.

Brush Shape
- **Square**: fills every cell in the [-r, r] range (full box).
- **Circle**: clips corners using Euclidean distance (dx*dx + dy*dy > r*r).

Live preview
- During drag, preview writes into the layer and immediately regenerates affected chunks.
- The viewport draws only the active footprint, raise cage, and touched connector candidates. These overlays use stroke-local data rather than scanning a whole layer and are synchronously removed on stroke end or Esc.
- On mouse-up, a final regeneration happens.
- Preview work consumes only dirty chunks. With region streaming enabled, every region crossed by the current stroke is pinned until release or cancel, and the starting region is loaded before the undo snapshot.
- **Inference cleanup is off by default.** Enabling it in Paint → Floor Paint wires `HFInferenceEngine` for new strokes. Its deliberately bounded pass can remove an isolated one-cell island, fill a one-cell cardinal hole or gap, and widen an inferred one-cell corridor by one row/column. Erase strokes are never rewritten, and cleanup is restricted to the stroke's dirty chunks plus its one-cell local halo.

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
- Boundary runs with different per-cell wall heights remain separate so a raised footprint does not change unrelated walls.
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
- per-cell wall height overrides
- `heightmap_b64` (base64-encoded raw float buffer, zstd compressed) and `height_scale` per layer (optional, backward-compatible; a base64 PNG written by an older version still loads)
- `terrain_slot_paths`, `terrain_slot_uv_scales`, `terrain_slot_tints` per layer
- confirmed paint connector definitions

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

## Auto-Connectors (`hf_connector_tool.gd` + `hf_auto_connector.gd`)
Generates transition geometry between layers at different Y heights:
- **Ramp**: SurfaceTool sloped quad strip from one cell to another.
- **Stairs**: horizontal treads + vertical risers when height difference exceeds step threshold.
- `ConnectorDef` specifies from/to layer indices, cells, width, and step height.
- **Live paint workflow:** only boundaries touched by the completed stroke become translucent connector ghosts. Enter commits those definitions in one undoable action; Esc discards them. Confirmed definitions persist in editor state and bake even when automatic detection is off.
- **Auto-detection during bake** (`hf_auto_connector.gd`): When "Auto Connectors" is enabled in Bake settings, the bake pipeline automatically scans paint layers for cross-layer height boundaries (N/S/E/W neighbors), groups adjacent boundary edges, and generates ramp or stair geometry. Mode can be Ramp, Stairs, or Auto (auto selects stairs when height difference exceeds stair step threshold). Connectors include collision shapes for navmesh parsing. Skipped during selection-only bakes.
- A confirmed boundary takes precedence over the same automatically detected boundary, preventing duplicate baked geometry.

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
- Auto-connectors use axis-aligned 4-directional scanning; diagonal height transitions are not detected.
