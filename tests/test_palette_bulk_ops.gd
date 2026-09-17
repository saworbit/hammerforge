extends GutTest

## Getting materials back out of the palette (#661).
##
## Add Prototype Textures puts 150 slots in with one press. The only way back was
## the minus button, 149 times, each press walking every brush and rebuilding
## every preview: 124 ms on a six brush room and minutes of frozen editor on a
## real level, assuming the mapper was willing to press it 149 times.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, at := Vector3.ZERO) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _named_material(label: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	return mat


## What each face points at, by material name rather than by slot number. The
## slot numbers are expected to move; which material a face wears is not.
func _face_materials(root: LevelRoot) -> Array:
	var names: Array = root.get_material_names()
	var out: Array = []
	for node in root.draft_brushes_node.get_children():
		if not root.is_brush_node(node):
			continue
		for face in node.get("faces"):
			var idx: int = int(face.material_idx)
			out.append(str(names[idx]) if idx >= 0 and idx < names.size() else "")
	return out


# ===========================================================================


func test_remove_unused_keeps_what_the_level_wears():
	var root := _fresh_root()
	var brush := _box(root)
	for label in ["a", "b", "c", "d", "e"]:
		root.add_material_to_palette(_named_material(label))
	# Two faces wear "c", one wears "e"; the rest are unset.
	brush.get("faces")[0].material_idx = 2
	brush.get("faces")[1].material_idx = 2
	brush.get("faces")[2].material_idx = 4
	var before := _face_materials(root)

	assert_eq(root.unused_material_slots(), [0, 1, 3], "a, b and d are dead")
	assert_eq(root.remove_unused_materials(), 3, "and all three go in one pass")

	assert_eq(root.get_material_names(), ["c", "e"], "only what the level wears is left")
	assert_eq(
		_face_materials(root), before, "and every face still wears the material it wore before"
	)


func test_clear_empties_the_palette_and_unsets_the_faces():
	var root := _fresh_root()
	var brush := _box(root)
	for label in ["a", "b"]:
		root.add_material_to_palette(_named_material(label))
	brush.get("faces")[0].material_idx = 1
	var face_count: int = brush.get("faces").size()

	assert_eq(root.clear_palette(), 2, "both slots go")

	assert_eq(root.get_materials().size(), 0, "the palette is empty")
	assert_eq(brush.get("faces").size(), face_count, "the geometry is untouched")
	for face in brush.get("faces"):
		assert_eq(int(face.material_idx), -1, "and every face is unset rather than dangling")


func test_a_bulk_removal_is_one_pass_not_one_per_slot():
	# The naive version shifts every face down by one per removal, which gets the
	# right answer only if each pass sees the result of the last. Removing a set
	# in one go is where an off-by-one lands, so this removes from the middle.
	var root := _fresh_root()
	var brush := _box(root)
	for label in ["a", "b", "c", "d", "e", "f"]:
		root.add_material_to_palette(_named_material(label))
	brush.get("faces")[0].material_idx = 0
	brush.get("faces")[1].material_idx = 3
	brush.get("faces")[2].material_idx = 5
	var before := _face_materials(root)

	assert_eq(root.remove_materials_from_palette([1, 2, 4]), 3, "three from the middle")

	assert_eq(root.get_material_names(), ["a", "d", "f"])
	assert_eq(_face_materials(root), before, "the survivors keep their faces")


func test_removing_nothing_changes_nothing():
	var root := _fresh_root()
	root.add_material_to_palette(_named_material("a"))
	assert_eq(root.remove_materials_from_palette([]), 0)
	assert_eq(root.remove_materials_from_palette([7, -1]), 0, "out of range asks for nothing")
	assert_eq(root.get_material_names(), ["a"])


func test_clear_on_an_empty_palette_is_a_no_op():
	var root := _fresh_root()
	assert_eq(root.clear_palette(), 0)
	assert_eq(root.remove_unused_materials(), 0)
