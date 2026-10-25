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
const FaceData = preload("face_data.gd")
const HFPluginUVWrap = preload("plugin_uv_wrap.gd")
const HFBrushConversion = preload("hf_brush_conversion.gd")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
const HFLog = preload("hf_log.gd")
const HFPluginDropHandler = preload("plugin_drop_handler.gd")
const HFPluginEditActions = preload("plugin_edit_actions.gd")
const HFPluginPointerTools = preload("plugin_pointer_tools.gd")
const HFPluginSelectionCommands = preload("plugin_selection_commands.gd")
const HFViewFiltersType = preload("hf_view_filters.gd")
const HFPluginPrefabCommands = preload("plugin_prefab_commands.gd")
const HFPluginViewCommands = preload("plugin_view_commands.gd")
const HFPluginSelectionState = preload("plugin_selection_state.gd")
const HFPluginTransformTools = preload("plugin_transform_tools.gd")
const HFPluginVertexOps = preload("plugin_vertex_ops.gd")
const HFPluginBrushStamp = preload("plugin_brush_stamp.gd")
const HFPluginSnapFeedbackType = preload("plugin_snap_feedback.gd")
const HFFgdReader = preload("hf_fgd_reader.gd")
const HFSettingsFile = preload("hf_settings_file.gd")
const HFPluginCompare = preload("plugin_compare.gd")
const HFPluginAdjustLast = preload("plugin_adjust_last.gd")
const HFPluginCommandLine = preload("plugin_command_line.gd")
const HFPluginFaceSweep = preload("plugin_face_sweep.gd")
const HFPluginRun = preload("plugin_run.gd")
@warning_ignore_restore("shadowed_global_identifier")


## Whether the palette must refuse `action` when there is no level. These act on
## LevelRoot-owned state or scene content and must not create a level as a side
## effect of using the command palette. Level creation is reserved for explicit
## setup actions and the first intentional Draw press in the viewport.
static func requires_existing_root(action: String) -> bool:
	return HFCommandRegistry.needs_level(action)


## How many commands run lately the palette lists at its top (#1694).
const RECENT_MAX := 8

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
	# Why a tool cannot start, for the palette to grey it out with the reason its
	# activation would give (#1868).
	state["tool_refusals"] = (
		registry.refusals(root) if registry and registry.has_method("refusals") else {}
	)
	# The toolbar's Repeat button: what it would place, and whether it is armed.
	var last_drawn: Dictionary = {}
	if root and root.get("drag_system"):
		last_drawn = root.drag_system.last_drawn
		state["repeat_label"] = HFPluginBrushStamp.label(last_drawn, float(root.grid_snap))
	state["repeat_shape"] = HFPluginBrushStamp.shape_key(last_drawn)
	var stamp = plugin.get("_brush_stamp")
	state["repeat_armed"] = stamp != null and stamp.armed
	# What Repeat Last Command would run, and the commands run lately (#1694).
	var last := last_command(plugin)
	state["repeat_command"] = last
	state["repeat_text"] = repeat_text(plugin, last) if last != "" else ""
	# What Repeat Run would play (#1735).
	state["run_text"] = HFPluginRun.run_text(plugin)
	state["run_steps"] = HFPluginRun.steps_of(plugin).size()
	var recent = plugin.get("recent_commands")
	state["recent_commands"] = (recent as Array).duplicate() if recent is Array else []

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

	# The picked faces that are still faces, counted as the dock counts them (#1685).
	var face_count := 0
	if root and root.has_method("picked_face_count"):
		face_count = root.picked_face_count()
	state["face_count"] = face_count
	# Whether the Space menu offers Re-pick: faces are picked, and a Trim Run's
	# piece is selected or was on the way into Face Select (#1414).
	state["repick_trim_run"] = false
	if face_count > 0 and root and root.has_method("generator_for_selection"):
		var target = root.generator_for_selection(
			HFPluginEditActions.clip_target_brush_ids(plugin, root)
		)
		state["repick_trim_run"] = target != null and HFGeneratorSystem.follows_run(target.type)
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
			state["prefab_copies"] = root.prefab_system.copies_like(pfb_rec.instance_id).size()
			# What a linked copy changed outside what it keeps (#1734).
			if pfb_rec.linked:
				state["prefab_changes"] = root.prefab_system.compute_instance_diff(
					pfb_rec.instance_id
				)

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


## Which way Extrude goes with `settings`: 1 up, -1 down (#1867).
static func extrude_way(settings: Dictionary) -> int:
	return -1 if int(settings.get("direction", 0)) == 1 else 1


