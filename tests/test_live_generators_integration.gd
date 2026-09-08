extends GutTest

## Live generators against the systems they have to survive: a real LevelRoot,
## the undo snapshot, the save format, the cutting tools, and the baker.

const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFLevelIOScript = preload("res://addons/hammerforge/hflevel_io.gd")
const BakerScript = preload("res://addons/hammerforge/baker.gd")
const MatMgrScript = preload("res://addons/hammerforge/material_manager.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var baker


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	baker = BakerScript.new()
	add_child_autoqfree(baker)


func after_each():
	root = null
	baker = null


func _arch(overrides: Dictionary = {}) -> Dictionary:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("arch")
	for key in overrides:
		settings[key] = overrides[key]
	return settings


func _only_record():
	for generator_id in root.generator_system.generators:
		return root.generator_system.generators[generator_id]
	return null


func _generated_brushes() -> Array:
	var out: Array = []
	var record = _only_record()
	if record == null:
		return out
	for brush_id in record.brush_ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if brush != null:
			out.append(brush)
	return out


func _baked_triangles(brush: DraftBrush) -> Array:
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var result = baker.bake_from_faces([brush], mat_mgr)
	if result == null:
		return []
	add_child_autoqfree(result)
	var triangles: Array = []
	for child in result.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh: Mesh = (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		var node_xform: Transform3D = (child as MeshInstance3D).transform
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var raw_indices = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = (
				raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
			)
			if indices.is_empty():
				for i in range(0, verts.size() - 2, 3):
					triangles.append(
						[
							node_xform * verts[i],
							node_xform * verts[i + 1],
							node_xform * verts[i + 2]
						]
					)
			else:
				for i in range(0, indices.size() - 2, 3):
					triangles.append(
						[
							node_xform * verts[indices[i]],
							node_xform * verts[indices[i + 1]],
							node_xform * verts[indices[i + 2]]
						]
					)
	return triangles


func _outward_ratio(brush: DraftBrush) -> float:
	var triangles := _baked_triangles(brush)
	if triangles.is_empty():
		return -1.0
	var centre := Vector3.ZERO
	var count := 0
	for tri in triangles:
		for v in tri:
			centre += v
			count += 1
	centre /= float(count)
	var outward := 0
	var counted := 0
	for tri in triangles:
		var a: Vector3 = tri[0]
		var normal: Vector3 = (tri[2] - a).cross(tri[1] - a)
		if normal.length() < 0.000001:
			continue
		var to_face: Vector3 = ((tri[0] + tri[1] + tri[2]) / 3.0) - centre
		if to_face.length() < 0.000001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


# ===========================================================================
# The subsystem exists on a real level
# ===========================================================================


func test_a_level_root_builds_the_generator_system():
	assert_not_null(root.generator_system, "LevelRoot must construct the generator system")


func test_level_root_exposes_the_methods_undo_dispatches_by_name():
	for method_name in [
		"create_arch",
		"create_generator",
		"regenerate_generator",
		"detach_generator",
		"generator_for_selection",
	]:
		assert_true(root.has_method(method_name), "LevelRoot must expose %s" % method_name)


func test_creating_an_arch_through_level_root_records_it():
	var result = root.create_arch(_arch({"segments": 5}), Vector3.ZERO)
	assert_true(result.ok, result.message)
	assert_eq(root.generator_system.generators.size(), 1)
	assert_eq(_only_record().brush_ids.size(), 5)


func test_an_invalid_arch_through_level_root_creates_nothing():
	var result = root.create_arch(_arch({"segments": 0}), Vector3.ZERO)
	assert_false(result.ok)
	assert_eq(root.generator_system.generators.size(), 0)


# ===========================================================================
# Undo and the save format
# ===========================================================================


func test_generator_records_survive_a_state_round_trip():
	assert_true(root.create_arch(_arch({"segments": 5, "radius": 175.0}), Vector3.ZERO).ok)
	var state: Dictionary = root.capture_state()
	assert_true(state.has("generators"), "the snapshot must carry generator records")
	assert_eq(state["generators"].size(), 1)

	root.generator_system.clear()
	assert_eq(root.generator_system.generators.size(), 0)
	root.restore_state(state)
	var record = _only_record()
	assert_not_null(record, "a restored level must remember its structures")
	assert_eq(record.type, "arch")
	assert_almost_eq(float(record.settings["radius"]), 175.0, 0.001)


func test_restored_brushes_still_know_their_generator():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	var record = _only_record()
	assert_not_null(record)
	var found = root.generator_for_selection([str(record.brush_ids[0])])
	assert_not_null(found, "a piece must still find its generator after a restore")
	assert_eq(found.generator_id, record.generator_id)


func test_undoing_a_regeneration_restores_the_previous_structure():
	assert_true(root.create_arch(_arch({"segments": 4, "radius": 100.0}), Vector3.ZERO).ok)
	var before: Dictionary = root.capture_state()
	var record = _only_record()
	assert_true(
		root.regenerate_generator(record.generator_id, _arch({"segments": 9, "radius": 300.0})).ok
	)
	assert_eq(_only_record().brush_ids.size(), 9)
	root.restore_state(before)
	var restored = _only_record()
	assert_not_null(restored)
	assert_eq(restored.brush_ids.size(), 4, "undo must bring the old structure back")
	assert_almost_eq(float(restored.settings["radius"]), 100.0, 0.001)


func test_a_generator_record_survives_the_hflevel_encoding():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3(10, 20, 30)).ok)
	var captured: Array = root.generator_system.capture()
	var decoded = HFLevelIOScript.decode_variant(HFLevelIOScript.encode_variant(captured))
	assert_true(decoded is Array)
	assert_eq((decoded as Array).size(), 1)
	root.generator_system.clear()
	root.generator_system.restore(decoded)
	var record = _only_record()
	assert_not_null(record)
	assert_true(record.placement.origin.is_equal_approx(Vector3(10, 20, 30)))


