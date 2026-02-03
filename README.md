<p align="center">
  <img src="docs/images/hammerforge_logo.png" alt="HammerForge Logo" width="200" style="max-width: 60%; height: auto;">
</p>

<h1 align="center">🔨 HammerForge</h1>

<p align="center">
  <strong>FPS-Style Level Editor for Godot 4.6+</strong><br>
  <em>Brush-based 3D level design without leaving the editor</em>
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-documentation">Docs</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.6+-478CBF?style=for-the-badge&logo=godot-engine&logoColor=white" alt="Godot 4.6+">
  <img src="https://img.shields.io/badge/Version-0.1.0-green?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/Language-GDScript-purple?style=for-the-badge" alt="GDScript">
</p>

---

## 🎯 What is HammerForge?

**HammerForge** is a Godot Editor Plugin that brings classic brush-based level design workflows—inspired by **Hammer Editor** and **TrenchBroom**—directly into the Godot editor. Create complete FPS levels with lightweight draft brushes, subtract carve operations, and one-click baking to optimized static meshes (CSG is only invoked during Bake).

> **Browser-free. Single-tool. Pure Godot.**

### Why HammerForge?

| Traditional Workflow | HammerForge Workflow |
|---------------------|---------------------|
| Export from external editor → Import → Fix materials → Generate collision | Draw brushes → Bake → Play |
| Multiple tools, multiple formats | One plugin, one editor |
| Constant context switching | Stay in Godot |

---

## ✨ Features

### 🎨 Brush Creation
- **CAD-Style Two-Stage Drawing**
  - Stage 1: Click & drag to define base dimensions
  - Stage 2: Move mouse to set height, click to commit
- **Draft Brush Editing**: Lightweight DraftBrush nodes for fast editor transforms (CSG is generated only during Bake)
- **Shape Palette**: Box, Cylinder, Sphere, Cone, Wedge, Pyramid, Prisms, Ellipsoid, Capsule, Torus, and Platonic solids (mesh shapes scale to brush size)
- **Draft Preview Parity**: Pyramids, prisms, and platonic solids render as lightweight line previews in the editor
- **Brush Operations**: Add (union) and Subtract (carve at bake time)
- **Grid Snapping**: Configurable 1-128 unit increments

### Editor UX
- **Editor Theme Parity**: Dock styling inherits the active Godot editor theme
- **Quick Snap Presets**: One-click 1/2/4/8/16/32/64 toggles synced with Grid Snap
- **On-Screen Shortcut HUD**: Optional cheat sheet in the 3D viewport
- **Dynamic Editor Grid**: High-contrast shader grid that follows the active axis/brush
- **Viewport Brush Gizmos**: Drag face handles to resize DraftBrushes with undo/redo support
- **Gizmo Snapping**: Resize handles respect `grid_snap` for consistent sizing
- **Material Paint Mode**: Pick an active material and click brushes to apply it
- **Entity Selection (early)**: Nodes under `Entities` or tagged `is_entity` are selectable and ignored by bake
- **Entity Palette UI**: Visual dock palette with drag-and-drop entity placement
- **DraftEntity Props (early)**: Schema-driven entity properties with Inspector dropdowns (stored under `data/`)
- **Entity Previews (early)**: Editor-only billboards/meshes from `entities.json`
- **Collapsible Dock Sections**: Collapse Settings/Presets/Actions to reduce clutter
- **Physics Layer Presets**: Set baked collision layers with a single dropdown
- **Live Brush Count**: Real-time count of draft brushes with performance warning colors
- **History Panel (beta)**: Undo/Redo buttons plus a recent action list for HammerForge actions
- **Playtest Button**: One-click bake + launch current scene (with hot-reload signal)
- **Playtest FPS Controller**: Runtime CharacterBody3D with sprint, crouch, jump, head-bob, and FOV stretch
- **Player Start Entity**: Spawn playtests at `Entities/DraftEntity` with `entity_class = "player_start"`

### ⌨️ Modifier Keys
| Key | Effect |
|-----|--------|
| `Shift` | Force square base |
| `Shift+Alt` | Force perfect cube |
| `Alt` | Height-only adjustment |
| `X` / `Y` / `Z` | Lock to specific axis |
| `Right-click` | Cancel current operation |

