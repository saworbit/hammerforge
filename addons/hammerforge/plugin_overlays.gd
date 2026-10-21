@tool
class_name HFPluginOverlays
extends RefCounted
## Overlay lifecycle, viewport drawing, quick-property, and coach-mark behavior.

const HFQuickProperty = preload("ui/hf_quick_property.gd")
const HFCoachMarks = preload("ui/hf_coach_marks.gd")
const HFOperationReplay = preload("ui/hf_operation_replay.gd")
const HFRadialMenu = preload("ui/hf_radial_menu.gd")
const HFViewportDropTarget = preload("ui/hf_viewport_drop_target.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFPluginCommands = preload("plugin_commands.gd")
const HFPluginTransformTools = preload("plugin_transform_tools.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFOverlayColors = preload("hf_overlay_colors.gd")

## The overlays that belong over the 3D viewport rather than in the toolbar row.
## Named by property so host adoption can re-home whichever of them exist.
const VIEWPORT_OVERLAY_PROPERTIES := [
	"_context_toolbar",
	"_hotkey_palette",
	"_quick_property",
	"_coach_marks",
	"_operation_replay",
	"_radial_menu",
]

## Where each overlay sits once it is over the viewport. Anchors rather than
## positions: the host is the viewport's own rect, so these follow it as the
## window is resized or the docks are dragged. Two are deliberately absent —
## the quick property puts itself at the cursor and the radial menu draws itself
## around one, and now that neither is inside a layout container the geometry
## they set for themselves is no longer overwritten on the next re-sort.
const VIEWPORT_OVERLAY_ANCHORS := {
	"_context_toolbar": ["top_center", 8.0],
	"_hotkey_palette": ["center", 0.0],
	"_coach_marks": ["bottom_center", 12.0],
	"_operation_replay": ["bottom_left", 12.0],
}


## Park a viewport overlay on the Control the 3D viewport draws through.
##
## CONTAINER_SPATIAL_EDITOR_MENU is a layout container: it reserves every child's
## full minimum size in the toolbar row, and the 3D viewport gets whatever height
## is left under that row. A 320x380 command palette parked there takes the row
## to 380px tall and squeezes the viewport it is supposed to float over; the
## contextual toolbar and the cursor popup do the same to its width. None of them
## are toolbar items — only the shortcut HUD and the status strip are.
##
## The viewport's draw-over Control is a plain Control, so it positions nothing
## and reserves nothing, and it is the space `event.position` from
## _forward_3d_gui_input is measured in — so the positions these overlays already
## set for themselves finally land where they say. The toolbar stays the fallback
## for the frames before the 3D editor has drawn once and handed us that Control.
static func attach_viewport_overlay(plugin: Object, control: Control) -> void:
	if plugin == null or control == null:
		return
	var host = plugin._viewport_overlay_host
	if host != null and is_instance_valid(host):
		host.add_child(control)
		place_viewport_overlay(plugin, control)
		return
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, control)


## Take the overlay off whichever of the two parents it landed on.
static func detach_viewport_overlay(plugin: Object, control: Control) -> void:
	if plugin == null or control == null or not is_instance_valid(control):
		return
	var host = plugin._viewport_overlay_host
	if host != null and is_instance_valid(host) and control.get_parent() == host:
		host.remove_child(control)
		return
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, control)


## Godot hands the draw-over Control to every viewport of a split layout on every
## draw. Keep the first live one: adopting each call in turn would drag the
## overlays between viewports every frame.
static func adopt_viewport_overlay_host(plugin: Object, host: Control) -> void:
	if plugin == null or host == null or not is_instance_valid(host):
		return
	var current = plugin._viewport_overlay_host
	if current != null and is_instance_valid(current) and current.is_inside_tree():
		return
	plugin._viewport_overlay_host = host
	for property in VIEWPORT_OVERLAY_PROPERTIES:
		var control = plugin.get(property)
		if control is Control and is_instance_valid(control):
			_rehome_viewport_overlay(control, host)
			place_viewport_overlay(plugin, control)