# ===========================================================================
# Regenerated geometry is still real geometry
# ===========================================================================


func test_an_untouched_arch_segment_bakes_outward_facing_triangles():
	assert_true(root.create_arch(_arch({"segments": 5}), Vector3.ZERO).ok)
	var segments := _generated_brushes()
	assert_gt(segments.size(), 0)
	assert_almost_eq(_outward_ratio(segments[0]), 1.0, 0.0001, "the control must pass")


func test_a_regenerated_arch_still_bakes_outward_facing_triangles():
	assert_true(root.create_arch(_arch({"segments": 5}), Vector3.ZERO).ok)
	var record = _only_record()
	assert_true(
		root.regenerate_generator(record.generator_id, _arch({"segments": 7, "radius": 200.0})).ok
	)
	for segment in _generated_brushes():
		assert_almost_eq(
			_outward_ratio(segment), 1.0, 0.0001, "a rebuilt segment would bake inside out"
		)


func test_regenerating_many_times_does_not_degrade_the_geometry():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	var record = _only_record()
	for i in 5:
		assert_true(
			(
				root
				. regenerate_generator(
					record.generator_id, _arch({"segments": 4 + i, "radius": 100.0 + 20.0 * i})
				)
				. ok
			)
		)
	assert_eq(_only_record().brush_ids.size(), 8)
	for segment in _generated_brushes():
		assert_almost_eq(_outward_ratio(segment), 1.0, 0.0001)


# ===========================================================================
# Living alongside the tools that change geometry
# ===========================================================================


func test_a_generated_segment_can_be_clipped_and_the_structure_detached():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	var record = _only_record()
	var victim := str(record.brush_ids[0])
	assert_true(root.clip_brush_by_plane(victim, Plane(Vector3.BACK, 0.0)).ok)
	assert_true(
		root.detach_generator(record.generator_id),
		"a structure that has been cut about must still be detachable"
	)
	assert_eq(root.generator_system.generators.size(), 0)


func test_regenerating_after_a_piece_was_clipped_away_still_works():
	# Clipping replaces a piece with two new brushes that the record has never
	# heard of, so the record goes stale. It is a hint, not a guarantee.
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	var record = _only_record()
	assert_true(root.clip_brush_by_plane(str(record.brush_ids[0]), Plane(Vector3.BACK, 0.0)).ok)
	var result = root.regenerate_generator(record.generator_id, _arch({"segments": 4}))
	assert_true(result.ok, "a stale record must not break a rebuild: %s" % result.message)
	assert_eq(_only_record().brush_ids.size(), 4)


func test_a_detached_structure_is_left_alone_by_later_rebuilds():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	var record = _only_record()
	var generator_id: String = record.generator_id
	assert_true(root.detach_generator(generator_id))
	var result = root.regenerate_generator(generator_id, _arch({"segments": 8}))
	assert_false(result.ok, "a forgotten structure cannot be rebuilt")


