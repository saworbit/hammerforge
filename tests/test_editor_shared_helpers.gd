extends GutTest

## Jobs three or so places each did in their own copy, now done in one: listing
## shortcuts by category (#906), the tools' drawing overlay (#904) and packing a
## paint chunk (#900).

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFShortcutDialogType = preload("res://addons/hammerforge/ui/hf_shortcut_dialog.gd")
const HFHotkeyPaletteType = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
const HFEditorToolType = preload("res://addons/hammerforge/hf_editor_tool.gd")
const HFPathToolType = preload("res://addons/hammerforge/hf_path_tool.gd")
const HFPolygonToolType = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const HFMeasureToolType = preload("res://addons/hammerforge/hf_measure_tool.gd")
const HFPaintLayerType = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGridType = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

const TRANSFORM_ACTIONS := ["rotate_ccw", "rotate_cw", "flip_selection", "reset_rotation"]

# -- Shortcuts by category (#906) ----------------------------------------------


func test_grouped_actions_follow_the_order_they_are_given():
	var keymap = HFKeymapType.load_or_default()
	var groups: Array = keymap.grouped_actions(["Selection", "Workflow", "No Such Category"])
	assert_eq(groups.size(), 2, "a category with no action is left out")
	assert_eq(groups[0][0], "Selection")
	assert_eq(groups[1][0], "Workflow")
	for action in groups[0][1]:
		assert_eq(HFKeymapType.get_category(action), "Selection")


## The dialog's own order left Transform out, so Rotate, Flip and Reset Rotation
## had bindings and no row in it.
func test_the_shortcut_dialog_lists_the_transform_shortcuts():
	var keymap = HFKeymapType.load_or_default()
	var dialog = HFShortcutDialogType.new()
	add_child_autofree(dialog)
	dialog.populate(keymap)
	var listed: Array = []
	var category: TreeItem = dialog._tree.get_root().get_first_child()
	while category:
		var item := category.get_first_child()
		while item:
			listed.append(str(item.get_meta("action", "")))
			item = item.get_next()
		category = category.get_next()
	for action in TRANSFORM_ACTIONS:
		assert_has(listed, action, "the dialog lists %s" % action)


func test_the_palette_and_the_dialog_list_the_same_shortcuts():
	var keymap = HFKeymapType.load_or_default()
	var palette = HFHotkeyPaletteType.new()
	add_child_autofree(palette)
	palette.populate(keymap)
	var in_palette: Array = []
	for entry in palette._entries:
		in_palette.append(str(entry.get("action", "")))
	var dialog = HFShortcutDialogType.new()
	add_child_autofree(dialog)
	dialog.populate(keymap)
	var in_dialog: Array = []
	var category: TreeItem = dialog._tree.get_root().get_first_child()
	while category:
		var item := category.get_first_child()
		while item:
			in_dialog.append(str(item.get_meta("action", "")))
			item = item.get_next()
		category = category.get_next()
	in_palette.sort()
	in_dialog.sort()
	assert_eq(in_dialog, in_palette)


# -- The tools' overlay (#904) ---------------------------------------------------


func test_every_drawing_tool_gets_the_same_overlay():
	var holder := Node3D.new()
	add_child_autofree(holder)
	var names := {
		"path": [HFPathToolType.new(), "_PathToolPreview"],
		"polygon": [HFPolygonToolType.new(), "_PolygonToolPreview"],
		"measure": [HFMeasureToolType.new(), "MeasureToolMesh"],
	}
	for label in names:
		var tool = names[label][0]
		tool.root = holder
		tool._ensure_mesh()
		var overlay: MeshInstance3D = tool._mesh_instance
		assert_not_null(overlay, "the %s tool has an overlay" % label)
		assert_eq(overlay.name, names[label][1])
		assert_eq(overlay.get_parent(), holder, "under the level")
		assert_true(overlay.mesh is ImmediateMesh, "drawn on an ImmediateMesh")
		assert_eq(tool._immediate_mesh, overlay.mesh, "which the tool draws on")
		assert_eq(overlay.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var material := overlay.material_override as StandardMaterial3D
		assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
		assert_true(material.vertex_color_use_as_albedo)
		assert_true(material.no_depth_test)
		assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
		tool._ensure_mesh()
		assert_eq(tool._mesh_instance, overlay, "and asking again keeps the one it has")


func test_every_drawing_tool_lets_its_overlay_go_the_same_way():
	var holder := Node3D.new()
	add_child_autofree(holder)
	for tool in [HFPathToolType.new(), HFPolygonToolType.new(), HFMeasureToolType.new()]:
		tool.root = holder
		tool._ensure_mesh()
		var overlay: MeshInstance3D = tool._mesh_instance
		tool._clear_visuals()
		assert_null(overlay.get_parent(), "out of the level at once, not a frame later")
		assert_true(overlay.is_queued_for_deletion(), "and freed")
		assert_null(tool._mesh_instance, "the tool lets go of it")
		assert_null(tool._immediate_mesh)


# -- One snap for the tools (#1468) ----------------------------------------------


class SnapRoot:
	extends Node3D

	var snap_calls := 0

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		snap_calls += 1
		return point.snapped(Vector3(4, 4, 4))


class GridOnlyRoot:
	extends Node3D

	var grid_snap := 0.5


func test_every_drawing_tool_snaps_through_the_level():
	var tools := [HFPathToolType.new(), HFPolygonToolType.new(), HFMeasureToolType.new()]
	for tool in tools:
		var root := SnapRoot.new()
		tool.root = root
		assert_eq(tool.snap_point(Vector3(3, 7, 9)), Vector3(4, 8, 8), "LevelRoot snaps")
		assert_eq(root.snap_calls, 1, "once, through the one helper")
		root.free()


func test_every_drawing_tool_falls_back_to_the_grid_the_same_way():
	# A root without LevelRoot's snap still has a grid. The measure tool used
	# to skip it, so its points went unsnapped where the other two snapped.
	for tool in [HFPathToolType.new(), HFPolygonToolType.new(), HFMeasureToolType.new()]:
		var root := GridOnlyRoot.new()
		tool.root = root
		assert_eq(tool.snap_point(Vector3(0.3, 0.9, -0.2)), Vector3(0.5, 1.0, 0.0))
		root.free()


func test_a_tool_with_no_level_leaves_the_point_alone():
	var tool := HFEditorToolType.new()
	assert_eq(tool.snap_point(Vector3(0.3, 0.9, -0.2)), Vector3(0.3, 0.9, -0.2))


# -- A packed paint chunk (#900) -------------------------------------------------


func test_a_chunk_packs_its_five_channels_as_ints():
	var layer = HFPaintLayerType.new()
	add_child_autofree(layer)
	layer.grid = HFPaintGridType.new()
	layer.set_cell(Vector2i(1, 2), true)
	var cid: Vector2i = layer.get_chunk_ids()[0]
	var packed: Dictionary = layer.packed_chunk(cid)
	assert_eq(packed["cx"], cid.x)
	assert_eq(packed["cy"], cid.y)
	for key in ["bits", "material_ids", "blend_weights", "blend_weights_2", "blend_weights_3"]:
		assert_true(packed[key] is Array, "%s is an Array" % key)
	var bits: Array = packed["bits"]
	assert_eq(bits.size(), layer.get_chunk_bits(cid).size(), "every byte")
	assert_true(bits.any(func(b): return b != 0), "with the painted cell in it")
	assert_false(packed.has("wall_heights"), "wall heights are the region file's to add")