## Keep the plugin's drop target on the viewport host, behind every overlay, so a
## drag over the viewport reaches `_can_drop_data()` and `_drop_data()` (#1417).
## It is not one of the overlays above: it covers the whole host and has nothing
## to show, and adoption would put it on top of them. The toolbar row is no place
## for it either, so it waits for a host.
static func ensure_viewport_drop_target(plugin: Object) -> void:
	var host = plugin._viewport_overlay_host
	if host == null or not is_instance_valid(host):
		return
	var target = plugin._viewport_drop_target
	if target == null or not is_instance_valid(target):
		target = HFViewportDropTarget.new()
		target.can_drop = Callable(plugin, "_can_drop_data")
		target.drop = Callable(plugin, "_drop_data")
		plugin._viewport_drop_target = target
	if target.get_parent() == host:
		return
	_rehome_viewport_overlay(target, host)
	host.move_child(target, 0)


static func free_viewport_drop_target(plugin: Object) -> void:
	var target = plugin._viewport_drop_target
	plugin._viewport_drop_target = null
	if target == null or not is_instance_valid(target):
		return
	if target.get_parent():
		target.get_parent().remove_child(target)
	target.free()


static func _rehome_viewport_overlay(control: Control, host: Control) -> void:
	var parent := control.get_parent()
	if parent == host:
		return
	if parent != null:
		parent.remove_child(control)
	host.add_child(control)


## The minimum size an overlay was last anchored against, so a change in it can
## be noticed without polling every anchor every frame.
const OVERLAY_PLACED_SIZE_META := &"hf_overlay_placed_size"


## Anchor an overlay inside the viewport. Anything not named in the table places
## itself, so leave it alone: overwriting a cursor-anchored popup with a corner
## preset is how it ends up in the wrong half of the screen.
static func place_viewport_overlay(plugin: Object, control: Control) -> void:
	if plugin == null or control == null or not is_instance_valid(control):
		return
	var property := _overlay_property_for(plugin, control)
	if not VIEWPORT_OVERLAY_ANCHORS.has(property):
		return
	_anchor_overlay(control, VIEWPORT_OVERLAY_ANCHORS[property])


## Re-anchor any overlay whose minimum size has moved under it.
##
## `set_anchors_and_offsets_preset` bakes its offsets from the minimum size it
## can see at the time, and neither anchored overlay is its final size when it is
## first placed: the contextual toolbar grows and shrinks with what is selected,
## and the palette finishes measuring its own rows after it is parented. Left
## alone, the toolbar keeps the left edge it was centred on while empty and a
## real selection grows it off the right side of the viewport.
##
## Anchors are fractions, so the host resizing is already handled; only a change
## of minimum size needs re-baking, and comparing two Vector2s is cheap enough to
## do on the draw hook.
static func refresh_viewport_overlay_placement(plugin: Object) -> void:
	if plugin == null:
		return
	var host = plugin._viewport_overlay_host
	if host == null or not is_instance_valid(host):
		return
	for property in VIEWPORT_OVERLAY_ANCHORS:
		var control = plugin.get(property)
		if not (control is Control) or not is_instance_valid(control):
			continue
		if control.get_parent() != host:
			continue
		var minimum: Vector2 = control.get_combined_minimum_size()
		if control.has_meta(OVERLAY_PLACED_SIZE_META):
			if control.get_meta(OVERLAY_PLACED_SIZE_META) == minimum:
				continue
		_anchor_overlay(control, VIEWPORT_OVERLAY_ANCHORS[property])