func test_two_arches_keep_separate_records():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	assert_true(root.create_arch(_arch({"segments": 6}), Vector3(500, 0, 0)).ok)
	assert_eq(root.generator_system.generators.size(), 2)
	var sizes: Array = []
	for generator_id in root.generator_system.generators:
		sizes.append(root.generator_system.generators[generator_id].brush_ids.size())
	sizes.sort()
	assert_eq(sizes, [4, 6], "each structure remembers its own shape")


func test_regenerating_one_arch_leaves_the_other_alone():
	assert_true(root.create_arch(_arch({"segments": 4}), Vector3.ZERO).ok)
	var first = _only_record()
	assert_true(root.create_arch(_arch({"segments": 6}), Vector3(500, 0, 0)).ok)
	var second = null
	for generator_id in root.generator_system.generators:
		if generator_id != first.generator_id:
			second = root.generator_system.generators[generator_id]
	assert_not_null(second)
	var untouched := Array(second.brush_ids)
	assert_true(root.regenerate_generator(first.generator_id, _arch({"segments": 10})).ok)
	assert_eq(Array(second.brush_ids), untouched, "the other structure must not move")
	for brush_id in untouched:
		assert_not_null(root.brush_system.find_brush_by_id(str(brush_id)))


# ===========================================================================
# Every structure type on a real level
# ===========================================================================


func _settings(type: String, overrides: Dictionary = {}) -> Dictionary:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings(type)
	for key in overrides:
		settings[key] = overrides[key]
	return settings


func _small(type: String) -> Dictionary:
	# Small enough to bake every piece of, big enough to be the real shape.
	match type:
		"arch":
			return _settings(type, {"segments": 4})
		"stairs":
			return _settings(type, {"steps": 4})
		"spiral_stairs":
			return _settings(type, {"steps": 4})
		_:
			return _settings(type, {"rings": 2, "segments": 6})


func test_every_structure_type_bakes_outward_facing_triangles():
	# The control is a plain box built the ordinary way. If the control fails the
	# measurement is wrong; if only the structure fails the geometry is wrong.
	var control := DraftBrush.new()
	control.size = Vector3(64, 64, 64)
	control.brush_id = "control"
	control.set_meta("brush_id", "control")
	root.draft_brushes_node.add_child(control)
	control.global_position = Vector3(999, 0, 0)
	control.rebuild_preview()
	assert_almost_eq(_outward_ratio(control), 1.0, 0.0001, "the control must pass")

	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		assert_true(
			root.create_generator(name, _small(name), Transform3D.IDENTITY).ok,
			"%s could not be created" % name
		)
		var record = _record_of_type(name)
		for brush_id in record.brush_ids:
			var brush = root.brush_system.find_brush_by_id(str(brush_id))
			assert_almost_eq(
				_outward_ratio(brush), 1.0, 0.0001, "a %s piece would bake inside out" % name
			)


func test_every_structure_type_still_bakes_outward_after_a_rebuild():
	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		assert_true(root.create_generator(name, _small(name), Transform3D.IDENTITY).ok)
		var record = _record_of_type(name)
		var changed := _small(name)
		changed["_unused"] = 0  # dropped by the schema; the rest is what it was
		assert_true(root.regenerate_generator(record.generator_id, changed).ok)
		for brush_id in record.brush_ids:
			var brush = root.brush_system.find_brush_by_id(str(brush_id))
			assert_almost_eq(
				_outward_ratio(brush), 1.0, 0.0001, "a rebuilt %s piece bakes inside out" % name
			)


func test_every_structure_type_survives_a_state_round_trip():
	for type in HFGeneratorSystemScript.known_types():
		assert_true(root.create_generator(str(type), _small(str(type)), Transform3D.IDENTITY).ok)
	var expected: int = HFGeneratorSystemScript.known_types().size()
	var state: Dictionary = root.capture_state()
	root.generator_system.clear()
	root.restore_state(state)
	assert_eq(root.generator_system.generators.size(), expected, "a type was lost in the save")
	for generator_id in root.generator_system.generators:
		var record = root.generator_system.generators[generator_id]
		assert_gt(record.brush_ids.size(), 0)
		assert_eq(
			record.brush_signatures.size(),
			record.brush_ids.size(),
			"%s forgot what its pieces were" % record.type
		)