### 🔧 Selection & Manipulation
- **Click to Select** brushes (Shift/Ctrl/Cmd for multi-select)
- **Hover Highlight** shows the brush under the cursor in Select mode
- **Delete** selected brushes
- **Duplicate** with `Ctrl+D` (grid-snapped offset)
- **Nudge** with Ctrl+Arrow and Ctrl+PageUp/PageDown (arrow keys work when the 3D viewport has focus)
- **Use Godot Gizmos** for move/rotate/scale on selected brushes
- **Resize with Face Handles**: Drag the DraftBrush face handles to resize while the opposite face stays pinned
- **Entities are selectable** when placed under `Entities` or tagged with `is_entity` (not included in bake)

### ⚠️ Known Issues (as of February 3, 2026)
- **Viewport multi-select is limited**: Shift/Ctrl/Cmd-clicking can cap at 2 items.
- **Drag-marquee selection is disabled** in the viewport.
  - **Workaround**: Use the Scene tree to multi-select brushes (Shift/Ctrl), or select one-by-one and duplicate/transform via the tree.

### ⚡ Pending Subtract System
- **Stage Your Cuts**: Subtract brushes appear solid red until applied
- **Preview Before Carving**: Position cuts precisely before committing (carve becomes visible after Bake)
- **Non-Destructive**: Clear pending cuts without affecting geometry
- **Commit Cuts**: Bake and keep the carve while hiding draft brushes (optional freeze keeps cut brushes)

### 🏗️ One-Click Baking
- Builds a temporary CSG tree from DraftBrushes and bakes **MeshInstance3D**
- Auto-generates **trimesh collision** (StaticBody3D) using Add brushes only (Subtracts are excluded)
- Removes hidden geometry for better performance
- Subtract previews do not bleed into baked materials
- **Bake Options**: Merge meshes, auto-LOD generation, lightmap UV2 unwrap, and navmesh baking
- **Chunked Bake**: set `bake_chunk_size` on `LevelRoot` to split large maps into chunk bakes (set `<= 0` to disable)
- **Playtest Flow**: Playtest button bakes then launches the scene; running instances can hot-reload via `res://.hammerforge/reload.lock`

### 💾 Storage & Exchange
- **.hflevel Save/Load**: Store brushes, entities, and level settings in a portable file
- **Autosave**: Background autosave to a configurable `.hflevel` path
- **Import/Export**: `.map` (Quake/TrenchBroom) import/export and `.glb` export for baked geometry

---

## 📦 Installation

### From GitHub

1. **Download** or clone this repository
2. **Copy** the `addons/hammerforge` folder to your project's `addons/` directory
3. **Enable** the plugin:
   - Go to `Project → Project Settings → Plugins`
   - Find "HammerForge" and toggle **Enabled**

### Project Structure
```
your-project/
|-- addons/
|   `-- hammerforge/      <- Copy this folder
|       |-- plugin.cfg
|       |-- plugin.gd
|       |-- level_root.gd
|       |-- dock.gd
|       |-- dock.tscn
|       |-- baker.gd
|       |-- brush_manager.gd
|       |-- brush_instance.gd
|       |-- brush_gizmo_plugin.gd
|       |-- draft_entity.gd
|       |-- entities.json
|       |-- icons/
|       |-- meshes/
|       `-- icon.png
`-- project.godot
```

Notes:
- `DraftBrushes` stores lightweight DraftBrush nodes used during editing (no live CSG).
- `CommittedCuts` stores frozen subtract brushes when "Freeze Commit" is enabled.
- `Entities` stores non-geometry nodes (selection-only, excluded from bake).
- `EditorGrid` (MeshInstance3D) is editor-only and not saved to scenes.
- `LevelRoot` can be a single node; child helpers are created automatically if missing.

---

## 🚀 Quick Start

### 1. Create Your First Level

```
1. Open any 3D scene in Godot
2. Click anywhere in the 3D viewport
   → HammerForge automatically creates a LevelRoot node
3. Click "Create Floor" in the dock
   → Adds a raycast-friendly surface for placement
```

### 2. Draw Your First Brush

```
1. Select "Draw" mode in the dock
2. Choose "Add" operation and "Box" shape
3. Click and drag in the viewport to define the base
4. Release, then move mouse up to set height
5. Click to commit the brush
```

### 3. Carve with Subtract

```
1. Switch to "Subtract" mode
2. Draw a brush that overlaps existing geometry
   → Appears as solid red (pending cut)
3. Click "Apply Cuts" to arm the carve
   → Subtract brushes become active for the next Bake
