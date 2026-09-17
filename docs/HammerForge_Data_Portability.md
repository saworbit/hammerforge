---
description: "Moving level data in and out of HammerForge safely: the .hflevel save format, version fields, UV migration and region streaming files."
---

# HammerForge Data Portability

Last updated: September 17, 2026

This document describes how to move data in and out of HammerForge safely.

## Source of Truth: `.hflevel`
- `.hflevel` files are the canonical save format for brushes, paint layers, materials, entities, decals, and settings.
- When region streaming is enabled, per-region paint data is stored in a sibling `<level>.hfregions/` folder as one `.hfr` file per region.
- A region is written before its chunks are streamed out of memory. If that write fails the region stays loaded and you are told, so unsaved paint is not dropped by moving the cursor.
- A region is only listed in the `.hflevel` index once its `.hfr` file exists on disk.
- Files include a version field and default missing keys on load for backward compatibility. The bundle version is `HFLevelIO.FORMAT_VERSION` (current: 1). A file stamped higher than this build reads is refused before anything is applied, with a message, rather than clearing the open level and restoring what it can parse. A file with no version, or version 0, is an older one and still loads, because every key defaults.
- Per-face UV data includes `uv_format_version` (current: 1). Legacy data (version 0, pre-April 2026) used a different UV transform order (scale+offset before rotation). On load, legacy faces are auto-migrated: uniform-scale faces get their offset adjusted; non-uniform-scale faces with rotation are baked to `custom_uvs`. No manual intervention is needed.
- Per-face vertex winding includes `winding_version` (current: 3). Legacy data (version 0, pre-April 2026) used CCW vertex winding for manually-created faces, which rendered inside-out under Godot 4's CW front-face convention. On load, `apply_serialized_faces()` detects v0 faces and runs a centroid-based migration: each face's normal is checked against the outward direction from the brush center, and faces pointing inward have their vertices reversed to CW. Mesh-extracted faces (already CW) are left unchanged. Version 1 data is correct except on the five shapes whose builders wound every face inside out before September 2026: `PRISM_TRI`, `PRISM_PENT`, `OCTAHEDRON`, `DODECAHEDRON` and `ICOSAHEDRON`. A v1 brush of one of those shapes runs the same centroid migration, which is exact because all five are convex; every other v1 face is left alone, so a torus or another concave brush is never touched. Version 2 data is correct except for path tool brushes, whose two builders wound every face inside out before September 2026. Those are `CUSTOM` brushes, so there is no shape to key the migration on; instead a brush saved below version 3 whose every face points at its own centroid runs the same centroid migration. That is what an inverted convex solid looks like and what a correctly wound closed solid cannot look like, concave or not, because the faces on its convex hull always point away from the centre. No manual intervention is needed.
- Autosaves write to `res://.hammerforge/<scene name>.hflevel` by default, derived from the scene the level was opened from. A level whose scene has never been saved has no name to derive from and uses `res://.hammerforge/autosave.hflevel` until it does.
- Files carry a `scene` field naming the `.tscn` they were saved from. It is what lets a file say which level it holds when every level shares the default autosave path. Files written before September 2026 do not have it, and every key defaults, so they still load.
- Store `.hflevel` in version control for reliable recovery.
- Visgroups and groups are saved with the order they were made in, beside the registry itself. The registries are JSON objects and `JSON.stringify` sorts object keys, so without it the panel came back alphabetised on every reload. A file written before September 2026 has no order recorded and loads the way it always did.
- **Save compression** (Console > Controls) decides the form on disk. On, the default, the bundle is deflated: a 45-brush level is about 3 KB. Off, it is plain JSON written one value per line with keys in a stable order, which is the form to use when the level is reviewed and merged like any other file in the repository. The same level is about 250 KB that way, and the loader reads either form without being told which.
- A `.hflevel` records `saved_at`, stamped as the file is written rather than when the level was captured. An autosave of a level nothing has changed therefore writes nothing, because what decides that is the level and not the clock.
- Save Level writes the file it is given, every time. A save to a second path is a copy of the level, not a no-op, even when nothing has changed since the last one.

### Which File Opens: the `.tscn` Wins
A level lives in two files, and they are written by two different commands. Godot's own **Ctrl+S** writes the scene; **Save Level** writes the `.hflevel`. Nothing reconciles them, and nothing merges them; HammerForge only tells you when they have come apart.

**On open, the scene wins**, because the scene is what Godot loads. A `.hflevel` saved after the last Ctrl+S is not what comes up. Use **Load Level** to bring it in.

HammerForge says so when it happens. On the frame the dock binds to a level it compares the two files' modification times, and if the `.hflevel` is the newer one it puts a line in the Console and a toast on screen. It says it once per open, not once per rebind, because after that the scene in the editor has moved on and Load Level would cost you whatever you did since.

A `.hflevel` records the scene it was saved from, so a file that belongs to another level is not reported against this one. That matters because a level can still be pointed at a shared path by hand, and Load Level on another level's file would overwrite the open one. Files written before September 2026 carry no such record; they are still reported, and the message says it cannot tell which level they hold.