## The settings `action` runs with from its key: those the command it stands for
## is given, under the keymap entry's `args`.
static func key_settings(action: String, keymap: Object) -> Dictionary:
	var settings := (HFCommandRegistry.runs(action).get("settings", {}) as Dictionary).duplicate()
	if keymap != null and keymap.has_method("args_for"):
		settings.merge(keymap.args_for(action), true)
	return settings


## Run `action` from any surface. `settings` are values for its `params`, as a
## keymap entry's `args` or Adjust Last give them; a setting left out is what the
## dock says, as before (#1867). An id kept for a keymap runs the command it
## stands for, with its own settings under those given.
static func execute(
	plugin: Object, action: String, args: Array = [], settings: Dictionary = {}
) -> void:
	if plugin == null or action.is_empty():
		return
	var stands_for := HFCommandRegistry.runs(action)
	if not stands_for.is_empty():
		var given := (stands_for.get("settings", {}) as Dictionary).duplicate()
		given.merge(settings, true)
		settings = given
		action = str(stands_for.get("id", action))
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
		"compare_level":
			if dock:
				dock.open_compare_dialog()
		"end_compare":
			HFPluginCompare.end(plugin)
		"tool_draw":
			plugin._deactivate_external_tool()
			if dock and dock.tool_draw:
				dock.tool_draw.button_pressed = true
		"tool_select":
			plugin._deactivate_external_tool()
			if dock and dock.tool_select:
				dock.tool_select.button_pressed = true
		"tool_extrude":
			plugin._deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(extrude_way(settings))
				plugin._update_hud_context()
		"adjust_last":
			HFPluginAdjustLast.show(plugin)
		"repeat_brush":
			plugin._ensure_brush_stamp().arm(plugin, root)
		"repeat_last_command":
			repeat_last(plugin, root)
		"repeat_run":
			HFPluginRun.play(plugin, root)
		"clear_run":
			HFPluginRun.clear(plugin)
			if dock:
				dock.show_toast("Run cleared: the next command starts a new one", 0)
		"command_line":
			HFPluginCommandLine.open(plugin)
		"run_command_script":
			HFPluginCommandLine.ask_for_script(plugin)
		"convert_entity_definitions":
			convert_entity_definitions(plugin, root)
		"hollow":
			plugin._hollow_selected(root)
		"clip":
			plugin._clip_selected(root)
		"clip_to_face":
			plugin._clip_to_face_plane_selected(root)
		"sweep_faces":
			HFPluginFaceSweep.open(plugin, root)
		"run_trim_along_faces":
			HFPluginEditActions.run_trim_along_faces(plugin, root)
		"repick_trim_run":
			HFPluginEditActions.repick_trim_run(plugin, root)
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
		"hull":
			HFPluginEditActions.hull_selected(plugin, root)
		"rotate_ccw":
			plugin._rotate_selected(root, 1)
		"rotate_cw":
			plugin._rotate_selected(root, -1)
		"flip_selection":
			plugin._flip_selected(root)
		"mirror_copy":
			HFPluginEditActions.mirror_copy_selected(plugin, root)
		"shear_selection":
			HFPluginEditActions.open_shear_dialog(plugin, root)
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
		"paste_at_cursor":
			HFPluginEditActions.paste_at_cursor(
				plugin, root, args[0] if not args.is_empty() else null
			)
		"delete":
			plugin._delete_selected(root)
		"place_entity_here":
			if args.size() >= 2:
				HFPluginEditActions.place_entity_here(plugin, root, str(args[0]), args[1])
		"make_brush_entity":
			if not args.is_empty():
				HFPluginEditActions.make_brush_entity(plugin, root, str(args[0]))
		"back_to_world":
			HFPluginEditActions.back_to_world(plugin, root)
		"add_to_visgroup":
			if not args.is_empty():
				HFPluginEditActions.add_to_visgroup(plugin, root, str(args[0]))
		"new_visgroup":
			HFPluginEditActions.new_visgroup(plugin, root)
		"show_material_in_browser":
			HFPluginEditActions.show_material_in_browser(plugin, root)
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
		"align_texture_to_edge":
			if dock:
				# From the face menu, the edge nearest where it was opened (#1727).
				var near: Variant = null
				if not args.is_empty() and str(args[0]) == "cursor" and root:
					near = root.pick_face(plugin.last_3d_camera, plugin.last_3d_mouse_pos).get(
						"position"
					)
				dock._on_align_to_edge(near)
		"fit_texture_repeats":
			if dock:
				dock._on_fit_repeats()
		"fit_texture_strip":
			if dock:
				dock._on_fit_strip()
		"uv_align_face":
			if dock:
				dock._on_uv_align(FaceData.UVProjection.FACE)
		"uv_align_world":
			if dock:
				dock._on_uv_align(FaceData.UVProjection.BOX_UV)
		"uv_wrap":
			HFPluginUVWrap.begin(plugin, root)
		"uv_link":
			if dock:
				dock._on_uv_link()
		"uv_unlink":
			if dock:
				dock._on_uv_unlink()
		"uv_select_group":
			if dock:
				dock._on_uv_select_group()
		"apply_to_brush":
			if dock:
				dock._apply_material_to_whole_brush()
		"apply_last_texture":
			plugin._apply_last_texture(root)
		"apply_picked_look":
			if dock:
				dock._on_apply_picked_look()
		"make_faces_hidden":
			if dock:
				dock.make_selected_faces_hidden(true)
		"make_faces_normal":
			if dock:
				dock.make_selected_faces_hidden(false)
		"hide_faces_against_solids":
			HFPluginEditActions.hide_faces_against_solids(plugin, root)
		"replace_material":
			if dock:
				dock.open_replace_material()
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
		"cycle_io_wires":
			if dock:
				dock.cycle_io_wires()
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
		"vertex_scale":
			if root:
				HFPluginVertexOps.open_scale_dialog(plugin, root)
		"vertex_exit":
			plugin._toggle_vertex_mode(root)
		"select_all":
			plugin._select_all_nodes(root)
		"deselect_all":
			plugin._deselect_all_nodes(root)
		"select_similar":
			plugin._select_similar(root)
		"invert_selection":
			HFPluginSelectionCommands.invert_selection(plugin, root)
		"select_inside", "select_partly_inside", "select_touching", "select_column":
			HFPluginSelectionCommands.select_with_brush(plugin, root, action)
		"hide_selection":
			HFPluginViewCommands.hide_selection(plugin, root)
		"show_hidden":
			HFPluginViewCommands.show_hidden(plugin, root)
		"isolate_selection":
			HFPluginViewCommands.isolate_selection(plugin, root)
		"isolate_visgroups":
			HFPluginViewCommands.isolate_visgroups(plugin, root)
		"end_isolate":
			HFPluginViewCommands.end_isolate(plugin, root)
		"previous_visibility":
			HFPluginViewCommands.previous_visibility(plugin, root)
		"selection_filter":
			plugin._show_selection_filter()
		"view_filter_world", "view_filter_cut", "view_filter_clip", "view_filter_trigger", "view_filter_brush_entity", "view_filter_entity", "view_filter_structure", "view_filter_prefab", "view_filter_decal", "view_filter_wires", "view_filter_cordons", "view_filter_hidden_faces":
			if root:
				var kind := action.trim_prefix("view_filter_")
				var hide: bool = not root.is_view_filtered(kind)
				root.set_view_filter(kind, hide)
				if dock:
					dock.show_toast(
						(
							"%s %s"
							% [HFViewFiltersType.label_for(kind), "hidden" if hide else "shown"]
						),
						0
					)
		"toggle_face_direction":
			if root:
				root.face_direction_view = not root.face_direction_view
				if dock:
					dock.show_toast(
						(
							"Face Direction on: a face seen from behind is drawn in the back colour"
							if root.face_direction_view
							else "Face Direction off"
						),
						0
					)
		"quick_select":
			HFPluginSelectionCommands.show_quick_select(plugin)
		"grow_selection":
			HFPluginSelectionCommands.grow_selection(plugin, root)
		"shrink_selection":
			HFPluginSelectionCommands.shrink_selection(plugin, root)
		"toggle_face_xray":
			HFPluginSelectionCommands.toggle_face_xray(plugin)
		"toggle_selection_size":
			if dock:
				dock.toggle_show_selection_size()
		"toggle_draw_on_face":
			if dock:
				dock.toggle_draw_on_face()
			# The preview under a still cursor changes with it.
			var hover_camera = plugin.get("last_3d_camera")
			if is_instance_valid(hover_camera):
				HFPluginPointerTools.follow_draw_hover(
					plugin, root, hover_camera, plugin.last_3d_mouse_pos
				)
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
		"unlink_prefab_copy":
			HFPluginPrefabCommands.unlink_copy(plugin, root)
		"select_linked_copies":
			HFPluginPrefabCommands.select_linked_copies(plugin, root)
		"discard_prefab_changes":
			HFPluginPrefabCommands.discard_changes(plugin, root)
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
		"measure", "tool_clip", "tool_polygon", "tool_path", "tool_decal", "tool_hull", "tool_shear":
			if plugin._tool_registry and plugin.active_root:
				var tool_id: int = plugin._tool_registry.tool_id_for_action(action)
				if tool_id >= 0:
					plugin._activate_external_tool(tool_id, plugin.active_root)
		"snap_next_vertex", "snap_next_midpoint", "snap_next_centre", "snap_next_perpendicular", "snap_next_grid":
			HFPluginSnapFeedbackType.limit(plugin, action)
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
		"toggle_operation_replay":
			if plugin._operation_replay and is_instance_valid(plugin._operation_replay):
				plugin._operation_replay.toggle_visible()
			else:
				plugin._toast_power_user_overlay_hint()
		_:
			# The table lists it, so a surface offers it, and nothing here runs it.
			# The palette sweep fails on this in every state it tries.
			push_error("HFPluginCommands: '%s' is in HFCommandRegistry but has no arm" % action)
			return
	note_command(plugin, action)
	plugin._show_coach_mark_for_action(action)
	plugin._update_hud_context()


