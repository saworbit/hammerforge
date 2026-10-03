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
