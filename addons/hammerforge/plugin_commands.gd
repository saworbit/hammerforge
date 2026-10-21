@tool
class_name HFPluginCommands
extends RefCounted
## Shared command dispatch for the context toolbar, hotkey palette, viewport
## context menu, and radial menu, and the state those surfaces read to decide
## what they offer. Surfaces keep their own root/selection guards.
##
## The arms below are what each command does. What it is called, whether it needs
## a level and what it needs selected are in `HFCommandRegistry`, and only an id
## listed there is run.

const LevelRootType = preload("level_root.gd")
const HFUndoNavType = preload("ui/hf_undo_nav.gd")
const HFInputStateType = preload("input_state.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFBrushConversion = preload("hf_brush_conversion.gd")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
const HFLog = preload("hf_log.gd")
const HFPluginDropHandler = preload("plugin_drop_handler.gd")
const HFPluginEditActions = preload("plugin_edit_actions.gd")
const HFPluginSelectionCommands = preload("plugin_selection_commands.gd")
const HFPluginSelectionState = preload("plugin_selection_state.gd")
const HFPluginTransformTools = preload("plugin_transform_tools.gd")
const HFPluginVertexOps = preload("plugin_vertex_ops.gd")
const HFPluginBrushStamp = preload("plugin_brush_stamp.gd")
@warning_ignore_restore("shadowed_global_identifier")


## Whether the palette must refuse `action` when there is no level. These act on
## LevelRoot-owned state or scene content and must not create a level as a side
## effect of using the command palette. Level creation is reserved for explicit
## setup actions and the first intentional Draw press in the viewport.
static func requires_existing_root(action: String) -> bool:
	return HFCommandRegistry.needs_level(action)


const TOOL_SWITCH_ACTIONS := [
	"tool_draw",
	"tool_select",
	"extrude_up",
	"extrude_down",
	"tool_extrude_up",
	"tool_extrude_down",
	"tool_extrude",
	"tool_extrude_down_alt",
]


## What every command surface reads to decide what it offers: the tool and mode,
## what is selected and what it belongs to, and what is waiting to be applied.
## The context toolbar and the palette get it on each HUD update and the viewport
## menu as it opens. Each adds only its own keys on top, so a key one surface
## reads is set for all of them (#1450).
static func build_command_state(plugin: Object, root: Node, tool_id: int) -> Dictionary:
	var state := {}
	if plugin == null:
		return state
	var dock = plugin.get("dock")
	var registry = plugin.get("_tool_registry")
	state["has_root"] = root != null
	state["tool"] = tool_id
	state["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	state["paint_mirror_x"] = dock.get_paint_mirror_x_enabled() if dock else false
	state["paint_mirror_z"] = dock.get_paint_mirror_z_enabled() if dock else false
	state["vertex_mode"] = plugin._vertex_mode
	state["is_subtract"] = dock.get_operation() != 0 if dock else false  # 0 = UNION
	state["has_active_external_tool"] = (registry.has_active_external_tool() if registry else false)
	# The toolbar's Repeat button: what it would place, and whether it is armed.
	var last_drawn: Dictionary = {}
	if root and root.get("drag_system"):
		last_drawn = root.drag_system.last_drawn
		state["repeat_label"] = HFPluginBrushStamp.label(last_drawn, float(root.grid_snap))
	state["repeat_shape"] = HFPluginBrushStamp.shape_key(last_drawn)
	var stamp = plugin.get("_brush_stamp")
	state["repeat_armed"] = stamp != null and stamp.armed

	# Input mode
	var input_mode := 0
	if root and root.input_state:
		input_mode = root.input_state.mode
		var dims = root.input_state.get_drag_dimensions()
		state["dimensions"] = HFInputStateType.format_dimensions(dims, root.grid_snap)
	state["input_mode"] = input_mode

	# Count from the authoritative editor selection. Mixed native/HammerForge
	# selections must remain visible to every action surface so none of them can
	# silently mutate only the managed subset.
	var selection_nodes = plugin._current_selection_nodes()
	state["mixed_selection"] = (
		plugin.classify_selection_scope(selection_nodes, root) == HFPluginSelectionState.SCOPE_MIXED
		if root
		else false
	)
	var brush_count := 0
	var entity_count := 0
	for node in selection_nodes:
		if node is DraftBrush:
			brush_count += 1
		elif root and root.has_method("is_entity_node") and root.is_entity_node(node):
			entity_count += 1
	state["brush_count"] = brush_count
	state["entity_count"] = entity_count
	# Godot nodes Convert to Brushes takes, so the viewport menu can offer it.
	var convertible_count := 0
	for node in selection_nodes:
		if not (node is DraftBrush) and HFBrushConversion.is_convertible_kind(node):
			convertible_count += 1
	state["convertible_count"] = convertible_count

	# I/O connection summary for entity context toolbar
	if entity_count > 0 and root and root.has_method("get_connection_summary"):
		var first_entity: Node = null
		for node in selection_nodes:
			if root.has_method("is_entity_node") and root.is_entity_node(node):
				first_entity = node
				break
		if first_entity:
			var summary = root.get_connection_summary(first_entity.name)
			var triggers: int = summary.get("triggers", 0)
			var triggered_by: int = summary.get("triggered_by", 0)
			var parts: Array = []
			if triggers > 0:
				parts.append("%d out" % triggers)
			if triggered_by > 0:
				parts.append("%d in" % triggered_by)
			if not parts.is_empty():
				state["io_summary"] = " | ".join(parts)

	# The toolbar's Highlight button and the viewport menu's check item both show
	# the level's own highlight, and toggle from it.
	if root and root.get("io_visualizer") and root.io_visualizer:
		state["highlight_connected"] = root.io_visualizer.highlight_connected

	# Face selection count
	var face_count := 0
	if root and root.get("face_selection") is Dictionary:
		for key in root.face_selection.keys():
			var indices = root.face_selection.get(key, [])
			face_count += indices.size()
	state["face_count"] = face_count
	state["texture_gizmo"] = dock.is_texture_gizmo_enabled() if dock else false

	# Pending cut count for "Apply Cuts" button visibility
	var pending_cut_count := 0
	if root and root.pending_node:
		for child in root.pending_node.get_children():
			if child is DraftBrush:
				pending_cut_count += 1
	state["pending_cut_count"] = pending_cut_count
	state["bake_preview_active"] = plugin._bake_preview_active
	state["bake_disabled"] = dock._bake_disabled if dock else false
	if root and root.get("paint_tool"):
		state["paint_connector_pending"] = root.paint_tool._pending_connector_defs.size()

	# Prefab instance info for context toolbar badge
	if root and root.prefab_system and not plugin.hf_selection.is_empty():
		var first_node = plugin.hf_selection[0]
		var pfb_rec = (
			root.prefab_system.instance_of(first_node)
			if is_instance_valid(first_node) and first_node is Node
			else null
		)
		if pfb_rec:
			state["prefab_source"] = pfb_rec.source_path
			state["prefab_variant"] = pfb_rec.variant_name
			state["prefab_linked"] = pfb_rec.linked

	# The structure a selected piece belongs to, for the toolbar's Update and
	# Detach. Read through the record: the tag on the brush only points at it.
	if root and root.has_method("generator_for_id"):
		for node in plugin.hf_selection:
			if not (is_instance_valid(node) and node is DraftBrush):
				continue
			var tag := str(node.get_meta(HFGeneratorSystem.GENERATOR_META, ""))
			var record = root.generator_for_id(tag) if tag != "" else null
			if record:
				state["structure_type"] = record.type
				break
	return state


static func execute(plugin: Object, action: String, args: Array = []) -> void:
	if plugin == null or action.is_empty():
		return
	# A surface naming an id the table does not have would otherwise fall through
	# the match and do nothing, with nothing said.
	if not HFCommandRegistry.dispatches(action):
		HFLog.warn("HammerForge has no command '%s'" % action)
		return
	var root: Node = plugin.active_root if plugin.get("active_root") else plugin._get_level_root()
	var dock = plugin.get("dock")
	if action in TOOL_SWITCH_ACTIONS and root:
		plugin._prepare_tool_transition(root)
		if dock:
			dock.highlight_tab("Brush")
	match action:
		"toggle_operation":
			plugin._on_context_toggle_operation()
		"toggle_paint_mode":
			plugin._toggle_paint_mode()
		"quick_play":
			if dock:
				dock._on_quick_play()
		"validate_level":
			if dock:
				dock._on_validate_level()
		"tool_draw":
			plugin._deactivate_external_tool()
			if dock and dock.tool_draw:
				dock.tool_draw.button_pressed = true
		"tool_select":
			plugin._deactivate_external_tool()
			if dock and dock.tool_select:
				dock.tool_select.button_pressed = true
		"extrude_up", "tool_extrude_up", "tool_extrude":
			plugin._deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(1)
				plugin._update_hud_context()
		"extrude_down", "tool_extrude_down", "tool_extrude_down_alt":
			plugin._deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(-1)
				plugin._update_hud_context()
		"repeat_brush":
			plugin._ensure_brush_stamp().arm(plugin, root)
		"hollow":
			plugin._hollow_selected(root)
		"clip":
			plugin._clip_selected(root)
		"clip_to_face":
			plugin._clip_to_face_plane_selected(root)
		"create_arch":
			if dock:
				dock._on_create_structure()
		"update_structure":
			if dock:
				dock._on_update_structure()
		"detach_structure":
			if dock:
				dock._on_detach_structure()
		"carve":
			plugin._carve_selected(root)
		"merge":
			plugin._merge_selected(root)
		"intersect":
			plugin._intersect_selected(root)
		"rotate_ccw":
			plugin._rotate_selected(root, 1)
		"rotate_cw":
			plugin._rotate_selected(root, -1)
		"flip_selection":
			plugin._flip_selected(root)
		"mirror_copy":
			HFPluginEditActions.mirror_copy_selected(plugin, root)
		"reset_rotation":
			plugin._reset_rotation_selected(root)
		"apply_rotation_scale":
			HFPluginEditActions.apply_rotation_scale_selected(plugin, root)
		"convert_to_brushes":
			HFPluginEditActions.convert_selected_to_brushes(plugin, root)
		"offset_selection":
			HFPluginTransformTools.open_offset(plugin, root)
		"pick_pivot":
			HFPluginTransformTools.arm_pivot_pick(plugin, root)
		"clear_pivot":
			HFPluginTransformTools.clear_pivot(plugin, root)
		"duplicate":
			plugin._duplicate_selected(root)
		"copy":
			plugin._copy_selection(root)
		"paste":
			plugin._paste_clipboard(root)
		"delete":
			plugin._delete_selected(root)
		"group":
			plugin._group_selected(root)
		"ungroup":
			plugin._ungroup_selected(root)
		"move_to_floor":
			plugin._move_selected_to_floor(root)
		"move_to_ceiling":
			plugin._move_selected_to_ceiling(root)
		"snap_to_grid":
			HFPluginEditActions.snap_selected_to_grid(plugin, root)
		"shape_box":
			if dock and dock.shape_select:
				dock.shape_select.select(0)
				dock._on_shape_selected(0)
		"shape_cylinder":
			if dock and dock.shape_select:
				dock.shape_select.select(1)
				dock._on_shape_selected(1)
		"shape_sphere":
			if dock and dock.shape_select:
				dock.shape_select.select(2)
				dock._on_shape_selected(2)
		"shape_cone":
			if dock and dock.shape_select:
				dock.shape_select.select(3)
				dock._on_shape_selected(3)
		"justify_fit":
			if dock:
				dock._on_justify("fit")
		"justify_center":
			if dock:
				dock._on_justify("center")
		"justify_left":
			if dock:
				dock._on_justify("left")
		"justify_right":
			if dock:
				dock._on_justify("right")
		"justify_top":
			if dock:
				dock._on_justify("top")
		"justify_bottom":
			if dock:
				dock._on_justify("bottom")
		"justify_fit_u":
			if dock:
				dock._on_justify("fit_u")
		"justify_fit_v":
			if dock:
				dock._on_justify("fit_v")
		"uv_flip_u":
			if dock:
				dock._on_uv_edit("flip_u")
		"uv_flip_v":
			if dock:
				dock._on_uv_edit("flip_v")
		"uv_rotate_90":
			if dock:
				dock._on_uv_edit("rotate_90")
		"apply_to_brush":
			if dock:
				dock._apply_material_to_whole_brush()
		"apply_last_texture":
			plugin._apply_last_texture(root)
		"apply_picked_look":
			if dock:
				dock._on_apply_picked_look()
		"texture_gizmo":
			# The toolbar's button says which way; the palette and a key switch it.
			if dock:
				dock.set_texture_gizmo_enabled(
					bool(args[0]) if not args.is_empty() else not dock.is_texture_gizmo_enabled()
				)
		# Apply Favorite 1 to 9, Alt+1 to Alt+9.
		_ when action.begins_with("apply_favorite_"):
			HFPluginMaterialCommands.apply_favorite(
				plugin, action.trim_prefix("apply_favorite_").to_int()
			)
		"entity_io", "entity_props":
			if dock:
				dock.main_tabs.current_tab = 2
		"highlight_connected":
			if root and root.has_method("set_highlight_connected"):
				var pressed: bool = args[0] if not args.is_empty() else false
				root.set_highlight_connected(pressed)
			if dock:
				dock.sync_wiring_highlight_state()
		"axis_x":
			if root:
				root.set_axis_lock(LevelRootType.AxisLock.X, true)
				plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
		"axis_y":
			if root:
				root.set_axis_lock(LevelRootType.AxisLock.Y, true)
				plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
		"axis_z":
			if root:
				root.set_axis_lock(LevelRootType.AxisLock.Z, true)
				plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
		"vertex_edit":
			plugin._toggle_vertex_mode(root)
		"vertex_submode":
			if root and root.vertex_system:
				root.vertex_system.sub_mode = 0
		"edge_submode":
			if root and root.vertex_system:
				root.vertex_system.sub_mode = 1
		"vertex_edge_mode":
			if root and root.vertex_system:
				var current: int = root.vertex_system.sub_mode
				root.vertex_system.sub_mode = 1 if current == 0 else 0
		"vertex_merge":
			if root and root.vertex_system:
				plugin._vertex_merge_selected(root)
		"vertex_split", "vertex_split_edge":
			if root and root.vertex_system:
				plugin._vertex_split_selected_edge(root)
		"vertex_clip_convex":
			if root and root.vertex_system:
				plugin._vertex_clip_to_convex(root)
		"vertex_snap_to_grid":
			if root:
				HFPluginVertexOps.snap_selected_to_grid(plugin, root)
		"vertex_exit":
			plugin._toggle_vertex_mode(root)
		"select_all":
			plugin._select_all_nodes(root)
		"deselect_all":
			plugin._deselect_all_nodes(root)
		"select_similar":
			plugin._select_similar(root)
		"selection_filter":
			plugin._show_selection_filter()
		"grow_selection":
			HFPluginSelectionCommands.grow_selection(plugin, root)
		"shrink_selection":
			HFPluginSelectionCommands.shrink_selection(plugin, root)
		"toggle_face_xray":
			HFPluginSelectionCommands.toggle_face_xray(plugin)
		"toggle_selection_size":
			if dock:
				dock.toggle_show_selection_size()
		"quick_save_prefab":
			plugin._quick_save_prefab(root, false)
		"quick_save_linked_prefab":
			plugin._quick_save_prefab(root, true)
		"cycle_variant":
			plugin._cycle_prefab_variant(root)
		"push_to_source":
			plugin._push_prefab_to_source(root)
		"propagate_prefab":
			plugin._propagate_prefab(root)
		"place_prefab":
			HFPluginDropHandler.place_selected_prefab(plugin, root)
		"texture_picker":
			plugin._texture_picker_active = true
			if dock:
				dock.show_toast("Texture Picker: click a face to sample its material", 0)
		"surface_paint":
			if dock and dock.paint_mode:
				dock.paint_mode.button_pressed = true
		"paint_bucket":
			if dock:
				dock.set_paint_tool(0)
		"paint_erase":
			if dock:
				dock.set_paint_tool(1)
		"paint_ramp":
			if dock:
				dock.set_paint_tool(2)
		"paint_line":
			if dock:
				dock.set_paint_tool(3)
		"paint_fill":
			if dock:
				dock.set_paint_tool(4)
		"paint_blend":
			if dock:
				dock.set_paint_tool(5)
		"paint_raise":
			plugin._begin_floor_paint_raise(root)
		"paint_mirror_x":
			if dock:
				dock.toggle_paint_mirror_x()
		"paint_mirror_z":
			if dock:
				dock.toggle_paint_mirror_z()
		"paint_room":
			plugin._stamp_floor_paint_room(root)
		"paint_confirm_connector":
			plugin._confirm_floor_paint_connector(root)
		"grid_decrease":
			plugin._adjust_grid_snap(root, 0.5)
		"grid_increase":
			plugin._adjust_grid_snap(root, 2.0)
		"grid_up", "grid_down", "grid_reset", "grid_align":
			if root and root.grid_system:
				root.grid_system.run_command(action, plugin.hf_selection)
		"toggle_grid":
			if dock and dock.show_grid:
				dock.show_grid.button_pressed = not dock.show_grid.button_pressed
		"quick_bake":
			if dock:
				dock._on_bake()
		# The editor's manager has no undo() a script can call, so these step the
		# level's scene history, as the dock's Undo and Redo buttons do.
		"undo":
			var history: UndoRedo = HFUndoNavType.get_scene_undo_redo(
				plugin.undo_redo_manager, root
			)
			if history:
				history.undo()
		"redo":
			var history: UndoRedo = HFUndoNavType.get_scene_undo_redo(
				plugin.undo_redo_manager, root
			)
			if history:
				history.redo()
		"set_grid_snap":
			if dock and not args.is_empty():
				dock._apply_grid_snap(float(args[0]))
		"measure":
			if plugin._tool_registry and plugin.active_root:
				plugin._activate_external_tool(100, plugin.active_root)
		"cancel_drag":
			if root:
				root.cancel_drag()
			plugin.numeric_buffer = ""
			plugin._update_hud_context()
		"apply_pending_cuts":
			if dock:
				dock._on_apply_cuts()
				plugin._update_hud_context()
		"commit_cuts":
			if dock:
				dock._on_commit_cuts()
				plugin._update_hud_context()
		"clear_pending_cuts":
			if dock:
				dock._on_clear_cuts()
				plugin._update_hud_context()
		"bake_preview_toggle":
			var bake_pressed: bool = args[0] if not args.is_empty() else false
			plugin._toggle_bake_preview(root, bake_pressed)
		"context_menu":
			var tool_id_now: int = dock.get_tool() if dock else 0
			plugin._show_viewport_context_menu(root, tool_id_now)
		"radial_menu":
			if plugin._radial_menu and is_instance_valid(plugin._radial_menu):
				if plugin._radial_menu.is_active():
					plugin._radial_menu.hide_menu()
				else:
					plugin._radial_menu.show_at(plugin._get_current_overlay_mouse_pos())
		_:
			# The table lists it, so a surface offers it, and nothing here runs it.
			# The palette sweep fails on this in every state it tries.
			push_error("HFPluginCommands: '%s' is in HFCommandRegistry but has no arm" % action)
			return
	plugin._show_coach_mark_for_action(action)
	plugin._update_hud_context()
