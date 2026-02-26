# HammerForge Data Portability

Last updated: February 26, 2026

This document describes how to move data in and out of HammerForge safely.

## Source of Truth: `.hflevel`
- `.hflevel` files are the canonical save format for brushes, paint layers, materials, entities, and settings.
- When region streaming is enabled, per-region paint data is stored in a sibling `<level>.hfregions/` folder.
- Files include a version field and default missing keys on load for backward compatibility.
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
- Import supports axis-aligned boxes and simple cylinders.
- Export writes box and cylinder primitives only and does not preserve per-face materials or paint data.
- Treat `.map` as a blockout exchange format, not a full fidelity export.

## `.glb` Export
- `.glb` export writes the baked geometry only.
- A successful bake is required before export.
- Use `Bake -> Export .glb` when you need DCC or engine interoperability.

## Recommended Pipeline
1. Design and iterate in HammerForge.
2. Save `.hflevel` to preserve full fidelity editing data.
3. Bake when you need runtime geometry.
4. Export `.glb` for downstream tools or external engines.