func test_a_structure_dragged_across_the_level_rebuilds_where_it_now_is():
	# End to end through LevelRoot: the defect was that it rebuilt where it was
	# created, which made "change your mind after seeing it in place" impossible.
	assert_true(root.create_generator("stairs", _small("stairs"), Transform3D.IDENTITY).ok)
	var record = _record_of_type("stairs")
	var delta := Vector3(256.0, 0.0, 128.0)
	for brush_id in record.brush_ids:
		root.brush_system.find_brush_by_id(str(brush_id)).global_position += delta

	assert_true(
		root.regenerate_generator(record.generator_id, _settings("stairs", {"steps": 6})).ok
	)
	var centre := Vector3.ZERO
	for brush_id in record.brush_ids:
		centre += root.brush_system.find_brush_by_id(str(brush_id)).global_position
	centre /= float(record.brush_ids.size())
	assert_almost_eq(centre.x, delta.x, 1.0, "the flight jumped back to where it was made")
	assert_almost_eq(centre.z, delta.z, 1.0)


func test_the_edit_count_a_rebuild_would_overwrite_is_visible_from_level_root():
	assert_true(root.create_generator("stairs", _small("stairs"), Transform3D.IDENTITY).ok)
	var record = _record_of_type("stairs")
	assert_eq(root.edited_generator_pieces(record.generator_id), 0)
	var victim = root.brush_system.find_brush_by_id(str(record.brush_ids[0]))
	victim.size += Vector3(16, 16, 16)
	assert_eq(root.edited_generator_pieces(record.generator_id), 1)


func test_structures_of_different_types_keep_separate_records():
	assert_true(root.create_generator("dome", _small("dome"), Transform3D.IDENTITY).ok)
	assert_true(
		(
			root
			. create_generator(
				"stairs", _small("stairs"), Transform3D(Basis.IDENTITY, Vector3(512, 0, 0))
			)
			. ok
		)
	)
	var dome = _record_of_type("dome")
	var stairs = _record_of_type("stairs")
	var stairs_ids := Array(stairs.brush_ids)
	assert_true(root.regenerate_generator(dome.generator_id, _settings("dome", {"rings": 3})).ok)
	for brush_id in stairs_ids:
		assert_not_null(
			root.brush_system.find_brush_by_id(str(brush_id)),
			"rebuilding the dome took a step with it"
		)


func _record_of_type(type: String):
	for generator_id in root.generator_system.generators:
		if root.generator_system.generators[generator_id].type == type:
			return root.generator_system.generators[generator_id]
	return null


func test_a_saved_and_reopened_structure_does_not_read_as_edited():
	# The failure this catches would be constant: the pieces come back out of the
	# save format rebuilt from serialized floats, and if that round trip moves a
	# vertex by a hair, every structure in the level warns that it has been edited
	# by hand and the warning stops meaning anything.
	for type in HFGeneratorSystemScript.known_types():
		assert_true(root.create_generator(str(type), _small(str(type)), Transform3D.IDENTITY).ok)
	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	for generator_id in root.generator_system.generators:
		var record = root.generator_system.generators[generator_id]
		assert_eq(
			root.edited_generator_pieces(generator_id),
			0,
			"a reopened %s claims pieces were edited by hand" % record.type
		)
		assert_eq(
			root.generator_system.relocation_delta(generator_id),
			Vector3.ZERO,
			"a reopened %s claims it was moved" % record.type
		)


func test_a_structure_turned_as_a_whole_warns_rather_than_silently_straightening():
	# Rotation is not recovered — only translation is — so the honest behaviour is
	# that every piece reads as edited and the user is told before Update
	# straightens the structure out.
	assert_true(root.create_generator("stairs", _small("stairs"), Transform3D.IDENTITY).ok)
	var record = _record_of_type("stairs")
	for brush_id in record.brush_ids:
		root.brush_system.find_brush_by_id(str(brush_id)).rotate_y(0.4)
	assert_eq(
		root.edited_generator_pieces(record.generator_id),
		record.brush_ids.size(),
		"a turned structure must not rebuild silently"
	)


func test_a_moved_structure_can_still_be_detached_where_it_stands():
	assert_true(root.create_generator("dome", _small("dome"), Transform3D.IDENTITY).ok)
	var record = _record_of_type("dome")
	var ids := Array(record.brush_ids)
	for brush_id in ids:
		root.brush_system.find_brush_by_id(str(brush_id)).global_position += Vector3(64, 0, 0)
	assert_true(root.detach_generator(record.generator_id))
	var centre := Vector3.ZERO
	for brush_id in ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		assert_not_null(brush, "detaching must keep the geometry")
		centre += brush.global_position
	centre /= float(ids.size())
	assert_almost_eq(centre.x, 64.0, 1.0, "and leave it where it stands")
