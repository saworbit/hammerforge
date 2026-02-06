# HammerForge Spec

Last updated: February 5, 2026

This document describes HammerForge's architecture and data flow.

## Goals
- Fast in-editor greyboxing with brush workflows.
- Editor responsiveness by avoiding live CSG.
- Reliable bake pipeline and clean data model.

## Architecture

Core scripts
- `addons/hammerforge/plugin.gd`: EditorPlugin entry, input routing.
- `addons/hammerforge/level_root.gd`: central controller and containers.
- `addons/hammerforge/dock.gd` + `dock.tscn`: UI and tool state.
- `addons/hammerforge/brush_instance.gd`: DraftBrush node.
- `addons/hammerforge/baker.gd`: CSG -> mesh bake pipeline.
- `addons/hammerforge/paint/*`: floor paint system.
- `addons/hammerforge/face_data.gd`: per-face materials, UVs, and paint layers.
- `addons/hammerforge/material_manager.gd`: shared materials palette.
- `addons/hammerforge/face_selector.gd`: raycast face selection helper.
- `addons/hammerforge/surface_paint.gd`: per-face surface paint tool.
- `addons/hammerforge/uv_editor.gd` + `uv_editor.tscn`: UV editing dock control.

## Node Hierarchy
```
LevelRoot (Node3D)
- DraftBrushes
- PendingCuts
- CommittedCuts
- MaterialManager
- PaintLayers
- SurfacePaint
- Generated
  - Floors
  - Walls
- Entities
- BakedGeometry
```

## Brush Workflow
- Draw creates DraftBrush nodes in DraftBrushes.
- Subtract brushes are staged in PendingCuts until Apply Cuts.
- Bake builds a temporary CSG tree from DraftBrushes + CommittedCuts and outputs BakedGeometry.

## Floor Paint System

Data
- Grid -> Layer -> Chunked bitset storage.
- Paint layers are stored under PaintLayers.

Generation
- Floors: greedy rectangle merge.
- Walls: boundary edges + merged segments.

Reconciliation
- Stable IDs for generated geometry.
- Dirty chunk scoping to avoid unnecessary churn.

## Entities
- Entities live under LevelRoot/Entities or are tagged `is_entity`.
- Entities are selectable but excluded from bake.
- Definitions come from `addons/hammerforge/entities.json`.

## Persistence (.hflevel)
- Stores brushes, entities, level settings, materials palette, and paint layers.
- Brush records include face data (materials, UVs, paint layers).
- Paint layers include grid settings, chunk size, and bitset data.

## Bake Pipeline
- Temporary CSG tree for DraftBrushes (including generated floors/walls).
- Optional mesh merging, LODs, lightmap UV2, navmesh.
- Optional face-material bake (per-face materials, no CSG).
- Collision uses Add brushes only.

## Face Materials + Surface Paint
Face data is stored per DraftBrush face with material assignment, UV projection, and optional paint layers.
Surface paint is a per-face splat system. It updates preview materials and can be baked using the face-material bake option.

## Editor UX
- Theme-aware dock styling.
- Optional HUD overlay for shortcuts.
- Shader-based editor grid with follow mode.