## Note `action` as run, for Repeat Last Command and the palette's recent list
## (#1694). Repeat itself is never noted, so it never repeats itself.
static func note_command(plugin: Object, action: String) -> void:
	if action == "repeat_last_command" or not HFCommandRegistry.dispatches(action):
		return
	HFPluginRun.on_command(plugin, action)
	if not ("recent_commands" in plugin and "last_repeatable_command" in plugin):
		return
	var recent: Array = plugin.recent_commands
	recent.erase(action)
	recent.push_front(action)
	if recent.size() > RECENT_MAX:
		recent.resize(RECENT_MAX)
	if HFCommandRegistry.repeatable(action):
		plugin.last_repeatable_command = action


## Note the command a key ran. The key router runs most commands itself rather
## than through `execute()`, so it asks which command the key is, the mode's own
## keys first as the router asks them.
static func note_key_command(plugin: Object, event: InputEventKey, mode: String) -> void:
	var keymap = plugin.get("_keymap")
	if keymap == null:
		return
	var found := ""
	for action in keymap.get_actions():
		if not HFCommandRegistry.dispatches(action) or not keymap.matches(action, event):
			continue
		var its: String = keymap.action_mode(action)
		if its == mode:
			found = action
			break
		if its == "general" and found == "":
			found = action
	if found != "":
		note_command(plugin, found)