The same record is what stops an autosave landing on someone else's file. An autosave is a write nobody asked for, on a timer, so it is refused when the target `.hflevel` says it holds a different scene, and the refusal is said once. **Save Level** is never refused: writing over another level's file on purpose is a thing you are allowed to do.

The one exception is a level set to keep only its baked geometry, below: that scene has no brushes to win with, so it loads its `.hflevel` when it opens.

### What the Scene Keeps
HammerForge gives an `owner` to almost everything it makes, so Ctrl+S writes the brushes *and* the geometry baked from them into the `.tscn`. A 100-brush level is about 261 KB of scene against 4 KB of `.hflevel`, and a bake adds another 149 KB that is derivable from the brushes already in the file. For a greybox session that is what you commit and what a teammate has to merge.

**Scene Keeps** on the `LevelRoot` chooses what goes in:

| Setting | The `.tscn` holds | Notes |
|---|---|---|
| **Brushes and bake** (default) | Both | The scene is the whole level on its own, and has geometry at runtime without the plugin. |
| **Brushes only** | The sources | The scene stays the size of its brushes. Bake again to get geometry back; there is none at runtime until you do. |
| **Baked geometry only** | The geometry | The lightest scene. The brushes live in the `.hflevel` and are loaded when the scene opens. |

Changing the setting re-owns what is already in the level, so the next Ctrl+S writes what the setting says rather than what the level happened to be built with.

Whichever setting is on, the scene also carries the records that describe the brushes without being brushes: visgroups and their visibility, groups, arrays, hollows, generators and prefab instances. They are not nodes, so they ride in a `live_registries` property on the `LevelRoot` rather than as children. Before September 2026 they did not ride anywhere, and a level reopened from its scene came back as loose geometry the structure panels could no longer edit. A scene saved back then is repaired on open as far as it can be: a visgroup is put back from the members that still name it, and comes back visible.

**Baked geometry only** needs somewhere to put the brushes. A level with no `.hflevel` path keeps them in the scene regardless, because dropping a level's only copy of its brushes is not a trade worth making silently. If the `.hflevel` is missing when such a scene opens, HammerForge says so rather than opening an empty level.

### Entity I/O Serialization
- Entity I/O connections are stored per-entity in the `io_outputs` key of each entity record.
- Each connection is a Dictionary: `{output_name, target_name, input_name, parameter, delay, fire_once}`.
- Connections are captured by `capture_entity_info()` and restored by `restore_entity_from_info()`.
- Missing `io_outputs` key on load = no connections (backward-compatible).

### Brush Entity Class Serialization
- Brush entity class (`func_detail`, `func_wall`, `trigger_once`, `trigger_multiple`) is stored in the `brush_entity_class` key of each brush record.
- `func_detail` brushes bake into one mesh per material and one collision body, the way the structural path groups, with a convex hull per brush so a pile of clutter still collides as the separate solids it is. A detail brush that carries an entity name or I/O outputs keeps a node of its own instead, because that is the address the runtime finds it by.
- Missing key on load = no entity class (standard structural brush).

## `.map` Import / Export
- Use `.map` to exchange basic brush layouts with other editors.
- Axis-aligned boxes use the optimized primitive path; tilted, clipped, and other non-axis-aligned convex brushes import and export as CUSTOM face geometry.
- Import works the face polygons out rather than reading them off the file. A `.map` face line names three points on an infinite plane, not the corners of a face, and the solid is the intersection of the half spaces behind its planes. A set of planes that closes nothing still imports, on the old reading of the points as corners, so an ill-formed brush arrives wrong rather than not at all.
- Key/value properties round-trip through the supported Classic Quake and Valve 220 adapters, on all three kinds of block: point entities, brush entities, and `worldspawn`. A `func_door` keeps its `speed`, `wait` and `angle`, a trigger keeps the `target` it points at, and the map keeps its `wad` list, its `message` and its `mapversion`. `worldspawn`'s keys live on `LevelRoot.map_worldspawn_properties` and travel in the `.hflevel`.
  - `target`/`targetname` is kept as an ordinary property rather than translated into HammerForge's own I/O. The reverse mapping is not one-to-one, so the pair survives a round trip without the editor guessing what it means.
- Per-face material names round-trip. Each face line names the material its `material_idx` points at, and an import maps that name back to a palette slot by name.
  - The texture field is positional and whitespace delimited, so a palette name with a space in it is written with underscores (`Red Brick` becomes `Red_Brick`). Import matches on the same token.
  - A name the palette does not already hold mints a placeholder slot named after it, so the palette mirrors the file and the Surface panel says `*water1` on the water. A `.map` names a texture without saying where it lives, so a placeholder carries no resource path rather than a guessed one that would resolve to nothing. Loading the palette first still matches the real materials by name.
  - The name is also kept on the face itself, in `FaceData.map_texture`, so an import and an export are lossless in a project with no materials loaded at all. `__default` is written only for a face that has neither a palette slot nor an imported name.
