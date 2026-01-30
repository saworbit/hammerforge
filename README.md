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

**HammerForge** is a Godot Editor Plugin that brings classic brush-based level design workflows—inspired by **Hammer Editor** and **TrenchBroom**—directly into the Godot editor. Create complete FPS levels with CSG brushes, subtract carve operations, and one-click baking to optimized static meshes.

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
- **Multiple Shapes**: Box and Cylinder brushes
- **CSG Operations**: Add (union) and Subtract (carve)
- **Grid Snapping**: Configurable 1-128 unit increments

### Editor UX
- **Editor Theme Parity**: Dock styling inherits the active Godot editor theme
- **Quick Snap Presets**: One-click 1/2/4/8/16/32/64 toggles synced with Grid Snap
- **On-Screen Shortcut HUD**: Optional cheat sheet in the 3D viewport
- **Dynamic Editor Grid**: High-contrast shader grid that follows the active axis/brush
- **Material Paint Mode**: Pick an active material and click brushes to apply it
- **Collapsible Dock Sections**: Collapse Settings/Presets/Actions to reduce clutter
- **Physics Layer Presets**: Set baked collision layers with a single dropdown
- **Live Brush Count**: Real-time warning when active CSG gets heavy

### ⌨️ Modifier Keys
| Key | Effect |
|-----|--------|
| `Shift` | Force square base |
| `Shift+Alt` | Force perfect cube |
| `Alt` | Height-only adjustment |
| `X` / `Y` / `Z` | Lock to specific axis |
| `Right-click` | Cancel current operation |

### 🔧 Selection & Manipulation
- **Click to Select** brushes (Shift for multi-select)
- **Hover Highlight** shows the brush under the cursor in Select mode
- **Delete** selected brushes
- **Duplicate** with `Ctrl+D` (grid-snapped offset)
- **Nudge** with Ctrl+Arrow and Ctrl+PageUp/PageDown (arrow keys work when the 3D viewport has focus)
- **Use Godot Gizmos** for move/rotate/scale on selected brushes

### ⚡ Pending Subtract System
- **Stage Your Cuts**: Subtract brushes appear solid red until applied
- **Preview Before Carving**: Position cuts precisely before committing
- **Non-Destructive**: Clear pending cuts without affecting geometry
- **Commit Cuts**: Bake and keep the carve while hiding live CSG

### 🏗️ One-Click Baking
- Converts live CSG to optimized **MeshInstance3D**
- Auto-generates **trimesh collision** (StaticBody3D)
- Removes hidden geometry for better performance
- Neutralizes subtract materials so carved faces match the final material

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
├── addons/
│   └── hammerforge/      ← Copy this folder
│       ├── plugin.cfg
│       ├── plugin.gd
│       ├── level_root.gd
│       ├── dock.gd
│       ├── dock.tscn
│       ├── baker.gd
│       ├── brush_manager.gd
│       ├── brush_instance.gd
│       └── icon.png
└── project.godot
```

Notes:
- `CommittedCuts` stores frozen subtract brushes when "Freeze Commit" is enabled.
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
3. Click "Apply Cuts" to carve
   → Subtract brushes now cut into the geometry
```

### 4. Bake for Performance

```
1. Click "Bake" in the dock
   → Creates optimized static mesh with collision
2. Press Play to test your level!
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
| **Mode** | `Add` - Union geometry / `Subtract` - Carve holes |
| **Shape** | `Box` - Rectangular / `Cylinder` - Round |
| **Size X/Y/Z** | Default brush dimensions |
| **Grid Snap** | Snap increment (1-128 units) |
| **Quick Snap** | Preset snap buttons (1/2/4/8/16/32/64) synced to Grid Snap |
| **Physics Layer** | Preset collision layer mask for baked geometry |
| **Freeze Commit** | Keep committed cuts hidden for later restore (off deletes cuts after commit) |
| **Show HUD** | Toggle the on-screen shortcut legend |
| **Show Grid** | Toggle the editor grid (off by default) |
| **Follow Grid** | Toggle grid follow mode (requires Show Grid) |
| **Debug Logs** | Print HammerForge events to the output console |
| **Live Brushes** | Real-time CSG count with performance warning colors |

### Buttons

| Button | Action |
|--------|--------|
| 🏗️ **Create Floor** | Spawn 1024×16×1024 collidable surface |
| ⚡ **Apply Cuts** | Execute pending subtract operations |
| 🧹 **Clear Pending** | Remove staged cuts without applying |
| 🔥 **Commit Cuts** | Apply + Bake + Remove cut shapes |
| ♻️ **Restore Cuts** | Bring committed cuts back for editing |
| 📦 **Bake** | Convert CSG to optimized mesh |
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
┌─────────────────────────────────────────────────────────┐
│                   HammerForge Plugin                    │
├─────────────────────────────────────────────────────────┤
│  plugin.gd          → EditorPlugin lifecycle & input   │
│  level_root.gd      → Core brush management & CSG ops  │
│  dock.gd/tscn       → UI panel controls                │
│  baker.gd           → CSG → StaticMesh converter       │
│  brush_manager.gd   → Brush instance tracking          │
│  brush_instance.gd  → Individual brush representation  │
└─────────────────────────────────────────────────────────┘
```

### Editor UX Files

- `addons/hammerforge/shortcut_hud.tscn` + `addons/hammerforge/shortcut_hud.gd`: On-screen shortcut legend.
- `addons/hammerforge/editor_grid.gdshader`: Shader-based grid for the editor viewport.

### Node Hierarchy

```
LevelRoot (Node3D)
├── BrushCSG (CSGCombiner3D)      ← Active brushes
│   ├── Brush_001 (CSGBox3D)
│   ├── Brush_002 (CSGCylinder3D)
│   └── ...
├── PendingCuts (CSGCombiner3D)   ← Staged subtracts
└── BakedGeometry (Node3D)        ← Output after bake
    ├── MeshInstance3D
    └── StaticBody3D
```

---

## 🗺️ Roadmap

### ✅ MVP (v0.1.0) - Current
- [x] CAD-style brush creation (Box, Cylinder)
- [x] CSG Add/Subtract operations
- [x] Grid snapping with modifier constraints
- [x] Selection, deletion, duplication, nudge
- [x] Pending subtract system
- [x] One-click baking with collision

### 🔜 Upcoming Features
- [ ] **Undo/Redo** - Full EditorUndoRedoManager integration
- [ ] **More Shapes** - Wedge, Arch, Sphere, Stairs
- [ ] **Texture Support** - Per-face material painting and UV tools
- [ ] **Chunked Baking** - LOD generation for large levels
- [ ] **Entity System** - Spawn points, triggers, lights

### 🔮 Future Modules
- [ ] **TerrainModule** - GPU heightmap sculpting
- [ ] **PrefabModule** - Drag-drop modular assets
- [ ] **AIPathModule** - Navigation mesh helpers
- [ ] **Import/Export** - `.map`, glTF, USD formats

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
