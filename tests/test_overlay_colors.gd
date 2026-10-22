extends GutTest
## Each overlay draws in the colour picked for it under Test > Settings > Colours,
## a change shows at once on what is already drawn, and Reset brings back the
## look these replaced (#1446). Before, every one of them was a literal in the
## file that drew it.
##
## The colours are changed the way a mapper changes them, through the dock's
## Colours block, on a plugin whose preferences are never written to disk.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFOverlayColors = preload("res://addons/hammerforge/hf_overlay_colors.gd")
const HFFaceSelectionOverlay = preload("res://addons/hammerforge/hf_face_selection_overlay.gd")
const PointerTools = preload("res://addons/hammerforge/plugin_pointer_tools.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func after_each() -> void:
	if rig.plugin:
		_panel().apply_preset(HFOverlayColors.DEFAULTS)
	HFOverlayColors.reset()


func _panel():
	return rig.plugin.dock.overlay_colors_panel


## A colour picked on the button for `key`, as the picker reports it.
func _pick_color(key: String, color: Color) -> void:
	var picker: ColorPickerButton = _panel().get_picker(key)
	picker.color = color
	picker.color_changed.emit(color)


func _high_contrast() -> void:
	_panel().high_contrast_btn.pressed.emit()


## Within the eight bits a channel that a hex string and a vertex colour keep.
func _near(a: Color, b: Color) -> bool:
	var off := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
	return off <= 1.0 / 255.0 + 0.0001


func _look(brush: DraftBrush) -> StandardMaterial3D:
	return brush.mesh_instance.get_active_material(0) as StandardMaterial3D


func _cut_outline(brush: DraftBrush) -> Color:
	for child in brush.get_children(true):
		if child.name == DraftBrush.SUBTRACT_OVERLAY_NAME:
			return ((child as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	return Color.TRANSPARENT


func _cut(level: Node, id: String, center: Vector3) -> DraftBrush:
	return (
		level
		. create_brush_from_info(
			{
				"size": Vector3(2, 2, 2),
				"center": center,
				"brush_id": id,
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
			}
		)
	)


func _top_face(brush: DraftBrush) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


func _mark(level: Node) -> MeshInstance3D:
	for child in level.get_children(true):
		if child is MeshInstance3D and child.name == HFFaceSelectionOverlay.NODE_NAME:
			return child
	return null


func _colors_of(mesh: Mesh, surface: int) -> PackedColorArray:
	return mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]


## How many of `colors` are `expected`, within a vertex colour's eight bits.
func _count_near(colors: PackedColorArray, expected: Color) -> int:
	var count := 0
	for color in colors:
		if _near(color, expected):
			count += 1
	return count


## The hover outline is made only in the editor, so a headless level is given
## one the way `_setup_highlight()` makes it.
func _give_hover_outline(level: Node) -> StandardMaterial3D:
	var outline := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HFOverlayColors.get_color(HFOverlayColors.HOVER)
	outline.material_override = mat
	level.add_child(outline, false, Node.INTERNAL_MODE_BACK)
	level.hover_highlight = outline
	return mat


## The face Extrude would act on under the middle of the box, hovered with tool
## `tool_id` (2 out, 3 in), and the colour the hover was drawn in.
func _extrude_hover(level: Node, tool_id: int) -> Color:
	var on_top := rig.camera.unproject_position(Vector3(0, 2, 0))
	PointerTools.handle_motion(
		rig.plugin, PluginRig.motion(on_top), level, rig.camera, on_top, tool_id
	)
	var drawn: Color = (
		level._face_hover_material.albedo_color if level._face_hover_material else Color.TRANSPARENT
	)
	level.clear_face_hover_highlight()
	return drawn


## The ghost an extrusion of the top face shows, and its colour.
func _extrude_ghost(level: Node, brush: DraftBrush, direction: int) -> Color:
	var tool = level.extrude_tool
	tool.begin_on_face(brush, _top_face(brush), direction)
	tool.set_height(2.0)
	var ghost: DraftBrush = tool._preview_brush
	var drawn := Color.TRANSPARENT
	if ghost:
		assert_true(DraftBrush.is_editor_look(ghost.material_override), "the ghost is a look")
		drawn = (ghost.material_override as StandardMaterial3D).albedo_color
	tool.cancel_extrude()
	return drawn


# -- Tests ----------------------------------------------------------------------


func test_each_overlay_draws_in_its_colour_and_the_defaults_are_the_old_look() -> void:
	var level = await rig.make_level()
	var solid: DraftBrush = rig.box(level, "solid", Vector3.ZERO)
	var cut := _cut(level, "cut", Vector3(10, 0, 0))
	assert_eq(_look(solid).albedo_color, Color(0.2, 0.8, 0.2, 0.35), "a solid is green")
	assert_eq(_look(cut).albedo_color, Color(1.0, 0.2, 0.2, 0.35), "a cut is red")
	assert_eq(_cut_outline(cut), Color(1.0, 0.2, 0.2, 0.7), "and outlined in red")
	assert_eq(_extrude_hover(level, 2), Color(0.2, 0.8, 0.3, 0.35), "extruding out is green")
	assert_eq(_extrude_hover(level, 3), Color(0.8, 0.2, 0.2, 0.35), "and in, red")
	level.set_cordon_from_selection([solid])
	var wire: PackedColorArray = _colors_of(level.cordon_wireframe.mesh, 0)
	assert_eq(_count_near(wire, Color(1.0, 0.8, 0.0, 0.6)), wire.size(), "the cordon is amber")
	await rig.leave_level(level)


func test_high_contrast_reaches_every_overlay_drawn_after_it() -> void:
	_high_contrast()
	var hc: Dictionary = HFOverlayColors.HIGH_CONTRAST
	for key in hc:
		assert_true(
			_near(HFOverlayColors.get_color(key), hc[key]), "the plugin drew %s from it" % key
		)
	var level = await rig.make_level()
	var solid: DraftBrush = rig.box(level, "solid", Vector3.ZERO)
	var cut := _cut(level, "cut", Vector3(10, 0, 0))
	var additive := HFOverlayColors.get_color(HFOverlayColors.ADDITIVE_BRUSH)
	var subtractive := HFOverlayColors.get_color(HFOverlayColors.SUBTRACTIVE_BRUSH)
	assert_eq(_look(solid).albedo_color, additive, "a solid wears the additive colour")
	assert_eq(_look(solid).emission, HFOverlayColors.with_alpha(additive, 1.0), "and glows in it")
	assert_eq(_look(cut).albedo_color, subtractive, "a cut the subtractive one")
	assert_eq(
		_cut_outline(cut),
		HFOverlayColors.with_alpha(subtractive, HFOverlayColors.SUBTRACT_OUTLINE_ALPHA),
		"and is outlined in it"
	)
	assert_eq(
		_extrude_hover(level, 2),
		HFOverlayColors.get_color(HFOverlayColors.EXTRUDE_UP),
		"a face hovered to extrude out"
	)
	assert_eq(
		_extrude_hover(level, 3),
		HFOverlayColors.get_color(HFOverlayColors.EXTRUDE_DOWN),
		"and to extrude in"
	)
	assert_eq(
		_extrude_ghost(level, solid, 1),
		HFOverlayColors.get_color(HFOverlayColors.EXTRUDE_UP),
		"the ghost of an extrusion out"
	)
	assert_eq(
		_extrude_ghost(level, solid, -1),
		HFOverlayColors.get_color(HFOverlayColors.EXTRUDE_DOWN),
		"and in"
	)

	level.toggle_face_selection(solid, _top_face(solid), true, false)
	await rig.frame()
	var mark := _mark(level)
	assert_not_null(mark, "a picked face is marked")
	if mark:
		var face := HFOverlayColors.get_color(HFOverlayColors.SELECTED_FACE)
		var fill := _colors_of(mark.mesh, 0)
		assert_eq(_count_near(fill, face), fill.size(), "in the selected face tint")
		var edge := _colors_of(mark.mesh, 1)
		assert_eq(
			_count_near(edge, HFOverlayColors.with_alpha(face, 1.0)),
			edge.size(),
			"outlined in it at full strength"
		)

	level.set_cordon_from_selection([solid])
	var extra: Array[AABB] = [AABB(Vector3(50, 0, 0), Vector3(4, 4, 4))]
	level.cordon_extra_aabbs = extra
	level.set_cordon_active(1, false)
	level.update_cordon_visual()
	var wire: PackedColorArray = _colors_of(level.cordon_wireframe.mesh, 0)
	assert_eq(
		_count_near(wire, LevelRoot.cordon_color(true)), wire.size() / 2, "a cordon on is drawn"
	)
	assert_eq(
		_count_near(wire, LevelRoot.cordon_color(false)),
		wire.size() / 2,
		"one off at a quarter of its strength"
	)
	assert_true(
		_near(
			LevelRoot.cordon_color(true), HFOverlayColors.HIGH_CONTRAST[HFOverlayColors.WIREFRAME]
		),
		"in the wireframe colour"
	)
	await rig.leave_level(level)


func test_a_change_redraws_what_is_already_up_without_a_reload() -> void:
	var level = await rig.make_level()
	var solid: DraftBrush = rig.box(level, "solid", Vector3.ZERO)
	var cut := _cut(level, "cut", Vector3(10, 0, 0))
	var hover := _give_hover_outline(level)
	level.toggle_face_selection(solid, _top_face(solid), true, false)
	level.set_cordon_from_selection([solid])
	await rig.frame()
	var mark_before := _mark(level)
	assert_not_null(mark_before, "fixture: a face is marked")

	_high_contrast()

	assert_eq(
		_look(solid).albedo_color,
		HFOverlayColors.get_color(HFOverlayColors.ADDITIVE_BRUSH),
		"the solid already drawn is redrawn"
	)
	assert_eq(
		_look(cut).albedo_color,
		HFOverlayColors.get_color(HFOverlayColors.SUBTRACTIVE_BRUSH),
		"and the cut"
	)
	assert_eq(
		_cut_outline(cut),
		HFOverlayColors.with_alpha(
			HFOverlayColors.get_color(HFOverlayColors.SUBTRACTIVE_BRUSH),
			HFOverlayColors.SUBTRACT_OUTLINE_ALPHA
		),
		"with its outline"
	)
	assert_eq(
		hover.albedo_color, HFOverlayColors.get_color(HFOverlayColors.HOVER), "the hover outline"
	)
	var wire: PackedColorArray = _colors_of(level.cordon_wireframe.mesh, 0)
	assert_eq(_count_near(wire, LevelRoot.cordon_color(true)), wire.size(), "the cordon")
	var mark := _mark(level)
	assert_not_null(mark, "and the face mark")
	if mark:
		var fill := _colors_of(mark.mesh, 0)
		assert_eq(
			_count_near(fill, HFOverlayColors.get_color(HFOverlayColors.SELECTED_FACE)),
			fill.size(),
			"in the new tint"
		)

	_panel().reset_btn.pressed.emit()
	assert_eq(_look(solid).albedo_color, Color(0.2, 0.8, 0.2, 0.35), "Reset puts green back")
	assert_eq(_look(cut).albedo_color, Color(1.0, 0.2, 0.2, 0.35), "and red")
	assert_eq(hover.albedo_color, Color(1.0, 1.0, 0.0, 0.5), "and the yellow hover")
	await rig.leave_level(level)


## The brush entity looks were literals, so High Contrast left a func_detail or a
## trigger blue under a sky blue selection (#1760).
func test_high_contrast_reaches_the_brush_entity_looks_already_drawn() -> void:
	var keys := {
		"func_detail": HFOverlayColors.FUNC_DETAIL,
		"trigger_once": HFOverlayColors.TRIGGER,
		"func_wall": HFOverlayColors.FUNC_WALL,
		"func_clip": HFOverlayColors.FUNC_CLIP,
		"func_door": HFOverlayColors.BRUSH_ENTITY,
	}
	var level = await rig.make_level()
	var brushes := {}
	var x := 0.0
	for entity_class in keys:
		var brush: DraftBrush = rig.box(level, entity_class, Vector3(x, 0, 0))
		brush.set_brush_entity_class(entity_class)
		brushes[entity_class] = brush
		x += 10.0
	for entity_class in keys:
		var look := _look(brushes[entity_class])
		var default: Color = HFOverlayColors.DEFAULTS[keys[entity_class]]
		assert_eq(look.albedo_color, default, "%s wears the look it had" % entity_class)
		assert_eq(look.emission, HFOverlayColors.with_alpha(default, 1.0), "and glows in it")

	_high_contrast()

	for entity_class in keys:
		var picked: Color = HFOverlayColors.HIGH_CONTRAST[keys[entity_class]]
		assert_true(
			_near(_look(brushes[entity_class]).albedo_color, picked),
			"%s is redrawn in High Contrast" % entity_class
		)
	_pick_color(HFOverlayColors.TRIGGER, Color(1.0, 0.0, 1.0, 0.4))
	assert_true(
		_near(_look(brushes["trigger_once"]).albedo_color, Color(1.0, 0.0, 1.0, 0.4)),
		"and a trigger in a colour picked for it"
	)
	await rig.leave_level(level)


func test_a_colour_the_brushes_do_not_wear_leaves_them_undrawn() -> void:
	var level = await rig.make_level()
	var solid: DraftBrush = rig.box(level, "solid", Vector3.ZERO)
	var look := _look(solid)
	_pick_color(HFOverlayColors.HOVER, Color(0.0, 0.0, 1.0, 0.5))
	assert_same(_look(solid), look, "a hover colour does not redraw every brush")
	_pick_color(HFOverlayColors.ADDITIVE_BRUSH, Color(0.0, 0.0, 1.0, 0.4))
	assert_true(_near(_look(solid).albedo_color, Color(0.0, 0.0, 1.0, 0.4)), "an additive one does")
	assert_eq(
		rig.plugin._user_prefs.get_pref(HFOverlayColors.ADDITIVE_BRUSH),
		"#0000ff66",
		"and the pick is kept as a preference"
	)
	await rig.leave_level(level)


func test_vertex_handles_draw_in_their_colours() -> void:
	var handle := Color(0.2, 0.4, 0.6, 1.0)
	var selected := Color(0.8, 0.0, 0.8, 1.0)
	_pick_color(HFOverlayColors.VERTEX_HANDLE, handle)
	_pick_color(HFOverlayColors.SELECTED_VERTEX, selected)
	var level = await rig.make_level()
	var box: DraftBrush = rig.box(level, "v", Vector3.ZERO)
	rig.select([box])
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	level.vertex_system.select_vertex("v", 0)
	rig.plugin._update_vertex_overlay(level, rig.camera)
	var mesh: ImmediateMesh = rig.plugin._vertex_overlay_imesh
	assert_not_null(mesh, "the handles are drawn")
	if mesh:
		assert_eq(mesh.get_surface_count(), 2, "edges, then vertices")
		var edges := _colors_of(mesh, 0)
		var half := Color(handle.r * 0.5, handle.g * 0.5, handle.b * 0.5, 0.5)
		assert_eq(_count_near(edges, half), edges.size(), "edges at half the handle colour")
		var crosses := _colors_of(mesh, 1)
		assert_eq(_count_near(crosses, selected), 6, "the selected vertex's cross")
		assert_eq(_count_near(crosses, handle), crosses.size() - 6, "and the rest in the handle's")
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	rig.select([])
	await rig.leave_level(level)


func test_a_level_in_another_tab_is_redrawn_when_it_comes_back() -> void:
	var level = await rig.make_level()
	var other := Node3D.new()
	other.name = "OtherScene"
	rig.viewport.add_child(other)
	var behind = LevelRoot.new()
	behind.name = "LevelRoot"
	behind.auto_spawn_player = false
	behind.hflevel_autosave_enabled = false
	other.add_child(behind)
	behind.owner = other
	var far: DraftBrush = rig.box(behind, "far", Vector3.ZERO)
	rig.plugin.stand_in_editor.scene_root = other
	rig.plugin.scene_changed.emit(other)
	rig.plugin.stand_in_editor.scene_root = rig.scene_root
	rig.plugin.scene_changed.emit(rig.scene_root)

	_pick_color(HFOverlayColors.ADDITIVE_BRUSH, Color(0.0, 0.0, 1.0, 0.4))
	assert_eq(
		_look(far).albedo_color, Color(0.2, 0.8, 0.2, 0.35), "fixture: the tab behind is not drawn"
	)
	rig.plugin.stand_in_editor.scene_root = other
	rig.plugin.scene_changed.emit(other)
	assert_true(
		_near(_look(far).albedo_color, Color(0.0, 0.0, 1.0, 0.4)),
		"it is redrawn in the new colour when it comes to the front"
	)
	var look := _look(far)
	rig.plugin.scene_changed.emit(other)
	assert_same(_look(far), look, "and once, not on every switch")

	rig.plugin.stand_in_editor.scene_root = rig.scene_root
	rig.plugin.scene_changed.emit(rig.scene_root)
	rig.viewport.remove_child(other)
	other.free()
	await rig.leave_level(level)
