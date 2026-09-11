---
description: "Moving level data in and out of HammerForge safely: the .hflevel save format, version fields, UV migration and region streaming files."
---

# HammerForge Data Portability

Last updated: September 2, 2026

This document describes how to move data in and out of HammerForge safely.

## Source of Truth: `.hflevel`
- `.hflevel` files are the canonical save format for brushes, paint layers, materials, entities, and settings.
- When region streaming is enabled, per-region paint data is stored in a sibling `<level>.hfregions/` folder as one `.hfr` file per region.
- A region is written before its chunks are streamed out of memory. If that write fails the region stays loaded and you are told, so unsaved paint is not dropped by moving the cursor.
- A region is only listed in the `.hflevel` index once its `.hfr` file exists on disk.
- Files include a version field and default missing keys on load for backward compatibility.
- Per-face UV data includes `uv_format_version` (current: 1). Legacy data (version 0, pre-April 2026) used a different UV transform order (scale+offset before rotation). On load, legacy faces are auto-migrated: uniform-scale faces get their offset adjusted; non-uniform-scale faces with rotation are baked to `custom_uvs`. No manual intervention is needed.
- Per-face vertex winding includes `winding_version` (current: 2). Legacy data (version 0, pre-April 2026) used CCW vertex winding for manually-created faces, which rendered inside-out under Godot 4's CW front-face convention. On load, `apply_serialized_faces()` detects v0 faces and runs a centroid-based migration: each face's normal is checked against the outward direction from the brush center, and faces pointing inward have their vertices reversed to CW. Mesh-extracted faces (already CW) are left unchanged. Version 1 data is correct except on the five shapes whose builders wound every face inside out before September 2026: `PRISM_TRI`, `PRISM_PENT`, `OCTAHEDRON`, `DODECAHEDRON` and `ICOSAHEDRON`. A v1 brush of one of those shapes runs the same centroid migration, which is exact because all five are convex; every other v1 face is left alone, so a torus or another concave brush is never touched. No manual intervention is needed.
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
- Import works the face polygons out rather than reading them off the file. A `.map` face line names three points on an infinite plane, not the corners of a face, and the solid is the intersection of the half spaces behind its planes. A set of planes that closes nothing still imports, on the old reading of the points as corners, so an ill-formed brush arrives wrong rather than not at all.
- Point-entity key/value properties and brush entity classes round-trip through the supported Classic Quake and Valve 220 adapters.
- Per-face material names round-trip. Each face line names the material its `material_idx` points at, and an import maps that name back to a palette slot by name. A face with no material, or one whose index is past the palette, writes `__default`.
  - The texture field is positional and whitespace delimited, so a palette name with a space in it is written with underscores (`Red Brick` becomes `Red_Brick`). Import matches on the same token.
  - A `.map` names a texture without saying where it lives, so a name the current palette does not hold leaves the face unset rather than adding a material. Load the palette first, then import.
- UV offset, rotation and scale are written in both formats. Valve 220 additionally carries the texture axes; Classic Quake has no field for them.
- Authored entity names round-trip as `targetname`, on both point entities and brush entities. The authored name is the address every I/O connection is aimed at, so without it a wired level comes back inert.
- **Entity I/O connections round-trip, one key/value line per connection.** The key is the output name and the value is `target,input,parameter,delay,fire_once`, which is the order Hammer writes a VMF connection:

  ```
  {
  "classname" "func_button"
  "targetname" "btn"
  "OnPressed" "door,Open,,0.0,0"
  }
  ```

  - A line with the five fields of a connection but a blank target or input, or a delay that is not a number, cannot be used and is dropped on import. The import result names how many were dropped rather than losing them in silence. The editor refuses to create one, so a file carrying them was written somewhere else or by hand.
  - There is no `connections { }` block, because `.map` entity bodies are key/value lines and nothing else: a nested brace inside an entity is read as a brush by every parser including this one, so a block would not survive its own round trip.
  - One line per connection, so two outputs on the same event both reach the file. The import reads the key/value lines in file order rather than through a dictionary, which would keep only the last of a repeated key.
  - A line is read back as a connection only if it has five comma-separated fields, a numeric delay, and a target and input that are actually there. An ordinary entity property does not look like that, so wiring is told apart from settings without a naming rule on the key.
  - The format defines no escape for a comma, so a comma inside a field is written as a space rather than escaped. A reader splitting on the comma would otherwise get a different number of fields than the writer wrote.