- UV offset, rotation and scale are written in both formats, converted into the units a `.map` uses: the rotation goes out in degrees (`FaceData.uv_rotation` is radians) and the scale goes out as its reciprocal (a `.map` reader divides by the scale field, `_apply_uv_transform()` multiplies by it). A zero or non-finite scale is written as 1 and warned about, since every Quake family compiler divides by it. A negative scale keeps its sign; it mirrors the texture. The offset needs no conversion. Valve 220 additionally carries the texture axes; Classic Quake has no field for them.
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
- The material palette can be saved and loaded independently, from Save Library and Load Library in the Paint tab or via `MaterialManager.save_library()` / `load_library()`.
- Library files are JSON containing material resource paths — portable across projects. A material with no resource path, which is any made in the editor session rather than loaded from disk, cannot be recorded: its slot saves empty and `get_dropped_save_slots()` names it. `save_library()` returns `ERR_SKIP` when no slot could be recorded at all.
- The library path can be stored alongside `.hflevel` saves.

## Prototype Textures
- HammerForge ships with 150 built-in SVG prototype textures at `addons/hammerforge/textures/prototypes/`.
- Click **Refresh Prototypes** in Paint tab → Materials section to batch-load all textures into the palette.
- Once loaded, prototype materials are serialized in `.hflevel` saves, as resource paths. The same rule as the material library applies: a material with no resource path, which is any made in the editor session rather than loaded from disk, cannot be recorded. Saving one now warns and records its class and name, and the slot loads empty.
- Prototype textures are included in the plugin directory and travel with the project automatically.

## Entity Definitions
- Entity types and brush entity classes are loaded from `entities.json` (data-driven, not hardcoded).
- Add your own in `res://hammerforge_entities.json`. That file overlays the plugin's `entities.json`, and an entry with the same classname replaces the plugin one. Prefer it over editing `res://addons/hammerforge/entities.json`, which is overwritten when the plugin is upgraded.
- A `LevelRoot` can point somewhere else through its `entity_definitions_path` export. The point entity palette and the brush entity dropdown both read the same merged result, so a custom point entity is placeable and a custom brush class is assignable without further setup.
- Definitions include `classname`, `description`, `color`, `is_brush_entity`, `properties`, optional `scene_path`, the optional `class` and `scene` which name the Godot node or `PackedScene` a playtest export builds for the entity, and optional `outputs` and `inputs` naming the I/O the class fires and answers to. A property may carry `maps_to` naming the engine property its value is written to. The dock also reads presentation keys straight from the JSON: `label`, `preview`, and `category`.
- `scene_property` names the property an *instance* uses to choose its own model, where `scene` names one for the whole class. `prop_static` uses it: the path a mapper types is instantiated as the entity's preview in the viewport and as the node the bake and the playtest export carry. A path that does not resolve leaves the class's own preview in place and says so in the log.
- `resource_properties` maps a property name to the resource class it holds, for a property that stores a path and a node that wants the thing at the end of it: `ambient_sound`'s Stream is a path a mapper types and an `AudioStream` the player needs. A path that does not resolve leaves the property empty and says so in the log.
- `input_methods` maps an input name to the engine method it means, for a class whose node already implements it: `logic_timer` maps `Start` to `Timer.start()`. See the I/O section of the user guide.
- Keys this list does not mention are carried through to the level root untouched, so a project's own definition file can hold whatever it likes beside the ones the plugin reads.

## Prefabs: `.hfprefab`
- `.hfprefab` files store reusable brush + entity groups as JSON.
- Transforms are stored relative to the group centroid, so prefabs can be placed at any world position.
- Brush IDs and group IDs are stripped on capture; new ones are assigned on instantiation.
- Entity I/O connections are captured and remapped to new entity names when instantiated. The remap runs over the entities the placement just created, not over a name lookup, so an authored name that collides with another copy's node name cannot send it to the wrong one.
- The authored entity name travels verbatim, so placing a prefab twice gives both copies the same name. The I/O remap works off node names, which are made unique on placement; rename the copies yourself if two of them are meant to be told apart by an output.
- Face materials travel by **path**, not by slot number. A face’s material is an index into the *level’s* palette, so a `materials` block records what each referenced slot meant and placement resolves those paths against the destination palette, appending any it does not already hold and rewriting the face indices to match. Placing the same prefab twice does not add the material twice. A material with no `resource_path` cannot be recorded, so its slot is left alone and the face keeps whatever the destination holds there — save the material to disk first if it should travel.
- A recorded material the destination project cannot load is reported by name, and those faces keep the index they had rather than being pointed somewhere wrong.
- A `.hfprefab` written before the `materials` block existed has none, and is placed exactly as it was before.
- Data encoding uses the same `HFLevelIO.encode_variant()` / `decode_variant()` pipeline as `.hflevel` (handles Vector3, Transform3D, Basis, etc.).
- Prefab files are saved to `res://prefabs/` by default. The directory is created automatically on first save.
- Prefabs are portable between projects — just copy `.hfprefab` files to another project's `res://prefabs/` folder.

## Autosave Safety
- Autosave serializes and writes on a background thread. The editor blocks only for the part that has to read the live level: walking the scene and resolving the materials it references. At 400 brushes that is about 50 ms, against about 125 ms of encoding that happens on the thread.
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
