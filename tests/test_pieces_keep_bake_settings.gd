extends GutTest

## Clip, Hollow, Carve, Intersect and Merge replace a brush with others, and the
## others are still that brush to the bake: a ceiling set to cast no shadow, or a
## floor set to a coarse lightmap, stays so once it is cut (#1660). The pieces
## took the visgroups and the entity and dropped Cast Shadows and Lightmap Scale.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBakeSplit = preload("res://addons/hammerforge/hf_bake_split.gd")

const OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, size: Vector3, at: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _id(brush: Node) -> String:
	return str(brush.get("brush_id"))


## Cast Shadows Off and Lightmap Scale 4 on each of `brushes`.
func _set_off_and_coarse(root: LevelRoot, brushes: Array) -> void:
	var ids: Array = brushes.map(_id)
	root.set_brush_cast_shadow(ids, OFF)
	root.set_brush_lightmap_scale(ids, 4.0)


func _assert_every_brush_keeps(root: LevelRoot, count: int, what: String) -> void:
	var brushes: Array = root._iter_managed_brush_nodes()
	assert_eq(brushes.size(), count, "%s: brushes left" % what)
	for brush in brushes:
		assert_eq(HFBakeSplit.brush_cast_shadow(brush), OFF, "%s: keeps Cast Shadows" % what)
		assert_almost_eq(
			HFBakeSplit.brush_lightmap_scale(brush), 4.0, 0.0001, "%s: keeps Lightmap Scale" % what
		)
		var info: Dictionary = root.get_brush_info_from_node(brush)
		assert_eq(info.get(HFBakeSplit.CAST_SHADOW_META), OFF, "%s: in its record" % what)


func test_clip_pieces_keep_the_bake_settings():
	var root := _fresh_root()
	var box := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	_set_off_and_coarse(root, [box])
	assert_true(root.clip_brush_by_id(_id(box), 0, 0.0).ok)
	_assert_every_brush_keeps(root, 2, "clip")


func test_hollow_walls_keep_the_bake_settings():
	var root := _fresh_root()
	var box := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	_set_off_and_coarse(root, [box])
	assert_true(root.hollow_brush_by_id(_id(box), 0.2).ok)
	_assert_every_brush_keeps(root, 6, "hollow")


func test_carve_pieces_keep_the_bake_settings():
	var root := _fresh_root()
	var wall := _box(root, Vector3(4, 2, 0.4), Vector3(0, 1, 0))
	_set_off_and_coarse(root, [wall])
	var door := _box(root, Vector3(1, 1, 1), Vector3(0, 1, 0))
	assert_true(root.carve_with_brush(_id(door)).ok)
	var pieces: int = root._iter_managed_brush_nodes().size()
	assert_gt(pieces, 1, "the door cut the wall into pieces")
	_assert_every_brush_keeps(root, pieces, "carve")


func test_intersect_keeps_the_target_bake_settings():
	var root := _fresh_root()
	var target := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	var other := _box(root, Vector3(2, 2, 2), Vector3(1, 1, 0))
	_set_off_and_coarse(root, [target])
	assert_true(root.intersect_brushes_by_ids([_id(target), _id(other)]).ok)
	_assert_every_brush_keeps(root, 1, "intersect")


func test_merge_keeps_the_first_brush_bake_settings():
	var root := _fresh_root()
	var left := _box(root, Vector3(1, 1, 1), Vector3(0, 0.5, 0))
	var right := _box(root, Vector3(1, 1, 1), Vector3(1, 0.5, 0))
	_set_off_and_coarse(root, [left, right])
	assert_true(root.merge_brushes_by_ids([_id(left), _id(right)]).ok)
	_assert_every_brush_keeps(root, 1, "merge")


## The next setting added to the record should reach the pieces too: whatever
## `HFBakeSplit.fields()` holds comes through the one place pieces are built.
func test_every_bake_field_reaches_a_piece_record():
	var root := _fresh_root()
	var box := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	_set_off_and_coarse(root, [box])
	var fields := HFBakeSplit.fields(box)
	assert_false(fields.is_empty(), "the brush holds its own settings")
	var faces: Array = (box as DraftBrush).get_faces()
	var infos: Array = root.brush_system._piece_infos_from_faces(box, [faces])
	for key in fields:
		assert_eq(infos[0].get(key), fields[key], "the piece record carries %s" % key)
