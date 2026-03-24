# HammerForge Prototype Textures

Last updated: March 24, 2026

HammerForge ships with 150 built-in prototype textures designed for greyboxing and level layout testing. Each texture is a lightweight SVG that renders at any resolution, making it ideal for quick material differentiation during early design phases.

## Overview

Prototype textures let you visually distinguish surfaces without importing external assets. They are organized by **pattern** (shape/style) and **color**, giving you 15 patterns x 10 colors = 150 unique textures.

Common use cases:

- Greyboxing level geometry with distinct surface identifiers.
- Marking directional arrows on floors and walls for flow testing.
- Differentiating rooms, zones, or material regions during layout iteration.

## Available Patterns

| Pattern              | Description                                     |
|----------------------|-------------------------------------------------|
| `arrow_down`         | Directional arrow pointing down                 |
| `arrow_left`         | Directional arrow pointing left                 |
| `arrow_right`        | Directional arrow pointing right                |
| `arrow_up`           | Directional arrow pointing up                   |
| `brick`              | Brick wall pattern                              |
| `checker`            | Checkerboard grid                               |
| `cross`              | Repeating cross / plus pattern                  |
| `diamond`            | Diamond / rhombus tiling                        |
| `dots`               | Regular dot grid                                |
| `hex`                | Hexagonal honeycomb tiling                      |
| `solid`              | Flat color fill with border and label           |
| `stripes_diagonal`   | Diagonal stripe pattern                         |
| `stripes_horizontal` | Horizontal stripe pattern                       |
| `triangles`          | Repeating triangle tiling                       |
| `zigzag`             | Zigzag / chevron pattern                        |

## Available Colors

| Color    | Hex (approximate) |
|----------|--------------------|
| `blue`   | #4488CC            |
| `brown`  | #886644            |
| `cyan`   | #44BBCC            |
| `green`  | #44AA44            |
| `grey`   | #888888            |
| `orange` | #DD8833            |
| `pink`   | #CC6688            |
| `purple` | #8855AA            |
| `red`    | #CC4444            |
| `yellow` | #CCBB33            |

## File Location

All prototype textures are located at:

```
res://addons/hammerforge/textures/prototypes/{pattern}_{color}.svg
```

For example: `res://addons/hammerforge/textures/prototypes/checker_red.svg`

Godot 4.6 automatically imports SVGs as `CompressedTexture2D` resources.

## Usage via Editor UI

1. Open the **Paint** tab in the HammerForge dock.
2. In the **Materials** section, click **Load Prototypes**.
3. All 150 prototype materials are added to the palette.
4. Enable **Face Select Mode** and click faces in the viewport.
5. Select a material from the palette and click **Assign to Selected Faces**.

The "Load Prototypes" button creates `StandardMaterial3D` resources with each SVG set as the albedo texture. Material names follow the format `proto_{pattern}_{color}` (e.g., `proto_checker_red`).

## Usage via GDScript

The `HFPrototypeTextures` class provides a static API for working with prototype textures programmatically.

### Load a single texture

```gdscript
var tex: Texture2D = HFPrototypeTextures.load_texture("brick", "orange")
```

### Create a material

```gdscript
var mat: StandardMaterial3D = HFPrototypeTextures.create_material("checker", "red")
# mat.resource_name == "proto_checker_red"
# mat.albedo_texture is the checker_red.svg texture
```

### Batch-load into MaterialManager

```gdscript
var count := HFPrototypeTextures.load_all_into(level_root.material_manager)
print("%d prototype materials loaded" % count)  # 150
```

### Query available options

```gdscript
var patterns: Array[String] = HFPrototypeTextures.PATTERNS   # 15 entries
var colors: Array[String] = HFPrototypeTextures.COLORS        # 10 entries
var all_paths: Array[String] = HFPrototypeTextures.get_all_texture_paths()  # 150 paths
```

### Check existence

```gdscript
if HFPrototypeTextures.texture_exists("hex", "purple"):
    var tex = HFPrototypeTextures.load_texture("hex", "purple")
```

## API Reference

### `HFPrototypeTextures` (RefCounted)

| Member | Type | Description |
|--------|------|-------------|
| `BASE_DIR` | `String` | `"res://addons/hammerforge/textures/prototypes/"` |
| `PATTERNS` | `Array[String]` | All 15 pattern names, sorted alphabetically |
| `COLORS` | `Array[String]` | All 10 color names, sorted alphabetically |

| Static Method | Returns | Description |
|---------------|---------|-------------|
| `get_texture_path(pattern, color)` | `String` | Resource path for a pattern/color pair |
| `texture_exists(pattern, color)` | `bool` | Whether the texture resource exists on disk |
| `load_texture(pattern, color)` | `Texture2D` | Loaded texture, or `null` if not found |
| `create_material(pattern, color)` | `StandardMaterial3D` | Material with albedo set, or `null` |
| `load_all_into(manager)` | `int` | Loads all 150 into a MaterialManager; returns count |
| `get_all_texture_paths()` | `Array[String]` | All 150 resource paths |

## HTML Preview

Open `docs/prototype_textures_preview.html` in any web browser to see all 150 textures displayed in a searchable grid. This is a self-contained HTML file with all SVGs embedded inline.

## Technical Notes

- All textures are SVG format, ranging from ~200 bytes (arrows, solids) to ~5.5 KB (hex pattern).
- Total disk footprint for all 150 SVGs is under 500 KB.
- Godot's SVG importer converts them to rasterized `CompressedTexture2D` at import time.
- Materials created by `create_material` use `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` for clean rendering at varying distances.
- The catalog uses hardcoded arrays rather than directory scanning, ensuring compatibility with exported builds and headless test environments.

## See Also

- [HammerForge Texture and Materials](HammerForge_Texture_Materials.md) -- per-face material system, UV editing, surface paint.
- [HammerForge User Guide](HammerForge_UserGuide.md) -- general usage documentation.
