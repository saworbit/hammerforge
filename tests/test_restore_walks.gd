extends GutTest

## An undo of a whole level step walks fewer nodes where it can (#1866): the
## visibility walk draws only what the restore built when nothing else it reads
## has changed, and the walks for stale structure, array and prefab tags are
## skipped when there are none of those before or after. What a mapper sees after
## an undo must be what it was.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBakeSplit = preload("res://addons/hammerforge/hf_bake_split.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(at: Vector3, shape: int = 0) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": shape,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func test_a_brush_an_undo_builds_into_a_hidden_visgroup_comes_back_hidden():
	var kept := _box(Vector3.ZERO)
	var changed := _box(Vector3(4, 0, 0))
	var changed_id := str(changed.brush_id)
	root.visgroup_system.create_visgroup("hidden")
	root.visgroup_system.add_to_visgroup(changed, "hidden")
	root.visgroup_system.set_visgroup_visible("hidden", false)
	assert_false(changed.visible, "fixture: hidden")
	var before: Dictionary = root.capture_state()
	changed.size = Vector3(3, 3, 3)
	root.restore_state(before)
	var back = root.find_brush_by_id(changed_id)
	assert_ne(back, changed, "fixture: the changed brush is built again")
	assert_false(back.visible, "built into a hidden visgroup, it is hidden")
	assert_true(kept.visible, "the brush the undo kept is still shown")


## An undo keeps the eyes of now (#1981), so a load is the restore that can
## still show a visgroup again. The brush it kept must be drawn with it.
func test_a_load_that_shows_a_visgroup_again_draws_the_brushes_it_kept():
	var member := _box(Vector3.ZERO)
	root.visgroup_system.create_visgroup("walls")
	root.visgroup_system.add_to_visgroup(member, "walls")
	root.visgroup_system.refresh_visibility()
	var undo_step: Dictionary = root.capture_state()
	var file: Dictionary = root.capture_state(false)
	root.visgroup_system.set_visgroup_visible("walls", false)
	assert_false(member.visible, "fixture: hidden")
	root.restore_state(undo_step)
	assert_eq(root.draft_brushes_node.get_child(0), member, "fixture: the brush is kept")
	assert_false(member.visible, "an undo leaves the visgroup hidden, and its brush")
	root.restore_state(file)
	assert_eq(root.draft_brushes_node.get_child(0), member, "fixture: the brush is kept")
	assert_true(member.visible, "the file shows the visgroup again, and so its brush")


func test_the_walk_draws_only_what_it_is_handed_while_nothing_it_reads_changes():
	var left := _box(Vector3.ZERO)
	var right := _box(Vector3(4, 0, 0))
	var visgroups = root.visgroup_system
	visgroups.refresh_visibility()
	left.visible = false
	visgroups.refresh_visibility([right])
	assert_false(left.visible, "a node it was not handed is left as it was")
	assert_true(right.visible)
	visgroups.create_visgroup("doors")
	visgroups.refresh_visibility([right])
	assert_true(left.visible, "a new visgroup is a change, and every node is drawn")


func test_a_record_keeps_sides_for_every_shape_built_from_them():
	var sided := [
		root.BrushShape.PYRAMID,
		root.BrushShape.PRISM_TRI,
		root.BrushShape.PRISM_PENT,
		root.BrushShape.CYLINDER,
		root.BrushShape.CONE,
		root.BrushShape.SPHERE,
		root.BrushShape.ELLIPSOID,
		root.BrushShape.CAPSULE,
		root.BrushShape.TORUS,
	]
	var x := 0.0
	for shape in root.BrushShape.values():
		if shape == root.BrushShape.CUSTOM:
			continue
		var brush := _box(Vector3(x, 0, 0), shape)
		x += 4.0
		var record: Dictionary = root.brush_system.get_brush_info_from_node(brush)
		assert_eq(
			record.has("sides"),
			sided.has(shape),
			"%s keeps its sides" % root.BrushShape.find_key(shape)
		)


func test_a_record_carries_the_entity_and_bake_settings_a_brush_has_and_no_others():
	var plain := _box(Vector3.ZERO)
	var tagged := _box(Vector3(4, 0, 0))
	HFBrushEntity.give(tagged, {HFBrushEntity.CLASS_META: "func_door"})
	HFBakeSplit.set_brush_cast_shadow(tagged, 0)
	HFBakeSplit.set_brush_lightmap_scale(tagged, 2.0)
	var record: Dictionary = root.brush_system.get_brush_info_from_node(tagged)
	assert_eq(record.get(HFBrushEntity.CLASS_META), "func_door")
	assert_eq(record.get(HFBakeSplit.CAST_SHADOW_META), 0)
	assert_almost_eq(float(record.get(HFBakeSplit.LIGHTMAP_SCALE_META, 0.0)), 2.0, 0.0001)
	var bare: Dictionary = root.brush_system.get_brush_info_from_node(plain)
	for key in (
		HFBrushEntity.FIELDS + [HFBakeSplit.CAST_SHADOW_META, HFBakeSplit.LIGHTMAP_SCALE_META]
	):
		assert_false(bare.has(key), "a plain brush has no %s" % key)


func test_an_undo_puts_back_an_order_a_brush_was_moved_out_of():
	var first := _box(Vector3.ZERO)
	var second := _box(Vector3(4, 0, 0))
	var third := _box(Vector3(8, 0, 0))
	var before: Dictionary = root.capture_state()
	root.draft_brushes_node.move_child(third, 0)
	root.restore_state(before)
	assert_eq(
		root.draft_brushes_node.get_children(), [first, second, third], "in the order recorded"
	)


func test_a_committed_cutter_an_undo_builds_stays_hidden():
	_box(Vector3.ZERO)
	(
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(1, 1, 1),
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"committed": true,
			}
		)
	)
	root.visgroup_system.refresh_visibility()
	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	assert_eq(root.committed_node.get_child_count(), 1, "fixture: one cutter")
	for cutter in root.committed_node.get_children():
		assert_false(cutter.visible, "its cut hides it, whatever its visgroups say")
