# Core-Loop Freeze Implementation Plan

> **For agentic workers:** Execute inline in this session. Tasks are tightly coupled (prefs → plugin → dock → docs).

**Goal:** Make Draw → material → entity → bake → Test Level the default HammerForge product, with extra overlays opt-in, dead code gone, core systems tested, and docs matching the code.

**Architecture:** A `power_user_overlays` pref (default false) gates radial menu, coach marks, and operation replay. Command palette, context toolbar, tutorial, Space context menu, and HUD stay on. Brush cache is the brush-list authority; `BrushManager` is a null-safe legacy mirror. Unused scripts are deleted.

**Tech Stack:** Godot 4.7.1 GDScript, GUT, existing coordinator + subsystem layout.

## Global Constraints

- Godot 4.7+ (`C:\Godot\Godot_v4.7.1-stable_win64_console.exe` for tests)
- No live CSG while editing
- LevelRoot remains the public API
- Keyboard shortcuts go through HFKeymap
- UTF-8 source files; no new dependencies
- Default UX is the core loop; power-user overlays are opt-in
- Subtract preview remains AABB overlap and must be labeled as such

---

### Task 1: Power-user overlays pref

**Files:**
- Modify: `addons/hammerforge/hf_user_prefs.gd`
- Modify: `addons/hammerforge/plugin.gd`
- Modify: `addons/hammerforge/dock.gd`
- Modify: `addons/hammerforge/ui/manage_tab_builder.gd`
- Modify: `addons/hammerforge/ui/hf_tooltip_text.gd`
- Test: `tests/test_user_prefs.gd`, `tests/test_bugfix_regressions.gd`, `tests/test_manage_tab_builder.gd`

**Produces:**
- `HFUserPrefs._defaults()["power_user_overlays"] == false`
- `HFUserPrefs.is_power_user_overlays_enabled() -> bool`
- `EditorPlugin.should_install_power_user_overlays(prefs) -> bool`
- Dock checkbox `power_user_overlays` in Test → Settings, default unchecked
- Plugin does not create radial/coach/replay unless the pref is true
- Radial / replay hotkeys toast when overlays are off

### Task 2: Dead code deletion

**Files:**
- Delete: `addons/hammerforge/ui/hf_welcome_panel.gd` (+ uid)
- Delete: `addons/hammerforge/brush_prefab.gd` (+ uid)
- Delete: `addons/hammerforge/debug_heightmap.gd` (+ uid)
- Delete: `addons/hammerforge/_archive/`
- Modify: `addons/hammerforge/dock.gd` (drop unused WelcomePanel preload)

### Task 3: Brush cache authority

**Files:**
- Modify: `addons/hammerforge/systems/hf_brush_system.gd`
- Test: `tests/test_brush_system.gd` (new)

**Produces:**
- `get_cached_brushes() -> Array`
- `get_cached_brush_count() -> int`
- All `brush_manager` writes null-safe
- `create_brush_from_info` / `delete_brush` keep cache as source of truth even when `brush_manager` is null

### Task 4: Core characterization tests

**Files:**
- Test: `tests/test_brush_system.gd`
- Test: `tests/test_baker.gd` (add cache/empty-merge cases if missing)
- Test: `tests/test_paint_system.gd` (new focused CRUD if missing)

### Task 5: Subtract preview honesty

**Files:**
- Modify: `addons/hammerforge/ui/manage_tab_builder.gd`
- Modify: `addons/hammerforge/ui/hf_tooltip_text.gd`
- Modify: `docs/HammerForge_Design_Constraints.md`

### Task 6: Docs match reality

**Files:**
- Modify: `addons/hammerforge/plugin.cfg`
- Modify: `README.md`, `DEVELOPMENT.md`, `ROADMAP.md`, `HammerForge_SPEC.md`
- Modify: `docs/HammerForge_Editor_Smoke_Checklist.md` (core-loop first)