- HammerForge surface-paint layers are not preserved, so `.hflevel` remains the editable source of truth.
- Treat `.map` as a blockout exchange format, not a full fidelity export.
- Cutters are not exported. A `.map` worldspawn holds additive solids only, so a subtraction brush written into one would fill the hole it was made for instead of cutting it. Carved shapes export uncut; bake or export `.glb` when the carve has to come with them.
- Face planes are written in `.map` winding, which is the reverse of the clockwise-from-outside order `FaceData` stores, so exported hulls are the right way out for compilers and other editors. Import applies the same conversion in reverse. Cylinders used to be written the other way round and now match the box and custom-face writers.
- One plane per flat surface. A `.map` brush is an intersection of half spaces, so a cylinder cap is a single plane rather than one plane per fan wedge: a prism exports as `sides + 2` planes. Writing the fan produced `3 * sides`, most of them exact duplicates, which several external compilers report as a degenerate brush.
- A file that does not parse is refused before the level is touched. Unbalanced braces, face lines that are not three points, and text outside any block are reported, the current level is left alone, and no undo entry is created.
- Multi-format export: **Classic Quake** and **Valve 220** format adapters are available via the format selector in the dock File section. Valve 220 includes UV texture axes from FaceData. The axes are resolved against the face normal, not against the stored projection alone: Valve 220 requires both axes to lie in the face plane, and a stored projection knows nothing about which way the face points. A projection whose axes would lie along the normal falls back to the dominant-normal choice.
- Entity property keys and values may contain quotes, backslashes and `//`. HammerForge escapes `\` and `"` on export and reads key/value lines as quoted tokens, so what it writes it reads back unchanged. The `.map` format itself defines no escaping rule, so a file written this way shows a literal `\"` if it is opened by a tool that does not expect one — keep quotes out of values you intend to hand to another editor.
- Reading is deliberately conservative in the other direction: only `\"` and `\\` are treated as escapes, so an unescaped Windows path from another tool (`textures\maps\wall`) survives intact. The one case that cannot be resolved either way is a literal `\\` written by a tool that does not escape; HammerForge reads it as a single backslash.

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
- Add your own in `res://hammerforge_entities.json`. That file overlays the plugin's `entities.json`, and an entry with the same classname replaces the plugin one. Prefer it over editing `res://addons/hammerforge/entities.json`, which is overwritten when the plugin is upgraded.
- A `LevelRoot` can point somewhere else through its `entity_definitions_path` export. The point entity palette and the brush entity dropdown both read the same merged result, so a custom point entity is placeable and a custom brush class is assignable without further setup.
- Definitions include `classname`, `description`, `color`, `is_brush_entity`, `properties`, and optional `scene_path`. The dock also reads presentation keys straight from the JSON: `label`, `preview`, and `category`.

## Prefabs: `.hfprefab`
- `.hfprefab` files store reusable brush + entity groups as JSON.
- Transforms are stored relative to the group centroid, so prefabs can be placed at any world position.
- Brush IDs and group IDs are stripped on capture; new ones are assigned on instantiation.
- Entity I/O connections are captured and remapped to new entity names when instantiated. The remap runs over the entities the placement just created, not over a name lookup, so an authored name that collides with another copy's node name cannot send it to the wrong one.
- The authored entity name travels verbatim, so placing a prefab twice gives both copies the same name. The I/O remap works off node names, which are made unique on placement; rename the copies yourself if two of them are meant to be told apart by an output.
- Data encoding uses the same `HFLevelIO.encode_variant()` / `decode_variant()` pipeline as `.hflevel` (handles Vector3, Transform3D, Basis, etc.).
- Prefab files are saved to `res://prefabs/` by default. The directory is created automatically on first save.
- Prefabs are portable between projects — just copy `.hfprefab` files to another project's `res://prefabs/` folder.

## Autosave Safety
- Autosave writes happen on a background thread.
- Saves first write a `.writing` sidecar, then replace the destination.
- The existing file is copied to `<level>.hflevel.previous` before it is replaced, and that copy is restored if the rename fails. On load, a missing destination with a `.previous` beside it is promoted automatically.
- If a write fails (e.g., disk full, permissions), `autosave_failed` fires for autosaves and `hflevel_save_failed` for manual saves, and the dock shows a red warning label.
- The next autosave interval retries automatically.
- Manual save is always available via Test tab → File section. Success is reported only after the matching background write finishes, not when the work is queued.
- Queued writes run in the order they were requested, so two saves to the same path in quick succession leave the newer one on disk.
- When region streaming is on, a failed `.hfregions` sidecar fails the whole save rather than writing a `.hflevel` whose index points at region files that are missing or stale.
- Keep `.hflevel` files in version control and treat the warning state as the authoritative failure signal.

## Recommended Pipeline
1. Design and iterate in HammerForge.
2. Save `.hflevel` to preserve full fidelity editing data.
3. Bake when you need runtime geometry.
4. Export `.glb` for downstream tools or external engines.
