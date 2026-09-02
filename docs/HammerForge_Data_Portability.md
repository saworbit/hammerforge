# HammerForge Data Portability

Last updated: September 2, 2026

This document describes how to move data in and out of HammerForge safely.

## Source of Truth: `.hflevel`
- `.hflevel` files are the canonical save format for brushes, paint layers, materials, entities, and settings.
- When region streaming is enabled, per-region paint data is stored in a sibling `<level>.hfregions/` folder.
- Files include a version field and default missing keys on load for backward compatibility.
- Per-face UV data includes `uv_format_version` (current: 1). Legacy data (version 0, pre-April 2026) used a different UV transform order (scale+offset before rotation). On load, legacy faces are auto-migrated: uniform-scale faces get their offset adjusted; non-uniform-scale faces with rotation are baked to `custom_uvs`. No manual intervention is needed.
- Per-face vertex winding includes `winding_version` (current: 1). Legacy data (version 0, pre-April 2026) used CCW vertex winding for manually-created faces, which rendered inside-out under Godot 4's CW front-face convention. On load, `apply_serialized_faces()` detects v0 faces and runs a centroid-based migration: each face's normal is checked against the outward direction from the brush center, and faces pointing inward have their vertices reversed to CW. Mesh-extracted faces (already CW) are left unchanged. No manual intervention is needed.
- Autosaves write to `res://.hammerforge/autosave.hflevel` by default.
- Store `.hflevel` in version control for reliable recovery.

### Entity I/O Serialization
- Entity I/O connections are stored per-entity in the `io_outputs` key of each entity record.
- Each connection is a Dictionary: `{output_name, target_name, input_name, parameter, delay, fire_once}`.
- Connections are captured by `capture_entity_info()` and restored by `restore_entity_from_info()`.
- Missing `io_outputs` key on load = no connections (backward-compatible).

### Brush Entity Class Serialization
- Brush entity class (`func_detail`, `func_wall`, `trigger_once`, `trigger_multiple`) is stored in the `brush_entity_class` key of each brush record.
- Missing key on load = no entity class (standard structural brush).

## `.map` Import / Export
- Use `.map` to exchange basic brush layouts with other editors.
- Axis-aligned boxes use the optimized primitive path; tilted, clipped, and other non-axis-aligned convex brushes import and export as CUSTOM face geometry.
- Point-entity key/value properties and brush entity classes round-trip through the supported Classic Quake and Valve 220 adapters.
- Per-face materials and HammerForge surface-paint layers are not preserved, so `.hflevel` remains the editable source of truth.
- Treat `.map` as a blockout exchange format, not a full fidelity export.
- Multi-format export: **Classic Quake** and **Valve 220** format adapters are available via the format selector in the dock File section. Valve 220 includes UV texture axes from FaceData.
- Known limitation: quoted entity property values containing escaped quotes or backslashes do not yet round-trip reliably; follow [#32](https://github.com/saworbit/hammerforge/issues/32) for that parser fix.

### Import Vertex Welding
Legacy .map files from Hammer, TrenchBroom, and other editors often carry floating-point representation drift in vertex coordinates. Two vertices that should be coincident may differ by a fraction of a unit, producing micro-gaps or non-planar faces after import.

`MapIO.parse_map_text()` automatically welds near-coincident parsed vertices before constructing brush geometry. The tolerance is controlled by `MapIO.import_weld_tolerance` (default **0.01 units**). Vertices within this distance are averaged to a shared position via BFS grouping over a spatial hash with 27-cell neighbor lookup, so pairs that straddle a snap-grid boundary are still caught.

To adjust the tolerance:
```gdscript
MapIO.import_weld_tolerance = 0.05  # increase for very noisy legacy files
MapIO.import_weld_tolerance = 0.0   # disable welding entirely
```

After import, run **Check Only** (Test tab) to detect any remaining non-planar faces or micro-gaps between brushes. The validation system offers auto-fix methods (`weld_brush_vertices`, `fix_non_planar_faces`) for post-import cleanup.

## `.glb` Export
- `.glb` export writes the baked geometry only.
- A successful bake is required before export.
- Use `Bake -> Export .glb` when you need DCC or engine interoperability.

## Material Library
- The material palette can be saved and loaded independently via `MaterialManager.save_library()` / `load_library()`.
- Library files are JSON containing material resource paths — portable across projects.
- The library path can be stored alongside `.hflevel` saves.

## Prototype Textures
- HammerForge ships with 150 built-in SVG prototype textures at `addons/hammerforge/textures/prototypes/`.
- Click **Refresh Prototypes** in Paint tab → Materials section to batch-load all textures into the palette.
- Once loaded, prototype materials are serialized in `.hflevel` saves alongside custom materials.
- Prototype textures are included in the plugin directory and travel with the project automatically.

## Entity Definitions
- Entity types and brush entity classes are loaded from `entities.json` (data-driven, not hardcoded).
- Custom entity definitions can be added by creating or editing `res://addons/hammerforge/entities.json`.
- Definitions include `classname`, `description`, `color`, `is_brush_entity`, `properties`, and optional `scene_path`.

## Prefabs: `.hfprefab`
- `.hfprefab` files store reusable brush + entity groups as JSON.
- Transforms are stored relative to the group centroid, so prefabs can be placed at any world position.
- Brush IDs and group IDs are stripped on capture; new ones are assigned on instantiation.
- Entity I/O connections are captured and remapped to new entity names when instantiated.
- Data encoding uses the same `HFLevelIO.encode_variant()` / `decode_variant()` pipeline as `.hflevel` (handles Vector3, Transform3D, Basis, etc.).
- Prefab files are saved to `res://prefabs/` by default. The directory is created automatically on first save.
- Prefabs are portable between projects — just copy `.hfprefab` files to another project's `res://prefabs/` folder.

## Autosave Safety
- Autosave writes happen on a background thread.
- Saves first write a `.writing` sidecar, then replace the destination.
- If a write fails (e.g., disk full, permissions), the `autosave_failed` signal fires and the dock shows a red warning label.
- The next autosave interval retries automatically.
- Manual save is always available via Test tab → File section.
- Current limitation: replacement removes an existing destination before renaming the sidecar, so interruption in that window is not fully crash-atomic ([#33](https://github.com/saworbit/hammerforge/issues/33)). Manual save can also report that work was queued before the background write completes ([#51](https://github.com/saworbit/hammerforge/issues/51)). Keep `.hflevel` files in version control and treat the warning state—not the initial queued message—as the authoritative failure signal.

## Recommended Pipeline
1. Design and iterate in HammerForge.
2. Save `.hflevel` to preserve full fidelity editing data.
3. Bake when you need runtime geometry.
4. Export `.glb` for downstream tools or external engines.
