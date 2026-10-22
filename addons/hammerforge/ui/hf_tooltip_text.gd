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

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

const TEXTS := {
	# --- Build tab: grid + toggles ---
	"grid_snap": "Grid snap size in metres\nControls brush placement and nudge step",
	"show_grid": "Show editor grid in 3D viewport",
	"follow_grid": "Grid follows the cursor along its current plane; its height stays fixed",
	"show_hud": "Show keyboard shortcut overlay in viewport",
	"power_user_overlays":
	"Radial menu, coach marks, and operation replay\nOff by default so Draw → Bake → Test Level stays obvious",
	"size_at_cursor":
	"Show the brush's size beside the cursor while drawing, and the depth while extruding\nA typed number shows in brackets",
	"draw_hover_preview":
	"Before you click, tint the face a draw would start on and mark the snapped start point\nBlue level with the grid, green on a raised face, amber on one that is not flat, violet with Draw on Face",
	"show_selection_size":
	"Label the width, depth and height of the selection's bounds in the viewport\nFaces picked in Face Select are measured instead of their brushes",
	"debug_logs": "Print debug info to Output panel",
	"_show_subtract_preview":
	"Show the live CSG cut between subtract and additive DraftBrushes\nOverlapping brushes only — not a full-level bake",
	# --- Build tab: brush size & shape ---
	"size_x": "Brush width (X axis) in metres",
	"size_y": "Brush height (Y axis) in metres",
	"size_z": "Brush depth (Z axis) in metres",
	"shape_select": "Brush shape for new brushes",
	"sides_spin":
	"Sides of a pyramid, or segments round a cylinder, cone, sphere, ellipsoid, capsule or torus\nMore is smoother and costs more faces",
	"commit_freeze": "Keep committed cuts frozen (restorable)\ninstead of deleting them",
	"collision_layer_opt": "Physics collision layer for baked geometry",
	"active_material_button":
	"The whole-brush material new brushes are made with: Draw, Polygon, Path, structures and dropped presets\nPaint mode puts it on a clicked brush. Saved with the scene\nThis is separate from per-face materials in the Materials tab",
	"clear_active_material_button":
	"New brushes go back to the translucent default\nBrushes already made keep their material",
	# --- Build tab: bake options ---
	"bake_profile_opt":
	"Sets the bake options below in one step. Undo puts them back\nEditing: Merge Meshes and Generate LODs off, for a fast bake while you build\nShipping: both on, for a fast frame in the game\nBoth leave Lightmap UV2, Navmesh, Occluders and Chunk Size alone; save your own profile to keep those\nCustom: the options match no profile",
	"bake_profile_name": "The name Save keeps the options under, and Delete removes",
	"bake_profile_save_btn":
	"Keep every option below under this name, in your preferences\nA profile of the same name is replaced",
	"bake_profile_delete_btn":
	"Delete the saved profile of this name. Press twice; it cannot be undone",
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
	"material_remove_unused":
	"Drop every palette slot no face is using\nRefresh Prototypes adds 150; this is the way back",
	"material_replace":
	"Replace one material with another on every face that wears it\nAcross the level, the selection or what is shown, as one undo step",
	"material_clear":
	"Empty the palette\nFaces that used a slot become unset, and keep their geometry",
	"material_save_library":
	"Write the palette out as a JSON library\nA material made here has to be saved to disk first, or its slot saves empty",
	"material_load_library":
	"Read a palette back from a JSON library\nA material the file names but cannot find leaves its slot empty",
	"material_assign":
	"Apply the selected material to all selected faces\nTip: choose a texture in the browser, then click faces in Face Select Mode",
	"face_clear": "Clear face selection",
	"face_select_xray":
	"X-ray ({toggle_face_xray})\nThe face box takes every face inside it, covered or facing away\nA brush you hid is still left out",
	# --- UV tab ---
	"uv_reset":
	"Reset this face to default projected UVs\nUse after stretching or before Fit/Center/Left/Right justify",
	"uv_apply_look_btn":
	"Give every selected face the look the Texture Picker (T) last read ({apply_picked_look})\nMaterial, projection, scale, offset and rotation, as one undo step\nA hand-made UV layout on a selected face is cleared so the copied settings show",
	# --- Manage tab ---
	"floor_btn": "Create a default floor brush",
	"apply_cuts_btn": "Move pending cuts into the draft brush tree",
	"clear_cuts_btn": "Remove all pending cuts without applying",
	"commit_cuts_btn": "Apply pending cuts, bake, then freeze/remove cut geometry",
	"restore_cuts_btn": "Restore frozen committed cuts back to draft tree",
	"hollow_btn": "Convert selected solid brush into a hollow room ({hollow})",
	"hollow_thickness": "Wall thickness for the hollow operation",
	"move_floor_btn": "Snap selected brushes to the nearest surface below ({move_to_floor})",
	"move_ceiling_btn": "Snap selected brushes to the nearest surface above ({move_to_ceiling})",
	"snap_to_grid_btn":
	"Move each selected brush the least distance that puts its corner on the grid ({snap_to_grid})\nSize and rotation stay",
	"tie_entity_btn": "Tag selected brushes as a brush entity class",
	"untie_entity_btn": "Remove brush entity tag from selected brushes",
	"brush_entity_class_opt": "Choose brush entity class (func_detail, trigger, etc.)",
	"brush_entity_name_edit":
	"Name this entity so I/O can target it\nBrushes tied under one name are one entity",
	"justify_fit_btn": "Scale UVs to fit the face exactly",
	"justify_center_btn": "Center UVs on the face",
	"justify_left_btn": "Align UVs to the left edge",
	"justify_right_btn": "Align UVs to the right edge",
	"justify_top_btn": "Align UVs to the top edge",
	"justify_bottom_btn": "Align UVs to the bottom edge",
	"uv_align_face_btn":
	"Lay every selected face's texture in the face's own plane (Face projection)\nU level along the face, V down its slope, so a ramp repeats as a wall does\nKeeps scale, offset and rotation; one undo step",
	"uv_wrap_btn":
	"Carry the selected face's texture over an edge: click a face beside it, then the next one\nEach click is one undo step and the clicked face carries it on\nEsc or right click ends",
	"uv_link_btn":
	"Make the selected faces one surface: they share one mapping\nMoving, resizing, cutting or reshaping one keeps it on the surface, and a group last fitted is fitted again\nOne undo step",
	"uv_unlink_btn": "The selected faces stop being one surface, each keeping the texture it shows",
	"uv_select_group_btn": "Select every face linked with the selected face",
	"uv_align_world_btn":
	"Lay every selected face's texture along the world axes (Box UV)\nKeeps scale, offset and rotation; one undo step",
	"justify_fit_u_btn":
	"Fit one repeat across the face's width, keeping the texture's aspect\nThe texture repeats down the face",
	"justify_fit_v_btn":
	"Fit one repeat to the face's height, keeping the texture's aspect\nThe texture repeats along the wall",
	"uv_scale_link":
	"Link U and V\nTyping one sets the other to the same size, each keeping its sign",
	"uv_scale_up_btn": "Scale x2: the texture repeats twice as often\nOn every selected face",
	"uv_scale_down_btn":
	"Scale /2: the texture repeats half as often\nOn every selected face, down to the smallest step of 0.01",
	"uv_flip_u_btn": "Mirror the texture along U on every selected face, about the face's middle",
	"uv_flip_v_btn": "Mirror the texture along V on every selected face, about the face's middle",
	"uv_rotate_90_btn":
	"Turn the texture a quarter on every selected face, about the face's middle",
	"uv_snap_check":
	"Snap a dragged UV corner to the grid\nHold Ctrl (Cmd on macOS) while dragging to place it freely",
	"uv_snap_preset_opt": "UV snap step, in repeats of the texture",
	"uv_texture_gizmo_check":
	"Drag in the viewport to move the texture on the faces Face Select picked\nThe middle square slides it a grid step at a time, an axis end stretches it (Shift: both), the ring turns it by Selection Tools > Step\nRight click or Escape puts it back",
	"uv_snap_step_spin": "UV snap step, in repeats of the texture",
	"bake_btn": "Bake draft brushes into optimized static meshes",
	"bake_dry_run_btn": "Report what will be baked without generating geometry",
	"validate_btn": "Scan the level for common issues",
	"validate_fix_btn": "Scan and auto-fix common issues",
	"clear_btn": "Remove all brushes and baked geometry",
	"save_hflevel_btn": "Save level to .hflevel file",
	"load_hflevel_btn": "Load level from .hflevel file",
	"import_map_btn": "Import a Quake-style .map file",
	"export_map_btn": "Export level as .map file",
	"map_scale_spin":
	(
		"How many .map units one metre is, for both import and export.\n"
		+ "32 is the Quake-family convention: a player is 56 units there and 1.6 here.\n"
		+ "A file that records its own figure is imported at that one instead."
	),
	"export_glb_btn": "Export baked geometry as .glb file",
	"autosave_enabled": "Enable automatic saving at regular intervals",
	"autosave_minutes": "Autosave interval in minutes",
	"autosave_path_btn": "Set the autosave file path",
	"autosave_keep": "Keep the last N autosave history files",
	"export_settings_btn": "Export editor preferences to a settings file",
	"import_settings_btn": "Import editor preferences from a settings file",
	"reset_tool_settings_btn":
	(
		"Put every tool's settings back to their defaults: the Build tab's shape, Sides,"
		+ " Solid/Cutout, snaps, Hollow and Bevel, the Structure section, and the"
		+ " Polygon, Path and Decal tools"
	),
	"save_preset_btn": "Save current brush settings as a reusable preset",
	"quick_play_btn": "Bake and play the current scene",
	"clip_btn": "Split selected brush along nearest axis plane ({clip})",
	# --- Entities tab ---
	"create_entity_btn": "Create a new entity at the cursor position",
	"io_output_name": "Output event name (e.g. OnTrigger, OnDamaged)",
	"io_target_name": "Target entity name to fire the input on",
	"io_input_name": "Input action on target entity (e.g. Open, Kill)",
	"io_parameter": "Optional parameter string passed to the input",
	"io_delay": "Delay in seconds before firing the input",
	"io_fire_once": "If checked, connection fires only once then auto-removes",
	"io_add_btn": "Add an output connection to the selected entity",
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
## One tooltip, with every `{action}` rendered against `keymap`.
##
## The chords in this catalogue are tokens rather than literals: the keymap is
## rebindable, and a tooltip naming a chord that no longer does anything is
## worse than one naming none.
static func text_for(prop_name: String, keymap = null) -> String:
	var text := str(TEXTS.get(prop_name, ""))
	if keymap == null:
		keymap = HFKeymapType.load_or_default("")
	return keymap.format_chords(text)


static func apply_all(dock: Object) -> void:
	if not is_instance_valid(dock):
		return
	var keymap = dock.get("_keymap")
	for prop_name in TEXTS:
		var control = dock.get(prop_name)
		if control:
			set_tooltip(control, text_for(prop_name, keymap))


## Apply tooltips for the snap quick-buttons (which carry their snap value
## as meta). Must be called separately because the catalog can't enumerate
## dynamic snap values.
static func apply_snap_buttons(snap_buttons: Array) -> void:
	for button in snap_buttons:
		if button and button.has_meta("snap_value"):
			set_tooltip(button, "Quick snap: %s m" % str(button.get_meta("snap_value")))