## Godot's own PRESET_CENTER_TOP puts the control's top-left corner on the
## centre-top point rather than centring the control there — it leaves both
## horizontal offsets at zero — so a 940px toolbar anchored that way starts at
## the middle of the viewport and runs off the right of it. The anchors and
## offsets are set out longhand instead, against the width the overlay needs now.
##
## Only the width is baked in. The height is left to the overlay's own minimum,
## which Godot never lays a control out under, and `grow_vertical` says which way
## it grows from the edge it hangs off. A wrapping section reports the height of
## its last layout as its minimum, made at whatever width the panel had before:
## the brush tools laid out at the Draw tool's width are seven rows deep, and
## baking that in held the panel at 188px with one row of buttons at the top of
## it until the next draw-over (#1327). Left to the minimum, the panel follows
## its rows as soon as they are laid out at the new width.
static func _anchor_overlay(control: Control, placement: Array) -> void:
	var margin := float(placement[1])
	var width := _overlay_width(control, margin)
	var half := width * 0.5
	match str(placement[0]):
		"top_center":
			control.grow_vertical = Control.GROW_DIRECTION_END
			_set_anchors(control, 0.5, 0.0, 0.5, 0.0)
			_set_offsets(control, -half, margin, half, margin)
		"center":
			control.grow_vertical = Control.GROW_DIRECTION_BOTH
			_set_anchors(control, 0.5, 0.5, 0.5, 0.5)
			_set_offsets(control, -half, 0.0, half, 0.0)
		"bottom_center":
			control.grow_vertical = Control.GROW_DIRECTION_BEGIN
			_set_anchors(control, 0.5, 1.0, 0.5, 1.0)
			_set_offsets(control, -half, -margin, half, -margin)
		"bottom_left":
			control.grow_vertical = Control.GROW_DIRECTION_BEGIN
			_set_anchors(control, 0.0, 1.0, 0.0, 1.0)
			_set_offsets(control, margin, -margin, margin + width, -margin)
	control.set_meta(OVERLAY_PLACED_SIZE_META, control.get_combined_minimum_size())


## The width the overlay should be laid out at, never wider than the viewport it
## floats over. An overlay wider than the viewport cannot be centred into it:
## centring just hangs it off both sides, with the buttons at each end
## unreachable. The contextual toolbar measures 940px with a brush selected and
## the viewport is narrower than that with a dock open, so it is capped here and
## wraps to a second row inside the cap.
##
## `natural_row_width()` is asked for rather than the combined minimum, because a
## wrapping container reports only its widest child and would otherwise cap
## itself to a single button.
static func _overlay_width(control: Control, margin: float) -> float:
	var width := control.get_combined_minimum_size().x
	if control.has_method("natural_row_width"):
		width = maxf(width, float(control.call("natural_row_width")))
	var area := control.get_parent_area_size()
	if area.x > 0.0:
		width = minf(width, maxf(0.0, area.x - margin * 2.0))
	return width


static func _set_anchors(
	control: Control, left: float, top: float, right: float, bottom: float
) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom


static func _set_offsets(
	control: Control, left: float, top: float, right: float, bottom: float
) -> void:
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


static func _overlay_property_for(plugin: Object, control: Control) -> String:
	for property in VIEWPORT_OVERLAY_PROPERTIES:
		if plugin.get(property) == control:
			return property
	return ""


