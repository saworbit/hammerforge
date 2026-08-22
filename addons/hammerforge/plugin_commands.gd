@tool
class_name HFPluginCommands
extends RefCounted
## Shared command dispatch for the context toolbar, hotkey palette, viewport
## context menu, and radial menu. Surfaces keep their own root/selection guards.

const LevelRootType = preload("level_root.gd")

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


static func execute(plugin: Object, action: String, args: Array = []) -> void:
	if plugin == null or action.is_empty():
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
		"hollow":
			plugin._hollow_selected(root)
		"clip":
			plugin._clip_selected(root)
		"carve":
			plugin._carve_selected(root)
		"merge":
			plugin._merge_selected(root)
		"duplicate":
			plugin._duplicate_selected(root)
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
		"apply_to_brush":
			if dock:
				dock._apply_material_to_whole_brush()
		"apply_last_texture":
			plugin._apply_last_texture(root)
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
		"grid_decrease":
			plugin._adjust_grid_snap(root, 0.5)
		"grid_increase":
			plugin._adjust_grid_snap(root, 2.0)
		"toggle_grid":
			if dock and dock.show_grid:
				dock.show_grid.button_pressed = not dock.show_grid.button_pressed
		"quick_bake":
			if dock:
				dock._on_bake()
		"undo":
			if plugin.undo_redo_manager:
				plugin.undo_redo_manager.undo()
		"redo":
			if plugin.undo_redo_manager:
				plugin.undo_redo_manager.redo()
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
	plugin._show_coach_mark_for_action(action)
	plugin._update_hud_context()
