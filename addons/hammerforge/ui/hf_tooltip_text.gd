@tool
class_name HFTooltipText
extends RefCounted
## Tooltip text catalog. Extracted from dock.gd's monolithic
## `_apply_all_tooltips`. Each entry maps a dock control-property name to its
## tooltip text. The catalog drives `apply_all()` which looks up each control
## via `dock.get(name)` and assigns the tooltip.
##
## To add a new tooltip: add a `<dock_property>: <text>` pair to TEXTS.
## To override at runtime: pass an extra dict to `apply_all`.

const TEXTS := {
	# --- Build tab: grid + toggles ---
	"grid_snap": "Grid snap size in units\nControls brush placement and nudge step",
	"show_grid": "Show editor grid in 3D viewport",
	"follow_grid": "Grid follows last placed brush position",
	"show_hud": "Show keyboard shortcut overlay in viewport",
	"power_user_overlays":
	"Radial menu, coach marks, and operation replay\nOff by default so Draw → Bake → Test Level stays obvious",
	"debug_logs": "Print debug info to Output panel",
	"_show_subtract_preview":
	"Show AABB overlap between subtract and additive brushes\nThis is an approximation, not live CSG",
	# --- Build tab: brush size & shape ---
	"size_x": "Brush width (X axis) in units",
	"size_y": "Brush height (Y axis) in units",
	"size_z": "Brush depth (Z axis) in units",
	"shape_select": "Brush shape for new brushes",
	"sides_spin": "Side count for polygon shapes (Pyramid, Prism)",
	"commit_freeze": "Keep committed cuts frozen (restorable)\ninstead of deleting them",
	"collision_layer_opt": "Physics collision layer for baked geometry",
	"active_material_button":
	"Brush-level material override for whole brushes\nThis is separate from per-face materials in the Materials tab",
	# --- Build tab: bake options ---
	"bake_merge_meshes": "Merge meshes during bake for better performance",
	"bake_generate_lods": "Generate LOD meshes during bake",
	"bake_unwrap_uv0": "Run Godot UV unwrap on baked meshes (UV0) for complex geometry",
	"bake_lightmap_uv2": "Generate UV2 for lightmap baking",
	"bake_use_face_materials":
	"Bake per-face materials into the final mesh\nTurn off to ignore face assignments and use brush-level materials instead",
	"bake_use_atlas_check":
	"Pack albedo textures into a single atlas to reduce draw calls\nRequires Face Materials enabled; non-textured materials stay separate",
	"bake_navmesh": "Generate navigation mesh during bake",
	"bake_lightmap_texel": "Lightmap texel density (smaller = higher quality)",
	"bake_navmesh_cell_size": "Navigation mesh cell size (XZ)",
	"bake_navmesh_cell_height": "Navigation mesh cell height (Y)",
	"bake_navmesh_agent_height": "Navigation agent height",
	"bake_navmesh_agent_radius": "Navigation agent radius",
	"bake_auto_connectors_check":
	"Auto-generate ramps or stairs between height levels during bake\nRequires at least 2 paint layers at different heights",
	# --- FloorPaint tab ---
	"paint_tool_select":
	"Floor paint tool\nB: Brush | E: Erase | R: Rect | L: Line | K: Bucket | N: Blend",
	"paint_radius": "Floor paint brush radius in grid cells",
	"brush_shape_select": "Brush shape: Square or Circle",
	"paint_layer_select": "Active floor paint layer",
	"paint_layer_add": "Add a new floor paint layer",
	"paint_layer_remove": "Remove the selected floor paint layer",
	"paint_layer_rename": "Rename the selected floor paint layer",
	"region_enable": "Enable region streaming for floor paint data",
	"region_size_spin": "Region size in grid cells (power of two recommended)",
	"region_radius_spin": "Streaming radius in regions around the cursor",
	"region_memory_spin": "Memory budget for loaded regions (MB)",
	"region_grid_toggle": "Show region boundaries in the viewport",
	"heightmap_import": "Import a heightmap image (PNG/EXR) for the active layer",
	"heightmap_generate": "Generate a procedural noise heightmap for the active layer",
	"height_scale_spin": "Height scale multiplier for the heightmap",
	"layer_y_spin": "Vertical Y offset for the active paint layer",
	"blend_strength_spin": "Blend strength when using the Blend paint tool",
	"blend_slot_select": "Blend target slot (B, C, or D)",
	"terrain_slot_a_button":
	"Choose terrain texture for Slot A (base layer)\nBlend between slots with the Blend paint tool",
	"terrain_slot_a_scale": "UV scale for Slot A texture",
	"terrain_slot_b_button":
	"Choose terrain texture for Slot B\nBlend between slots with the Blend paint tool",
	"terrain_slot_b_scale": "UV scale for Slot B texture",
	"terrain_slot_c_button":
	"Choose terrain texture for Slot C\nBlend between slots with the Blend paint tool",
	"terrain_slot_c_scale": "UV scale for Slot C texture",
	"terrain_slot_d_button":
	"Choose terrain texture for Slot D\nBlend between slots with the Blend paint tool",
	"terrain_slot_d_scale": "UV scale for Slot D texture",
	# --- SurfacePaint tab ---
	"paint_target_select": "Paint target: Floor (grid) or Surface (UV)",
	"surface_paint_radius": "Surface paint radius in UV space (0.0 - 1.0)",
	"surface_paint_strength": "Surface paint opacity/strength (0.0 - 1.0)",
	"surface_paint_layer_select": "Active surface paint layer",
	"surface_paint_layer_add": "Add a new surface paint layer",
	"surface_paint_layer_remove": "Remove the selected surface paint layer",
	"surface_paint_texture":
	"Choose the texture for the selected surface-paint layer\nRequires a selected face and an existing paint layer",
	# --- Materials tab ---
	"face_select_mode":
	"Enable per-face texturing\nClick faces in the viewport to select them\nShift+Click adds more faces\nRequired for per-face assign, UV edit, and surface paint",
	"material_add": "Add a material to the palette",
	"material_remove": "Remove selected material from palette",
	"material_load_prototypes":
	"Load built-in prototype textures into the palette\nUse this first if the browser looks empty",
	"material_assign":
	"Apply the selected material to all selected faces\nTip: choose a texture in the browser, then click faces in Face Select Mode",
	"face_clear": "Clear face selection",
	# --- UV tab ---
	"uv_reset":
	"Reset this face to default projected UVs\nUse after stretching or before Fit/Center/Left/Right justify",
	# --- Manage tab ---
	"floor_btn": "Create a default floor brush",
	"apply_cuts_btn": "Move pending cuts into the draft brush tree",
	"clear_cuts_btn": "Remove all pending cuts without applying",
	"commit_cuts_btn": "Apply pending cuts, bake, then freeze/remove cut geometry",
	"restore_cuts_btn": "Restore frozen committed cuts back to draft tree",
	"hollow_btn": "Convert selected solid brush into a hollow room (Ctrl+H)",
	"hollow_thickness": "Wall thickness for the hollow operation",
	"move_floor_btn": "Snap selected brushes to the nearest surface below (Ctrl+Shift+F)",
	"move_ceiling_btn": "Snap selected brushes to the nearest surface above (Ctrl+Shift+C)",
	"tie_entity_btn": "Tag selected brushes as a brush entity class",
	"untie_entity_btn": "Remove brush entity tag from selected brushes",
	"brush_entity_class_opt": "Choose brush entity class (func_detail, trigger, etc.)",
	"justify_fit_btn": "Scale UVs to fit the face exactly",
	"justify_center_btn": "Center UVs on the face",
	"justify_left_btn": "Align UVs to the left edge",
	"justify_right_btn": "Align UVs to the right edge",
	"justify_top_btn": "Align UVs to the top edge",
	"justify_bottom_btn": "Align UVs to the bottom edge",
	"bake_btn": "Bake draft brushes into optimized static meshes",
	"bake_dry_run_btn": "Report what will be baked without generating geometry",
	"validate_btn": "Scan the level for common issues",
	"validate_fix_btn": "Scan and auto-fix common issues",
	"clear_btn": "Remove all brushes and baked geometry",
	"save_hflevel_btn": "Save level to .hflevel file",
	"load_hflevel_btn": "Load level from .hflevel file",
	"import_map_btn": "Import a Quake-style .map file",
	"export_map_btn": "Export level as .map file",
	"export_glb_btn": "Export baked geometry as .glb file",
	"autosave_enabled": "Enable automatic saving at regular intervals",
	"autosave_minutes": "Autosave interval in minutes",
	"autosave_path_btn": "Set the autosave file path",
	"autosave_keep": "Keep the last N autosave history files",
	"export_settings_btn": "Export editor preferences to a settings file",
	"import_settings_btn": "Import editor preferences from a settings file",
	"save_preset_btn": "Save current brush settings as a reusable preset",
	"quick_play_btn": "Bake and play the current scene",
	"clip_btn": "Split selected brush along nearest axis plane (Shift+X)",
	# --- Entities tab ---
	"create_entity_btn": "Create a new entity at the cursor position",
	"io_output_name": "Output event name (e.g. OnTrigger, OnDamaged)",
	"io_target_name": "Target entity name to fire the input on",
	"io_input_name": "Input action on target entity (e.g. Open, Kill)",
	"io_parameter": "Optional parameter string passed to the input",
	"io_delay": "Delay in seconds before firing the input",
	"io_fire_once": "If checked, connection fires only once then auto-removes",
	"io_add_btn": "Add an output connection to the selected entity",
	"io_remove_btn": "Remove the selected output connection",
}


## Set tooltip text on a control. Caches the original text in
## "default_tooltip" meta so the toolbar contextual-hint system can restore
## it after temporary overrides.
static func set_tooltip(control: Control, text: String) -> void:
	if not control:
		return
	if not control.has_meta("default_tooltip"):
		control.set_meta("default_tooltip", text)
	control.tooltip_text = text


## Walk the catalog and apply each tooltip to its named dock property. Skips
## entries whose control isn't present yet (e.g. disabled features).
static func apply_all(dock: Object) -> void:
	if not is_instance_valid(dock):
		return
	for prop_name in TEXTS:
		var control = dock.get(prop_name)
		if control:
			set_tooltip(control, TEXTS[prop_name])


## Apply tooltips for the snap quick-buttons (which carry their snap value
## as meta). Must be called separately because the catalog can't enumerate
## dynamic snap values.
static func apply_snap_buttons(snap_buttons: Array) -> void:
	for button in snap_buttons:
		if button and button.has_meta("snap_value"):
			set_tooltip(button, "Quick snap: %s units" % str(button.get_meta("snap_value")))