static func install_power_user_overlays(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._coach_marks == null:
		plugin._coach_marks = HFCoachMarks.new()
		if plugin.base_control:
			plugin._coach_marks.theme = plugin.base_control.theme
		plugin._coach_marks.set_user_prefs(plugin._user_prefs)
		plugin._coach_marks.set_keymap(plugin.get("_keymap"))
		plugin._coach_marks.guide_dismissed.connect(plugin._on_coach_mark_dismissed)
		attach_viewport_overlay(plugin, plugin._coach_marks)
	if plugin._operation_replay == null:
		plugin._operation_replay = HFOperationReplay.new()
		if plugin.base_control:
			plugin._operation_replay.theme = plugin.base_control.theme
		plugin._operation_replay.replay_requested.connect(plugin._on_replay_requested)
		attach_viewport_overlay(plugin, plugin._operation_replay)
		if plugin.dock:
			plugin.dock.set_operation_replay(plugin._operation_replay)
	if plugin._radial_menu == null:
		plugin._radial_menu = HFRadialMenu.new()
		if plugin.base_control:
			plugin._radial_menu.theme = plugin.base_control.theme
		plugin._radial_menu.action_selected.connect(plugin._on_radial_action)
		attach_viewport_overlay(plugin, plugin._radial_menu)


static func teardown_power_user_overlays(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._coach_marks:
		if is_instance_valid(plugin._coach_marks):
			plugin._coach_marks.guide_dismissed.disconnect(plugin._on_coach_mark_dismissed)
		detach_viewport_overlay(plugin, plugin._coach_marks)
		if is_instance_valid(plugin._coach_marks):
			plugin._coach_marks.queue_free()
		plugin._coach_marks = null
	if plugin._operation_replay:
		if is_instance_valid(plugin._operation_replay):
			plugin._operation_replay.replay_requested.disconnect(plugin._on_replay_requested)
		detach_viewport_overlay(plugin, plugin._operation_replay)
		if is_instance_valid(plugin._operation_replay):
			plugin._operation_replay.queue_free()
		plugin._operation_replay = null
		if plugin.dock:
			plugin.dock.set_operation_replay(null)
	if plugin._radial_menu:
		if is_instance_valid(plugin._radial_menu):
			plugin._radial_menu.action_selected.disconnect(plugin._on_radial_action)
		detach_viewport_overlay(plugin, plugin._radial_menu)
		if is_instance_valid(plugin._radial_menu):
			plugin._radial_menu.queue_free()
		plugin._radial_menu = null


static func update_vertex_overlay(plugin: Object, root: Node) -> void:
	if plugin == null:
		return
	if not plugin._vertex_mode or not root or not root.vertex_system:
		clear_vertex_overlay(plugin)
		return
	var vertex_system = root.vertex_system
	var vertex_data = vertex_system.get_all_vertex_world_positions()
	if vertex_data.is_empty():
		clear_vertex_overlay(plugin)
		return
	ensure_vertex_overlay(plugin, root)
	# The handles and edges are world positions, and this hangs off the LevelRoot,
	# so it has to be pinned to world space. These are what a vertex drag is aimed
	# at; drawing them a root transform away makes the tool unusable off the origin.
	plugin._vertex_overlay_mesh.global_transform = Transform3D.IDENTITY
	plugin._vertex_overlay_imesh.clear_surfaces()
	var handle_color := HFOverlayColors.get_color(HFOverlayColors.VERTEX_HANDLE)
	var selected_color := HFOverlayColors.get_color(HFOverlayColors.SELECTED_VERTEX)
	# Full strength, unlike the hover outline round a brush: a handle is a thin
	# cross that has to read against the brush it sits on.
	var hover_color := HFOverlayColors.with_alpha(
		HFOverlayColors.get_color(HFOverlayColors.HOVER), 1.0
	)
	var edge_data = vertex_system.get_all_edge_world_positions()
	if not edge_data.is_empty():
		plugin._vertex_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for edge in edge_data:
			# An edge is the handle colour at half brightness and half strength.
			var edge_color := Color(
				handle_color.r * 0.5,
				handle_color.g * 0.5,
				handle_color.b * 0.5,
				handle_color.a * 0.5
			)
			if edge.selected:
				edge_color = selected_color
			elif edge.hovered:
				edge_color = hover_color
			plugin._vertex_overlay_imesh.surface_set_color(edge_color)
			plugin._vertex_overlay_imesh.surface_add_vertex(edge.a)
			plugin._vertex_overlay_imesh.surface_set_color(edge_color)
			plugin._vertex_overlay_imesh.surface_add_vertex(edge.b)
		plugin._vertex_overlay_imesh.surface_end()
	plugin._vertex_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for entry in vertex_data:
		var position: Vector3 = entry.pos
		var color := handle_color
		if entry.selected:
			color = selected_color
		elif entry.hovered:
			color = hover_color
		var size := 0.4
		for offset in [
			Vector3(-size, 0, 0),
			Vector3(size, 0, 0),
			Vector3(0, -size, 0),
			Vector3(0, size, 0),
			Vector3(0, 0, -size),
			Vector3(0, 0, size),
		]:
			plugin._vertex_overlay_imesh.surface_set_color(color)
			plugin._vertex_overlay_imesh.surface_add_vertex(position + offset)
	plugin._vertex_overlay_imesh.surface_end()


## Take the overlay colours from the preferences and redraw what is up in the old
## ones (#1446): the gizmo outlines, the level's hover outline, cordon and brush
## looks, the Face Select mark and the vertex handles. What draws later reads
## the new colours as it draws. Nothing is redrawn when no colour changed.
static func apply_overlay_colors(plugin: Object) -> void:
	if plugin == null:
		return
	if HFOverlayColors.apply_prefs(plugin.get("_user_prefs")):
		var gizmo_plugin = plugin.get("brush_gizmo_plugin")
		if gizmo_plugin and gizmo_plugin.has_method("apply_overlay_colors"):
			gizmo_plugin.apply_overlay_colors()
	var root = plugin.get("active_root")
	if root == null or not is_instance_valid(root):
		root = plugin.call("_get_level_root")
	refresh_overlay_colors(plugin, root)


## Redraw `root`'s overlays when they were drawn under an older palette, and mark
## it drawn under this one. A level in another scene tab misses a change made
## while it is out of sight, so the plugin asks again when it comes back.
static func refresh_overlay_colors(plugin: Object, root: Node) -> void:
	# Out of the tree a brush cannot draw, so a level there is left marked stale.
	if plugin == null or root == null or not is_instance_valid(root) or not root.is_inside_tree():
		return
	var drawn: Dictionary = plugin.get("_overlay_colors_drawn")
	var id := root.get_instance_id()
	var now := Vector2i(HFOverlayColors.revision(), HFOverlayColors.brush_revision())
	var was: Vector2i = drawn.get(id, Vector2i.ZERO)
	if was == now:
		return
	drawn[id] = now
	if root.has_method("refresh_overlay_colors"):
		root.refresh_overlay_colors(was.y != now.y)
	var face_mark = plugin.get("_face_selection_overlay")
	if face_mark:
		face_mark.refresh()
	if plugin.get("_vertex_mode"):
		update_vertex_overlay(plugin, root)


static func ensure_vertex_overlay(plugin: Object, root: Node) -> void:
	if plugin == null or root == null:
		return
	if plugin._vertex_overlay_mesh and is_instance_valid(plugin._vertex_overlay_mesh):
		return
	plugin._vertex_overlay_mesh = MeshInstance3D.new()
	plugin._vertex_overlay_mesh.name = "_VertexEditOverlay"
	plugin._vertex_overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plugin._vertex_overlay_mesh.material_override = material
	plugin._vertex_overlay_imesh = ImmediateMesh.new()
	plugin._vertex_overlay_mesh.mesh = plugin._vertex_overlay_imesh
	root.add_child(plugin._vertex_overlay_mesh)


static func clear_vertex_overlay(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._vertex_overlay_mesh and is_instance_valid(plugin._vertex_overlay_mesh):
		if plugin._vertex_overlay_mesh.get_parent():
			plugin._vertex_overlay_mesh.get_parent().remove_child(plugin._vertex_overlay_mesh)
		plugin._vertex_overlay_mesh.queue_free()
		plugin._vertex_overlay_mesh = null
	plugin._vertex_overlay_imesh = null


## Draw only the active Floor Paint footprint, height cage, and connector
## candidates. The source lists are stroke-local, so mouse motion never scans or
## rebuilds a complete paint layer.
static func update_paint_overlay(plugin: Object, root: Node) -> void:
	if plugin == null or root == null or not plugin.dock or not plugin.dock.is_paint_mode_enabled():
		clear_paint_overlay(plugin)
		return
	var paint_tool = root.get("paint_tool")
	var layers = root.get("paint_layers")
	if paint_tool == null or layers == null:
		clear_paint_overlay(plugin)
		return
	var layer = layers.get_active_layer()
	if layer == null or layer.grid == null:
		clear_paint_overlay(plugin)
		return
	var cells: Array[Vector2i] = paint_tool.get_preview_cells()
	var connector_meshes: Array = paint_tool.get_pending_connector_meshes()
	if cells.is_empty():
		_clear_paint_footprint_overlay(plugin)
	else:
		_ensure_paint_overlay(plugin, root)
		plugin._paint_overlay_mesh.global_transform = Transform3D.IDENTITY
		plugin._paint_overlay_imesh.clear_surfaces()
		plugin._paint_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var raising: bool = paint_tool.is_height_gesture_active()
		var raise_height: float = paint_tool.get_raise_preview_height()
		for cell in cells:
			_draw_paint_cell(plugin._paint_overlay_imesh, layer, cell, raising, raise_height)
		plugin._paint_overlay_imesh.surface_end()
	_update_connector_overlays(plugin, root, connector_meshes)


static func _ensure_paint_overlay(plugin: Object, root: Node) -> void:
	if plugin._paint_overlay_mesh and is_instance_valid(plugin._paint_overlay_mesh):
		return
	plugin._paint_overlay_mesh = MeshInstance3D.new()
	plugin._paint_overlay_mesh.name = "_FloorPaintFootprintOverlay"
	plugin._paint_overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plugin._paint_overlay_mesh.material_override = material
	plugin._paint_overlay_imesh = ImmediateMesh.new()
	plugin._paint_overlay_mesh.mesh = plugin._paint_overlay_imesh
	root.add_child(plugin._paint_overlay_mesh)


static func _draw_paint_cell(
	mesh: ImmediateMesh, layer, cell: Vector2i, raising: bool, raise_height: float
) -> void:
	var grid = layer.grid
	var uv: Vector2 = grid.cell_to_uv(cell)
	var size: float = grid.cell_size
	var base_y: float = grid.layer_y + layer.get_height_at(cell) + 0.03
	var corners := [
		grid.uv_to_world(uv, base_y),
		grid.uv_to_world(uv + Vector2(size, 0.0), base_y),
		grid.uv_to_world(uv + Vector2(size, size), base_y),
		grid.uv_to_world(uv + Vector2(0.0, size), base_y),
	]
	var color := Color(0.2, 0.85, 1.0, 0.95)
	_draw_loop(mesh, corners, color)
	if not raising:
		return
	var top_y := base_y + raise_height
	var top := [
		grid.uv_to_world(uv, top_y),
		grid.uv_to_world(uv + Vector2(size, 0.0), top_y),
		grid.uv_to_world(uv + Vector2(size, size), top_y),
		grid.uv_to_world(uv + Vector2(0.0, size), top_y),
	]
	var raise_color := Color(1.0, 0.65, 0.15, 0.95)
	_draw_loop(mesh, top, raise_color)
	for index in range(4):
		_add_line(mesh, corners[index], top[index], raise_color)


static func _draw_loop(mesh: ImmediateMesh, points: Array, color: Color) -> void:
	for index in range(points.size()):
		_add_line(mesh, points[index], points[(index + 1) % points.size()], color)


static func _add_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)


static func _update_connector_overlays(plugin: Object, root: Node, entries: Array) -> void:
	_clear_connector_overlays(plugin)
	for entry in entries:
		if not entry is Dictionary:
			continue
		var mesh: ArrayMesh = entry.get("mesh")
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "_FloorPaintConnectorGhost"
		instance.mesh = mesh
		instance.transform = entry.get("transform", Transform3D.IDENTITY)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.35, 0.9, 0.45, 0.45)
		instance.material_override = material
		root.add_child(instance)
		plugin._paint_connector_overlay_meshes.append(instance)


static func _clear_paint_footprint_overlay(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._paint_overlay_mesh and is_instance_valid(plugin._paint_overlay_mesh):
		if plugin._paint_overlay_mesh.get_parent():
			plugin._paint_overlay_mesh.get_parent().remove_child(plugin._paint_overlay_mesh)
		plugin._paint_overlay_mesh.free()
	plugin._paint_overlay_mesh = null
	plugin._paint_overlay_imesh = null


static func _clear_connector_overlays(plugin: Object) -> void:
	if plugin == null:
		return
	for instance in plugin._paint_connector_overlay_meshes:
		if instance and is_instance_valid(instance):
			if instance.get_parent():
				instance.get_parent().remove_child(instance)
			instance.free()
	plugin._paint_connector_overlay_meshes.clear()


static func clear_paint_overlay(plugin: Object) -> void:
	_clear_paint_footprint_overlay(plugin)
	_clear_connector_overlays(plugin)


static func update_marquee_overlay(
	plugin: Object, from: Vector2, to: Vector2, active: bool
) -> void:
	if plugin == null:
		return
	plugin._marquee_overlay_origin = from
	plugin._marquee_overlay_current = to
	plugin._marquee_overlay_active = active
	if plugin.is_inside_tree():
		plugin.update_overlays()


static func draw_marquee_overlay(plugin: Object, viewport_control: Control) -> void:
	if plugin == null or not plugin._marquee_overlay_active or not viewport_control:
		return
	var local_mouse := viewport_control.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, viewport_control.size).has_point(local_mouse):
		return
	var rect := (
		Rect2(
			plugin._marquee_overlay_origin,
			plugin._marquee_overlay_current - plugin._marquee_overlay_origin
		)
		. abs()
	)
	var color := marquee_color(plugin)
	viewport_control.draw_rect(rect, Color(color, 0.12))
	viewport_control.draw_rect(rect, Color(color, 0.7), false, 1.5)


## The face marquee's colour: blue, or amber while X-ray has it take every face
## in the box, so a box that reaches through walls looks like one (#1432).
static func marquee_color(plugin: Object) -> Color:
	var dock = plugin.get("dock") if plugin != null else null
	var xray: bool = dock != null and dock.is_face_xray_enabled()
	return Color(1.0, 0.6, 0.2) if xray else Color(0.3, 0.6, 1.0)


static func handle_double_tap(plugin: Object, keycode: int, root: Node, paint_mode: bool) -> bool:
	match keycode:
		KEY_G:
			var snap_value: float = root.grid_snap if root else 16.0
			show_quick_property(
				plugin,
				HFQuickProperty.PropertyType.GRID_SNAP,
				[snap_value],
				_ranges_of(plugin, ["grid_snap"])
			)
			return true
		KEY_B:
			if paint_mode:
				return false
			var size: Vector3 = (
				root.input_state.drag_size_default
				if root and root.input_state
				else Vector3(4, 4, 4)
			)
			show_quick_property(
				plugin,
				HFQuickProperty.PropertyType.BRUSH_SIZE,
				[size.x, size.y, size.z],
				_ranges_of(plugin, ["size_x", "size_y", "size_z"])
			)
			return true
		KEY_R:
			if paint_mode:
				var radius: float = plugin.dock.get_surface_paint_radius() if plugin.dock else 0.25
				show_quick_property(
					plugin,
					HFQuickProperty.PropertyType.PAINT_RADIUS,
					[radius],
					_ranges_of(plugin, ["surface_paint_radius"])
				)
				return true
	return false


## The min/max/step of the named dock controls, for the popup that stands in
## for them. Empty when the dock is not there, which leaves the popup on its
## own defaults.
static func _ranges_of(plugin: Object, control_names: Array) -> Array:
	var out: Array = []
	if plugin == null or not plugin.dock:
		return out
	for control_name in control_names:
		var control = plugin.dock.get(control_name)
		if control is Range:
			(
				out
				. append(
					{
						"min": control.min_value,
						"max": control.max_value,
						"step": control.step,
					}
				)
			)
	return out


static func show_quick_property(
	plugin: Object, property_type: int, values: Array, ranges: Array = []
) -> void:
	if (
		plugin == null
		or not plugin._quick_property
		or not is_instance_valid(plugin._quick_property)
	):
		return
	plugin._quick_property.show_property(
		property_type, plugin._get_current_overlay_mouse_pos(), values, ranges
	)


static func on_quick_property_committed(plugin: Object, property_type: int, values: Array) -> void:
	if plugin == null:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	match property_type:
		HFQuickProperty.PropertyType.GRID_SNAP:
			if plugin.dock and not values.is_empty():
				plugin.dock._apply_grid_snap(float(values[0]))
		HFQuickProperty.PropertyType.BRUSH_SIZE:
			if root and root.input_state and values.size() >= 3:
				# The dock spins clamp and round; drag_size_default takes
				# whatever it is given. Write the controls first and read the
				# size back out of them, so the two ends cannot disagree about
				# how big the next brush is.
				var applied := Vector3(values[0], values[1], values[2])
				if plugin.dock and plugin.dock.size_x:
					plugin.dock.size_x.value = values[0]
					plugin.dock.size_y.value = values[1]
					plugin.dock.size_z.value = values[2]
					applied = Vector3(
						plugin.dock.size_x.value, plugin.dock.size_y.value, plugin.dock.size_z.value
					)
				root.input_state.drag_size_default = applied
		HFQuickProperty.PropertyType.PAINT_RADIUS:
			if plugin.dock and not values.is_empty() and plugin.dock.surface_paint_radius:
				plugin.dock.surface_paint_radius.value = float(values[0])
		HFQuickProperty.PropertyType.OFFSET:
			if values.size() >= 4:
				HFPluginTransformTools.apply_offset(
					plugin,
					root,
					Vector3(float(values[0]), float(values[1]), float(values[2])),
					bool(values[3])
				)


static func show_coach_mark_for_action(plugin: Object, action: String) -> void:
	if plugin == null or not plugin._coach_marks or not is_instance_valid(plugin._coach_marks):
		return
	var coach_key := ""
	match action:
		"vertex_edit":
			coach_key = "vertex_edit"
		"hollow":
			coach_key = "hollow"
		"clip":
			coach_key = "clip"
		"carve":
			coach_key = "carve"
		"tool_extrude_up", "tool_extrude_down", "tool_extrude", "tool_extrude_down_alt":
			coach_key = "extrude"
		"paint_bucket", "paint_erase", "paint_ramp", "paint_line", "paint_fill", "paint_blend":
			coach_key = "surface_paint"
	if not coach_key.is_empty():
		plugin._coach_marks.show_guide(coach_key)


static func show_coach_mark_for_tool_id(plugin: Object, tool_id: int) -> void:
	if (
		plugin == null
		or not plugin._coach_marks
		or not is_instance_valid(plugin._coach_marks)
		or not plugin._tool_registry
	):
		return
	var tool = plugin._tool_registry.get_tool_by_id(tool_id)
	if not tool:
		return
	var tool_name: String = tool.tool_name().to_lower()
	if "polygon" in tool_name:
		plugin._coach_marks.show_guide("polygon")
	elif "path" in tool_name:
		plugin._coach_marks.show_guide("path")
	elif "measure" in tool_name:
		plugin._coach_marks.show_guide("measure")
	elif "decal" in tool_name:
		plugin._coach_marks.show_guide("decal")


# ---------------------------------------------------------------------------
# Viewport context menu
# ---------------------------------------------------------------------------


## Show the viewport context menu at the current mouse position.
## Triggered by Space key (no modifiers). Converts screen coords to window-local
## for PopupMenu.popup() — the only reliable coordinate source since the 3D
## SubViewport's event.position space doesn't match window space.
static func show_viewport_context_menu(plugin: Object, root: Node, tool_id: int) -> void:
	var menu = plugin._viewport_context_menu
	if not menu or not is_instance_valid(menu):
		return
	var state := build_viewport_state(plugin, root, tool_id)
	var screen_pos := DisplayServer.mouse_get_position()
	var win: Window = plugin.get_window()
	var window_pos := Vector2(screen_pos)
	if win:
		window_pos = Vector2(screen_pos - win.position)
	menu.show_at(window_pos, state)


## Summarise what is selected and what mode the editor is in, so the menu can
## show only the entries that would actually do something. The state every
## command surface reads, plus the menu's own.
static func build_viewport_state(plugin: Object, root: Node, tool_id: int) -> Dictionary:
	var state := HFPluginCommands.build_command_state(plugin, root, tool_id)
	# The prefab selected in the library, for Place Selected Prefab. Only this menu
	# offers it, so it is read as the menu opens and not on every HUD update.
	var dock = plugin.get("dock")
	var library = dock.get("_prefab_library") if dock else null
	state["library_prefab"] = library.get_selected_path() if library else ""
	return state