## The command Repeat Last Command would run, or "".
static func last_command(plugin: Object) -> String:
	var last = plugin.get("last_repeatable_command") if plugin else null
	return str(last) if last is String else ""


## What Repeat says it runs: the command's name, and the setting it runs with
## where it has one, as "Hollow (0.25 m)".
static func repeat_text(plugin: Object, action: String) -> String:
	var text := HFCommandRegistry.label(action)
	var dock = plugin.get("dock")
	if action == "hollow" and dock and dock.has_method("get_hollow_thickness"):
		text += " (%s m)" % String.num(float(dock.get_hollow_thickness()), 3)
	return text


## Convert Entity Definitions to JSON (#1721): the classes the level reads from an
## FGD, written as an `entities.json` beside the first FGD it names, for a team
## that wants to go on in that form. One way: the FGD is left as it is, and the
## level reads the new file once its definitions path names it. Returns the file
## written, or "".
static func convert_entity_definitions(plugin: Object, root: Node) -> String:
	var dock = plugin.get("dock")
	var path := str(root.get("entity_definitions_path"))
	var fgd := ""
	for part in path.split(HFEntityDef.PATH_SEPARATOR, false):
		if part.strip_edges().get_extension().to_lower() == "fgd":
			fgd = part.strip_edges()
			break
	if fgd == "":
		if dock:
			dock.show_toast("The level's entity definitions name no FGD to convert", 1)
		return ""
	var read := HFEntityDef._read_entries(path)
	if str(read["failure"]) != "" or (read["entries"] as Array).is_empty():
		if dock:
			dock.show_toast("%s has no entity classes to convert" % fgd.get_file(), 1)
		return ""
	var out := fgd.get_basename() + ".json"
	var err := HFSettingsFile.write_text(out, HFFgdReader.to_json_text(read["entries"]))
	if err != OK:
		if dock:
			dock.show_toast("Could not write %s: %s" % [out, error_string(err)], 2)
		return ""
	(
		root
		. emit_signal(
			"user_message",
			(
				"Wrote %d entity classes to %s. Point the level's entity definitions at it to edit them as JSON"
				% [(read["entries"] as Array).size(), out]
			),
			0
		)
	)
	return out


## Run the last command that changed the level or the selection again, on the
## selection there is now (#1694). The command's own selection guard is asked
## first, so a refusal reads as that command's. The command makes its own undo
## step, named after it.
static func repeat_last(plugin: Object, root: Node) -> void:
	var dock = plugin.get("dock")
	var last := last_command(plugin)
	if last == "":
		if dock:
			dock.show_toast("Nothing to repeat yet", 0)
		return
	if root and not plugin._managed_action_surface_allowed(root, last):
		return
	if dock:
		dock.show_toast("Repeat: %s" % repeat_text(plugin, last), 0)
	execute(plugin, last)
