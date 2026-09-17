extends GutTest

## What an undo pays for that it does not need (#705).
##
## `restore_state()` has reconciled since #600: a brush whose record is identical
## to what it would capture right now is kept rather than rebuilt, and on a
## 900-brush map a one-brush edit rebuilds one. But the restore then called
## `set_materials()`, which ends in a rebuild of every brush preview in the
## level, whether or not the palette was part of what changed. That was 141 ms of
## the 188 an undo cost at that size, spent repainting exactly the brushes the
## reconcile had just decided to keep.
##
## The cost itself is recorded by `tools/vibe/scenarios/big_level.gd`. What is
## asserted here is the thing that makes the saving safe: the refresh is skipped
## only when the palette is the same one, and still happens when it is not.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _level() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _material(hue: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(hue, 0.5, 0.8)
	return mat


## Three brushes, each painted from a two-slot palette.
func _painted_level() -> LevelRoot:
	var root := _level()
	root.material_manager.materials.append(_material(0.0))
	root.material_manager.materials.append(_material(0.5))
	for i in 3:
		var brush = root.create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(2, 2, 2),
				"center": Vector3(i * 4, 0, 0),
				"brush_id": "b%d" % i
			}
		)
		for face in brush.faces:
			if face:
				face.material_idx = i % 2
		brush.rebuild_preview()
	return root


func _brushes(root: LevelRoot) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			out.append(child)
	return out


## Which mesh object each brush is currently showing.
##
## `rebuild_preview()` builds a fresh `ArrayMesh` every time, so a refresh that
## happened is a set of different objects and one that did not is the same ones.
func _preview_meshes(root: LevelRoot) -> Array:
	var out: Array = []
	for brush in _brushes(root):
		out.append(brush.mesh_instance.mesh.get_instance_id() if brush.mesh_instance else 0)
	return out


# ===========================================================================
# palette_matches
# ===========================================================================


func test_the_same_materials_in_the_same_order_match():
	var root := _painted_level()
	var live: Array = root.material_manager.materials.duplicate()
	assert_true(root.material_manager.palette_matches(live))


func test_a_palette_of_a_different_length_does_not_match():
	var root := _painted_level()
	var shorter: Array = root.material_manager.materials.duplicate()
	shorter.pop_back()
	assert_false(root.material_manager.palette_matches(shorter))


func test_a_different_material_in_a_slot_does_not_match():
	var root := _painted_level()
	var swapped: Array = root.material_manager.materials.duplicate()
	swapped[0] = _material(0.25)
	assert_false(root.material_manager.palette_matches(swapped))


func test_the_same_materials_in_a_different_order_do_not_match():
	# Order is what `material_idx` indexes, so two slots swapped repaints the
	# level even though the set of materials is the same.
	var root := _painted_level()
	var reordered: Array = root.material_manager.materials.duplicate()
	reordered.reverse()
	assert_false(root.material_manager.palette_matches(reordered))


func test_a_material_edited_in_place_still_matches():
	# The same object in the same slot, and the level is already showing the
	# edit, so there is nothing for a restore to put back.
	var root := _painted_level()
	var live: Array = root.material_manager.materials.duplicate()
	(live[0] as StandardMaterial3D).albedo_color = Color.RED
	assert_true(root.material_manager.palette_matches(live))


# ===========================================================================
# What the restore does with it
# ===========================================================================


func test_an_undo_that_changes_nothing_does_not_repaint_the_level():
	var root := _painted_level()
	var state: Dictionary = root.capture_state()
	var before := _preview_meshes(root)
	root.restore_state(state)
	assert_eq(_preview_meshes(root), before, "the brushes are the ones that were already there")


func test_an_undo_that_moves_one_brush_leaves_the_others_alone():
	var root := _painted_level()
	var state: Dictionary = root.capture_state()
	var before := _preview_meshes(root)
	var moved: Node3D = _brushes(root)[1]
	moved.position += Vector3(0, 1, 0)
	moved.rebuild_preview()
	root.restore_state(state)
	var after := _preview_meshes(root)
	assert_eq(after.size(), before.size(), "the same three brushes")
	assert_eq(after[0], before[0], "the brush nobody touched was not rebuilt")
	assert_eq(after[2], before[2], "nor the one after it")


func test_an_undo_that_puts_a_palette_back_does_repaint():
	# The guard must not skip a refresh that is needed. The snapshot's palette is
	# not the live one here, so every brush has to be repainted from it.
	var root := _painted_level()
	var state: Dictionary = root.capture_state()
	var before := _preview_meshes(root)
	root.material_manager.materials[0] = _material(0.8)
	root.restore_state(state)
	var after := _preview_meshes(root)
	for i in after.size():
		assert_ne(after[i], before[i], "brush %d was repainted from the restored palette" % i)


func test_the_restored_palette_is_the_one_the_level_ends_up_with():
	var root := _painted_level()
	var original: Material = root.material_manager.materials[0]
	var state: Dictionary = root.capture_state()
	root.material_manager.materials[0] = _material(0.8)
	root.restore_state(state)
	assert_eq(root.material_manager.materials[0], original, "the slot holds what the snapshot held")


func test_a_palette_that_grew_is_put_back_to_the_size_it_was():
	var root := _painted_level()
	var state: Dictionary = root.capture_state()
	root.material_manager.materials.append(_material(0.9))
	root.restore_state(state)
	assert_eq(
		root.material_manager.materials.size(), 2, "the slot added after the snapshot is gone"
	)
