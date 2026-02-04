# HammerForge Floor Paint Greyboxing

Last updated: February 5, 2026

This document describes the floor paint system: grid storage, tools, geometry synthesis, reconciliation, and persistence.

## Overview
Floor Paint is a grid-based authoring tool that generates DraftBrush floors and walls. It is optimized for editor responsiveness:
- Chunked bitset storage.
- Per-chunk regeneration (dirty chunk scope).
- Stable IDs + reconciliation to avoid node churn.
- Live preview while dragging.

## Data Model

HFPaintGrid
- Cell size, origin, basis (plane), and layer height.
- Converts between world and grid coordinates.

HFPaintLayer
- Chunked grid storage using a bitset per chunk.
- Tracks dirty chunks for incremental regeneration.

HFPaintLayerManager
- Holds multiple layers and an active layer index.

HFStroke
- Captures cells, timing, bounding box, and intent hints.

## Tools
- Brush: stamp with radius.
- Erase: clears cells.
- Rect: filled rectangle.
- Line: Bresenham line.
- Bucket: flood fill (contiguous region).

Live preview
- During drag, preview writes into the layer and immediately regenerates affected chunks.
- On mouse-up, inference (if enabled) runs and a final regeneration happens.

## Geometry Synthesis

Floors
- Greedy rectangle merge on the chunk occupancy grid.
- Each rect becomes one DraftBrush box.

Walls
- Extract boundary edges where a filled cell borders empty space.
- Merge horizontal edges by y/outward and contiguous x.
- Merge vertical edges by x/outward and contiguous y.

## Stable ID Scheme

Floors
- hf:floor:v1:{layer}:{chunk}:{minx},{miny}:{w}x{h}

Walls
- hf:wall:v1:{layer}:{chunk}:{ax},{ay}->{bx},{by}:{outward}

This keeps IDs deterministic and scoped to the dirty chunk so reconciliation can be local.

## Reconciliation
1. Build an index for nodes whose `hf_chunk` is in the dirty scope.
2. Upsert nodes for all IDs in the new model.
3. Delete nodes in scope that were not regenerated.

## Persistence (.hflevel)
Paint layers serialize into the level save:
- grid settings (cell size, origin, basis, layer y)
- chunk size
- chunks with bitset data

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

## Implementation Notes
- Chunk index must floor correctly for negative coordinates.
- Live preview should reconcile on every drag update.
- Radius 1 should produce a single cell (no cross pattern).
- Generated nodes live under LevelRoot/Generated/Floors and /Walls.

## Known Limitations
- Greedy rects can change after edits, which can change IDs for floors.
- Walls are more stable because they follow boundary edges.