```

### 4. Bake for Performance

```
1. Click "Bake" in the dock
   → Creates optimized static mesh with collision
2. Click "Playtest" to bake + launch with the playtest controller
   → Place a `player_start` entity for spawn location
```

---

## 🎮 Controls Reference

### Dock Panel

Sections can be collapsed using the toggle button in each header.

| Control | Function |
|---------|----------|
| **Tool** | `Draw` - Create brushes / `Select` - Pick brushes |
| **Paint Mode** | Toggle paint-on-click when Select is active |
| **Active Material** | Pick the material applied by Paint Mode |
| **Mode** | `Add` - Union geometry / `Subtract` - Carve holes (visible after Bake) |
| **Shape** | Select from the dynamic Shape Palette grid |
| **Sides** | Contextual sides control for pyramids/prisms |
| **Size X/Y/Z** | Default brush dimensions |
| **Grid Snap** | Snap increment (1-128 units) |
| **Quick Snap** | Preset snap buttons (1/2/4/8/16/32/64) synced to Grid Snap |
| **Physics Layer** | Preset collision layer mask for baked geometry |
| **Bake Options** | Merge meshes, generate LODs, lightmap UV2 + texel size, and navmesh settings |
| **Freeze Commit** | Keep committed cuts hidden for later restore (off deletes cuts after commit) |
| **Show HUD** | Toggle the on-screen shortcut legend |
| **Show Grid** | Toggle the editor grid (off by default) |
| **Follow Grid** | Toggle grid follow mode (requires Show Grid) |
| **3D View Layout (native)** | Use Godot’s View → Layout → 4 View for Top/Front/Side/3D |
| **Debug Logs** | Print HammerForge events to the output console |
| **Live Brushes** | Real-time draft brush count with performance warning colors |
| **History** | Undo/Redo controls and a recent action list (beta) |
| **Autosave** | Enable background autosave and adjust autosave interval |

### Buttons

| Button | Action |
|--------|--------|
| 🏗️ **Create Floor** | Spawn 1024×16×1024 collidable surface |
| ⚡ **Apply Cuts** | Execute pending subtract operations |
| 🧹 **Clear Pending** | Remove staged cuts without applying |
| 🔥 **Commit Cuts** | Apply + Bake + Remove cut shapes |
| ♻️ **Restore Cuts** | Bring committed cuts back for editing |
| 🧩 **Create DraftEntity** | Spawn a DraftEntity under `Entities` |
| 💾 **Save .hflevel** | Save brushes, entities, and settings to a `.hflevel` file |
| 📂 **Load .hflevel** | Load brushes, entities, and settings from a `.hflevel` file |
| 🧭 **Import .map** | Import Quake/TrenchBroom `.map` brushes and entities |
| 📤 **Export .map** | Export DraftBrushes to a `.map` file |
| 📦 **Export .glb** | Export baked geometry as a `.glb` |
| 🗂 **Set Autosave Path** | Choose the autosave destination for `.hflevel` |
| 📦 **Bake** | Bake DraftBrushes to an optimized mesh (temporary CSG) |
| Playtest | Bake + launch current scene (supports hot-reload) |
| 🗑️ **Clear All** | Remove all brushes |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Delete` | Delete selected brushes |
| `Ctrl+D` | Duplicate selected |
| `Ctrl+Left` `Ctrl+Right` | Nudge X axis |
| `Ctrl+Up` `Ctrl+Down` | Nudge Z axis |
| `Ctrl+PgUp` `Ctrl+PgDn` | Nudge Y axis |
| `X` `Y` `Z` | Lock axis during draw |
| `Shift` | Square base constraint |
| `Shift+Alt` | Cube constraint |
| `Alt` | Height-only mode |
| `Right-click` | Cancel drag |

### HUD and Editor Grid

- **Shortcut HUD**: Toggle with "Show HUD" in the dock. The overlay is informational and does not change your active tool.
- **Dynamic Grid**: Editor-only grid plane driven by a shader for high contrast. Enable with "Show Grid".
- **Tuning**: Adjust `grid_visible`, `grid_follow_brush`, `grid_plane_size`, `grid_color`, and `grid_major_line_frequency` on `LevelRoot` in the Inspector.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [📖 User Guide](docs/HammerForge_UserGuide.md) | Complete usage instructions |
| [🔧 MVP Guide](docs/HammerForge_MVP_GUIDE.md) | Developer implementation guide |
| [📋 Specification](HammerForge_SPEC.md) | Technical architecture & design |
| [📝 Changelog](CHANGELOG.md) | Version history |

---

## 🛠️ Architecture

```
HammerForge Plugin
- plugin.gd -> EditorPlugin lifecycle & input
- level_root.gd -> Core brush management & virtual bake
- dock.gd/tscn -> UI panel controls
- baker.gd -> CSG -> StaticMesh converter
- brush_manager.gd -> Brush instance tracking
- brush_instance.gd -> DraftBrush (Node3D + MeshInstance3D)
- draft_entity.gd -> DraftEntity (schema-driven entity properties)
- brush_gizmo_plugin.gd -> DraftBrush resize handles in the viewport
- hflevel_io.gd -> .hflevel serialization helpers
- map_io.gd -> .map import/export utilities
```

### Editor UX Files

- `addons/hammerforge/shortcut_hud.tscn` + `addons/hammerforge/shortcut_hud.gd`: On-screen shortcut legend.
- `addons/hammerforge/editor_grid.gdshader`: Shader-based grid for the editor viewport.

### Node Hierarchy

```
LevelRoot (Node3D)
├── DraftBrushes (Node3D)         ← Editable draft brushes
│   ├── Brush_001 (DraftBrush)
│   ├── Brush_002 (DraftBrush)
│   └── ...
├── PendingCuts (Node3D)          ← Staged subtracts (DraftBrush)
├── CommittedCuts (Node3D)        ← Hidden frozen cuts (optional)
├── Entities (Node3D)             ← Non-geometry nodes (not baked)
│   └── DraftEntity (Node3D)      ← Schema-driven entity with Inspector props
└── BakedGeometry (Node3D)        ← Output after bake (chunked if enabled)
    └── BakedChunk_x_y_z (Node3D)
        ├── MeshInstance3D
        └── StaticBody3D
    └── BakedNavmesh (NavigationRegion3D)
```

---

## 🗺️ Roadmap

### ✅ MVP (v0.1.0) - Current
- [x] CAD-style brush creation (Box, Cylinder)
- [x] Add/Subtract operations (virtual during edit, baked via CSG)
- [x] Grid snapping with modifier constraints
- [x] Selection, deletion, duplication, nudge
- [x] Pending subtract system
- [x] One-click baking with collision

### 🔜 Upcoming Features
- [ ] **Undo/Redo** - History panel and editor undo hooks (beta)
- [x] **More Shapes** - Wedge, Sphere, Cone, Pyramid, Prisms, Ellipsoid, Capsule, Torus, Platonic solids
- [ ] **Texture Support** - Per-face material painting and UV tools
- [x] **Chunked Baking** - Bake large maps by chunk with `bake_chunk_size`
- [x] **Entity System** - Selectable entities under `Entities` or tagged `is_entity` (excluded from bake)
- [x] **Advanced Baking** - Mesh merging, LOD generation, lightmap UV2 unwrap, and integrated navmesh baking
- [x] **Autosave + .hflevel Storage** - Custom format for brushes + metadata with background autosave
- [x] **Entity Palette UI** - Visual dock palette with drag-and-drop entity placement
- [x] **Import/Export** - `.map` import/export and `.glb` export for baked geometry

### 🔮 Future Modules
- [ ] **TerrainModule** - GPU heightmap sculpting
- [ ] **PrefabModule** - Drag-drop modular assets
- [ ] **AIPathModule** - Navigation mesh helpers
- [ ] **Import/Export** - USD and additional pipelines beyond `.map`/`.glb`

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **🐛 Report Bugs** - Open an issue with reproduction steps
2. **💡 Suggest Features** - Describe your use case
3. **🔧 Submit PRs** - Fork, branch, and submit pull requests

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/hammerforge.git

# Open in Godot 4.6+
# Enable plugin in Project Settings → Plugins
# Edit scripts in addons/hammerforge/
```

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by [Valve's Hammer Editor](https://developer.valvesoftware.com/wiki/Valve_Hammer_Editor)
- Inspired by [TrenchBroom](https://trenchbroom.github.io/)
- Built with [Godot Engine](https://godotengine.org/)

---

<p align="center">
  <strong>Made with ❤️ for the Godot community</strong><br>
  <sub>Star ⭐ this repo if you find it useful!</sub>
</p>

