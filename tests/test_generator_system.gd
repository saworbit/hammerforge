extends GutTest

## Live generators: a structure that remembers what made it, and can be made
## again differently.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFGeneratorScript = preload("res://addons/hammerforge/hf_generator.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var brushes: HFBrushSystem
var generators


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	brushes = root.brush_system
	generators = root.generator_system


func after_each():
	root = null
	brushes = null
	generators = null


func _arch(overrides: Dictionary = {}) -> Dictionary:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("arch")
	for key in overrides:
		settings[key] = overrides[key]
	return settings


func _create(overrides: Dictionary = {}, placement := Transform3D.IDENTITY):
	return generators.create("arch", _arch(overrides), placement)


func _only_record():
	for generator_id in generators.generators:
		return generators.generators[generator_id]
	return null


func _brush_count() -> int:
	var count := 0
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			count += 1
	return count


# ===========================================================================
# Creating
# ===========================================================================


func test_creating_records_what_it_made():
	assert_true(_create({"segments": 6}).ok)
	var record = _only_record()
	assert_not_null(record, "creating must leave a record behind")
	assert_eq(record.type, "arch")
	assert_eq(record.brush_ids.size(), 6)
	assert_eq(_brush_count(), 6)


func test_the_record_keeps_the_settings_it_was_built_from():
	assert_true(_create({"segments": 5, "radius": 200.0}).ok)
	var record = _only_record()
	assert_eq(int(record.settings["segments"]), 5)
	assert_almost_eq(float(record.settings["radius"]), 200.0, 0.001)


func test_the_record_keeps_where_it_was_placed():
	var placement := Transform3D(Basis.IDENTITY, Vector3(10, 20, 30))
	assert_true(_create({"segments": 4}, placement).ok)
	assert_true(_only_record().placement.origin.is_equal_approx(Vector3(10, 20, 30)))


func test_every_created_brush_carries_the_generator_id():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	for brush_id in record.brush_ids:
		var brush = brushes.find_brush_by_id(str(brush_id))
		assert_not_null(brush)
		assert_eq(str(brush.get_meta("hf_generator_id", "")), record.generator_id)


func test_an_unknown_type_is_refused():
	var result = generators.create("gazebo", {}, Transform3D.IDENTITY)
	assert_false(result.ok)
	assert_ne(result.fix_hint, "", "a refusal should say what types exist")
	assert_eq(_brush_count(), 0, "a refused generator must leave no debris")


func test_invalid_settings_are_refused_before_anything_is_built():
	assert_false(_create({"segments": 0}).ok)
	assert_eq(_brush_count(), 0)
	assert_eq(generators.generators.size(), 0)


# ===========================================================================
# Finding a generator from its geometry
# ===========================================================================


func test_a_brush_finds_the_generator_that_made_it():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var found = generators.generator_for_brush(str(record.brush_ids[2]))
	assert_not_null(found)
	assert_eq(found.generator_id, record.generator_id)


func test_a_plain_brush_belongs_to_no_generator():
	var b = DraftBrush.new()
	b.brush_id = "plain"
	b.set_meta("brush_id", "plain")
	root.draft_brushes_node.add_child(b)
	brushes._register_brush_id("plain", b)
	assert_null(generators.generator_for_brush("plain"))


func test_a_selection_finds_the_first_generator_in_it():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var found = generators.generator_for_selection(
		["not_a_brush", str(record.brush_ids[1]), "also_not"]
	)
	assert_not_null(found)
	assert_eq(found.generator_id, record.generator_id)


func test_a_selection_of_plain_brushes_finds_nothing():
	assert_null(generators.generator_for_selection(["a", "b"]))


# ===========================================================================
# Regenerating
# ===========================================================================


func test_regenerating_replaces_the_geometry():
	assert_true(_create({"segments": 4, "radius": 100.0}).ok)
	var record = _only_record()
	var old_ids := Array(record.brush_ids)
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 4, "radius": 200.0})).ok
	)
	for brush_id in old_ids:
		assert_null(brushes.find_brush_by_id(str(brush_id)), "the old pieces must be gone")
	assert_eq(_brush_count(), 4, "and replaced one for one")


func test_regenerating_updates_the_record():
	assert_true(_create({"segments": 4, "radius": 100.0}).ok)
	var record = _only_record()
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 4, "radius": 250.0})).ok
	)
	assert_almost_eq(float(_only_record().settings["radius"]), 250.0, 0.001)


func test_regenerating_with_more_segments_makes_more_pieces():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 9})).ok)
	assert_eq(_brush_count(), 9)
	assert_eq(_only_record().brush_ids.size(), 9)


func test_regenerating_with_fewer_segments_makes_fewer_pieces():
	assert_true(_create({"segments": 9}).ok)
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 3})).ok)
	assert_eq(_brush_count(), 3)


func test_regenerating_keeps_the_placement():
	var placement := Transform3D(Basis.IDENTITY, Vector3(0, 500, 0))
	assert_true(_create({"segments": 4}, placement).ok)
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 6})).ok)
	for brush_id in _only_record().brush_ids:
		var brush = brushes.find_brush_by_id(str(brush_id))
		assert_gt(brush.global_position.y, 100.0, "the rebuilt arch must stay where it was put")


func test_materials_survive_a_regeneration_at_the_same_count():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var painted: Array = []
	for i in record.brush_ids.size():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(float(i) / 10.0, 0, 0)
		painted.append(mat)
		brushes.find_brush_by_id(str(record.brush_ids[i])).material_override = mat
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 4, "radius": 150.0})).ok
	)
	var rebuilt = _only_record()
	for i in rebuilt.brush_ids.size():
		var brush = brushes.find_brush_by_id(str(rebuilt.brush_ids[i]))
		assert_eq(brush.material_override, painted[i], "piece %d lost its material" % i)


func test_the_surviving_prefix_keeps_its_materials_when_the_count_shrinks():
	assert_true(_create({"segments": 6}).ok)
	var record = _only_record()
	var first := StandardMaterial3D.new()
	brushes.find_brush_by_id(str(record.brush_ids[0])).material_override = first
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 3})).ok)
	var rebuilt = _only_record()
	assert_eq(
		brushes.find_brush_by_id(str(rebuilt.brush_ids[0])).material_override,
		first,
		"the first piece keeps what was painted on it"
	)


func test_extra_pieces_take_the_default_when_the_count_grows():
	assert_true(_create({"segments": 2, "arc_degrees": 90.0}).ok)
	var record = _only_record()
	var mat := StandardMaterial3D.new()
	for brush_id in record.brush_ids:
		brushes.find_brush_by_id(str(brush_id)).material_override = mat
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 5, "arc_degrees": 90.0})).ok
	)
	var rebuilt = _only_record()
	assert_eq(brushes.find_brush_by_id(str(rebuilt.brush_ids[0])).material_override, mat)
	assert_null(
		brushes.find_brush_by_id(str(rebuilt.brush_ids[4])).material_override,
		"a piece with nothing to inherit takes the default"
	)


func test_regenerating_with_invalid_settings_leaves_the_structure_alone():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var before := Array(record.brush_ids)
	var result = generators.regenerate(record.generator_id, _arch({"segments": 0}))
	assert_false(result.ok, "an unbuildable change must be refused")
	assert_eq(_brush_count(), 4, "and nothing may be deleted on the way")
	for brush_id in before:
		assert_not_null(brushes.find_brush_by_id(str(brush_id)))


func test_regenerating_an_unknown_generator_is_refused():
	assert_false(generators.regenerate("gen_nothing", _arch()).ok)


func test_pieces_deleted_by_hand_are_skipped_on_a_regeneration():
	assert_true(_create({"segments": 5}).ok)
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[2]))
	assert_eq(_brush_count(), 4)
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 5})).ok,
		"a stale record must be a hint, not an error"
	)
	assert_eq(_brush_count(), 5, "the structure comes back whole")


# ===========================================================================
# Detaching and removing
# ===========================================================================


func test_detaching_keeps_the_brushes_and_drops_the_record():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var ids := Array(record.brush_ids)
	assert_true(generators.detach(record.generator_id))
	assert_eq(generators.generators.size(), 0, "the record is forgotten")
	assert_eq(_brush_count(), 4, "the brushes stay")
	for brush_id in ids:
		var brush = brushes.find_brush_by_id(str(brush_id))
		assert_false(brush.has_meta("hf_generator_id"), "and stop claiming a generator")


func test_a_detached_brush_finds_no_generator():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var brush_id := str(record.brush_ids[0])
	generators.detach(record.generator_id)
	assert_null(generators.generator_for_brush(brush_id))


func test_a_redone_detach_leaves_no_tag_behind():
	# Undo and redo restore whole states. A restore that reuses a piece's node
	# kept its tag, so the piece went on claiming a structure that was gone, and
	# the scene file saved it that way (#1306).
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var ids := Array(record.brush_ids)
	var before: Dictionary = root.capture_state()
	assert_true(generators.detach(record.generator_id))
	var after: Dictionary = root.capture_state()
	root.restore_state(before)
	for brush_id in ids:
		var piece = brushes.find_brush_by_id(str(brush_id))
		assert_eq(
			str(piece.get_meta("hf_generator_id", "")), record.generator_id, "undo tags it again"
		)
	root.restore_state(after)
	for brush_id in ids:
		var piece = brushes.find_brush_by_id(str(brush_id))
		assert_false(piece.has_meta("hf_generator_id"), "redo takes the tag off %s" % brush_id)


func test_a_restore_keeps_the_tag_on_every_piece_a_record_lists():
	assert_true(_create({"segments": 4}).ok)
	var kept = _only_record()
	assert_true(_create({"segments": 3}, Transform3D(Basis(), Vector3(40, 0, 0))).ok)
	var gone = null
	for generator_id in generators.generators:
		if generator_id != kept.generator_id:
			gone = generators.generators[generator_id]
	var before: Dictionary = root.capture_state()
	assert_true(generators.detach(gone.generator_id))
	var after: Dictionary = root.capture_state()
	root.restore_state(before)
	root.restore_state(after)
	for brush_id in kept.brush_ids:
		var piece = brushes.find_brush_by_id(str(brush_id))
		assert_eq(str(piece.get_meta("hf_generator_id", "")), kept.generator_id, "still a piece")
	for brush_id in gone.brush_ids:
		assert_false(brushes.find_brush_by_id(str(brush_id)).has_meta("hf_generator_id"))
	assert_true(generators.regenerate(kept.generator_id, _arch({"segments": 5})).ok)
	assert_eq(_brush_count(), 5 + 3, "an update still finds its pieces and only them")


func test_a_tag_on_a_brush_the_record_does_not_list_goes_on_restore():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var stranger = brushes.create_brush_from_info(
		{"size": Vector3(2, 2, 2), "center": Vector3(30, 1, 0), "brush_id": "stranger"}
	)
	stranger.set_meta("hf_generator_id", record.generator_id)
	generators.restore(generators.capture())
	assert_false(stranger.has_meta("hf_generator_id"), "not one of its pieces")
	for brush_id in record.brush_ids:
		assert_true(brushes.find_brush_by_id(str(brush_id)).has_meta("hf_generator_id"))


func test_detaching_something_that_is_not_a_generator_returns_false():
	assert_false(generators.detach("gen_nothing"))


func test_removing_deletes_the_brushes_and_the_record():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	assert_true(generators.remove(record.generator_id))
	assert_eq(generators.generators.size(), 0)
	assert_eq(_brush_count(), 0)


func test_removing_something_that_is_not_a_generator_returns_false():
	assert_false(generators.remove("gen_nothing"))


# ===========================================================================
# Persistence
# ===========================================================================


func test_records_survive_a_capture_and_restore():
	assert_true(_create({"segments": 5, "radius": 175.0}).ok)
	var captured: Array = generators.capture()
	assert_eq(captured.size(), 1)
	generators.clear()
	assert_eq(generators.generators.size(), 0)
	generators.restore(captured)
	var record = _only_record()
	assert_not_null(record)
	assert_eq(record.type, "arch")
	assert_eq(record.brush_ids.size(), 5)
	assert_almost_eq(float(record.settings["radius"]), 175.0, 0.001)


func test_restoring_puts_the_meta_back_on_the_brushes():
	assert_true(_create({"segments": 4}).ok)
	var captured: Array = generators.capture()
	var record = _only_record()
	for brush_id in record.brush_ids:
		brushes.find_brush_by_id(str(brush_id)).remove_meta("hf_generator_id")
	generators.clear()
	generators.restore(captured)
	for brush_id in _only_record().brush_ids:
		var brush = brushes.find_brush_by_id(str(brush_id))
		assert_true(brush.has_meta("hf_generator_id"), "a restored piece must know its generator")


func test_a_record_round_trips_through_a_dictionary():
	var record = HFGeneratorScript.new()
	record.type = "arch"
	record.settings = {"radius": 64.0, "segments": 7}
	record.placement = Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(1, 2, 3))
	record.brush_ids = PackedStringArray(["a", "b"])
	var restored = HFGeneratorScript.from_dict(record.to_dict())
	assert_eq(restored.generator_id, record.generator_id)
	assert_eq(restored.type, "arch")
	assert_eq(int(restored.settings["segments"]), 7)
	assert_eq(Array(restored.brush_ids), ["a", "b"])
	assert_true(restored.placement.is_equal_approx(record.placement))


func test_a_dictionary_missing_fields_loads_with_defaults():
	var restored = HFGeneratorScript.from_dict({"type": "arch"})
	assert_eq(restored.type, "arch")
	assert_eq(restored.brush_ids.size(), 0)
	assert_true(restored.placement.is_equal_approx(Transform3D.IDENTITY))
	assert_true(restored.settings.is_empty())


func test_a_record_without_a_type_is_dropped_on_restore():
	generators.restore([{"generator_id": "gen_x", "brush_ids": []}])
	assert_eq(generators.generators.size(), 0, "a record that names no builder is useless")


func test_restore_tolerates_rubbish():
	generators.restore([null, 5, "nonsense", {}])
	assert_eq(generators.generators.size(), 0)


# ===========================================================================
# The type table
# ===========================================================================


func test_the_known_types_are_buildable():
	for type in HFGeneratorSystemScript.known_types():
		var settings: Dictionary = HFGeneratorSystemScript.default_settings(type)
		assert_false(settings.is_empty(), "%s must have defaults" % type)
		assert_true(
			HFGeneratorSystemScript.validate(type, settings).ok, "%s defaults must be valid" % type
		)
		assert_gt(
			HFGeneratorSystemScript.build_faces(type, settings).size(),
			0,
			"%s defaults must build something" % type
		)


func test_an_unknown_type_has_no_defaults_and_builds_nothing():
	assert_true(HFGeneratorSystemScript.default_settings("gazebo").is_empty())
	assert_eq(HFGeneratorSystemScript.build_faces("gazebo", {}).size(), 0)
	assert_false(HFGeneratorSystemScript.validate("gazebo", {}).ok)


# ===========================================================================
# Stale records must stay harmless
# ===========================================================================


func test_a_rebuild_does_not_delete_a_brush_it_no_longer_owns():
	# Brush ids are reissued as the counter moves, so a stale entry in one record
	# can name a brush that now belongs to something else. The meta on the brush is
	# the authority, not the list.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var stranger = DraftBrush.new()
	stranger.brush_id = "stranger"
	stranger.set_meta("brush_id", "stranger")
	root.draft_brushes_node.add_child(stranger)
	brushes._register_brush_id("stranger", stranger)
	record.brush_ids.append("stranger")

	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	assert_not_null(
		brushes.find_brush_by_id("stranger"),
		"a brush that belongs to nobody must survive a rebuild"
	)


func test_removing_does_not_delete_a_brush_it_no_longer_owns():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var stranger = DraftBrush.new()
	stranger.brush_id = "stranger"
	stranger.set_meta("brush_id", "stranger")
	root.draft_brushes_node.add_child(stranger)
	brushes._register_brush_id("stranger", stranger)
	record.brush_ids.append("stranger")

	assert_true(generators.remove(record.generator_id))
	assert_not_null(brushes.find_brush_by_id("stranger"), "only its own pieces may be removed")


func test_a_structure_whose_pieces_were_all_deleted_can_still_be_rebuilt():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	for brush_id in Array(record.brush_ids):
		brushes.delete_brush_by_id(str(brush_id))
	assert_eq(_brush_count(), 0)
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 4})).ok,
		"the record outlives the geometry, which is the point of it"
	)
	assert_eq(_brush_count(), 4)


# ===========================================================================
# Every type, not only the arch
# ===========================================================================


func test_every_known_type_creates_a_structure_of_its_own():
	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		var result = generators.create(
			name, HFGeneratorSystemScript.default_settings(name), Transform3D.IDENTITY
		)
		assert_true(result.ok, "%s could not be created: %s" % [name, result.message])
	assert_eq(
		generators.generators.size(),
		HFGeneratorSystemScript.known_types().size(),
		"each type is its own structure"
	)


func test_a_piece_of_any_type_finds_its_own_generator():
	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		assert_true(
			(
				generators
				. create(name, HFGeneratorSystemScript.default_settings(name), Transform3D.IDENTITY)
				. ok
			)
		)
	for generator_id in generators.generators:
		var record = generators.generators[generator_id]
		for brush_id in record.brush_ids:
			var found = generators.generator_for_brush(str(brush_id))
			assert_eq(
				found.generator_id, record.generator_id, "a piece pointed at the wrong structure"
			)


func test_a_structure_of_any_type_rebuilds_from_new_settings():
	var cases := {
		"stairs": {"steps": 5},
		"spiral_stairs": {"steps": 5},
		"dome": {"rings": 2, "segments": 6},
	}
	for type in cases:
		var name := str(type)
		var settings: Dictionary = HFGeneratorSystemScript.default_settings(name)
		assert_true(generators.create(name, settings, Transform3D.IDENTITY).ok)
		var record = _record_of_type(name)
		var before: int = record.brush_ids.size()
		var changed: Dictionary = settings.duplicate()
		for key in cases[type]:
			changed[key] = cases[type][key]
		assert_true(
			generators.regenerate(record.generator_id, changed).ok, "%s would not rebuild" % name
		)
		assert_ne(record.brush_ids.size(), before, "%s ignored its new settings" % name)


func _record_of_type(type: String):
	for generator_id in generators.generators:
		if generators.generators[generator_id].type == type:
			return generators.generators[generator_id]
	return null


# ===========================================================================
# What has happened to a structure since it was made
# ===========================================================================


func test_creating_remembers_what_each_piece_was():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	assert_eq(record.brush_signatures.size(), 4, "every piece is remembered")
	for brush_id in record.brush_ids:
		var signature: Dictionary = record.brush_signatures[str(brush_id)]
		assert_true(str(signature.get("geometry", "")) != "", "a piece has no shape recorded")


func test_an_untouched_structure_has_moved_nowhere_and_been_edited_nowhere():
	assert_true(_create({"segments": 6}).ok)
	var record = _only_record()
	assert_eq(generators.relocation_delta(record.generator_id), Vector3.ZERO)
	assert_eq(generators.edited_piece_count(record.generator_id), 0)


func test_dragging_the_whole_structure_reads_as_a_move_and_not_as_editing():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var delta := Vector3(64.0, 0.0, -32.0)
	for brush_id in record.brush_ids:
		brushes.find_brush_by_id(str(brush_id)).global_position += delta
	assert_almost_eq(generators.relocation_delta(record.generator_id).x, delta.x, 0.001)
	assert_almost_eq(generators.relocation_delta(record.generator_id).z, delta.z, 0.001)
	assert_eq(
		generators.edited_piece_count(record.generator_id),
		0,
		"moving a structure is not editing its pieces"
	)


func test_a_structure_that_was_moved_rebuilds_where_it_now_is():
	# The defect this exists for: create an arch on the origin, drag it into a
	# doorway, widen it, and watch it jump back to the origin.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var delta := Vector3(100.0, 50.0, 0.0)
	for brush_id in record.brush_ids:
		brushes.find_brush_by_id(str(brush_id)).global_position += delta
	var moved_centre := _structure_centre(record)

	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	assert_almost_eq(record.placement.origin.x, delta.x, 0.01, "the record forgot where it went")
	assert_almost_eq(_structure_centre(record).x, moved_centre.x, 1.0)
	assert_almost_eq(_structure_centre(record).y, moved_centre.y, 1.0)


func test_pieces_moved_apart_are_edits_rather_than_a_relocation():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var i := 0
	for brush_id in record.brush_ids:
		brushes.find_brush_by_id(str(brush_id)).global_position += Vector3(10.0 * float(i), 0, 0)
		i += 1
	assert_eq(
		generators.relocation_delta(record.generator_id),
		Vector3.ZERO,
		"pieces that disagree were not moved together"
	)
	assert_gt(
		generators.edited_piece_count(record.generator_id), 0, "moving one piece is a hand edit"
	)


func test_a_reshaped_piece_is_counted_as_edited():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var victim = brushes.find_brush_by_id(str(record.brush_ids[0]))
	victim.size = victim.size * 2.0
	assert_eq(generators.edited_piece_count(record.generator_id), 1)
	assert_eq(Array(generators.edited_brush_ids(record.generator_id)), [str(record.brush_ids[0])])


func test_a_turned_piece_is_counted_as_edited():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var victim = brushes.find_brush_by_id(str(record.brush_ids[1]))
	victim.rotate_y(0.5)
	assert_eq(generators.edited_piece_count(record.generator_id), 1)


func test_a_rebuild_clears_the_edit_count_because_the_edits_are_gone():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	brushes.find_brush_by_id(str(record.brush_ids[0])).size += Vector3(8, 8, 8)
	assert_eq(generators.edited_piece_count(record.generator_id), 1)
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	assert_eq(
		generators.edited_piece_count(record.generator_id),
		0,
		"the pieces are the generated ones again"
	)


func test_a_deleted_piece_is_counted_as_an_edit():
	# A rebuild puts it back, so the section has to say so first. It was passed over
	# as missing rather than changed, and a gap cut on purpose filled in unannounced.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[0]))
	assert_eq(Array(generators.edited_brush_ids(record.generator_id)), [str(record.brush_ids[0])])


func test_signatures_survive_the_save_format():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	brushes.find_brush_by_id(str(record.brush_ids[0])).size += Vector3(8, 8, 8)
	var edited_before: int = generators.edited_piece_count(record.generator_id)

	var captured: Array = generators.capture()
	generators.restore(captured)
	var restored = _only_record()
	assert_eq(restored.brush_signatures.size(), 4, "a reopened level must still know what it built")
	assert_eq(
		generators.edited_piece_count(restored.generator_id),
		edited_before,
		"the same pieces must still read as edited after a reload"
	)


func test_a_record_saved_before_signatures_existed_still_loads():
	var older := {
		"generator_id": "gen_old",
		"type": "arch",
		"settings": _arch(),
		"brush_ids": ["b1"],
	}
	generators.restore([older])
	var record = generators.generators["gen_old"]
	assert_eq(record.brush_signatures.size(), 0)
	assert_eq(
		generators.relocation_delta("gen_old"),
		Vector3.ZERO,
		"nothing recorded means nothing known, not a move"
	)
	assert_eq(generators.edited_piece_count("gen_old"), 0)


func test_a_stranger_brush_in_the_record_is_ignored_by_both_questions():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var stranger = DraftBrush.new()
	stranger.brush_id = "stranger"
	stranger.set_meta("brush_id", "stranger")
	root.draft_brushes_node.add_child(stranger)
	brushes._register_brush_id("stranger", stranger)
	stranger.global_position = Vector3(999, 999, 999)
	record.brush_ids.append("stranger")
	record.brush_signatures["stranger"] = {"origin": Vector3.ZERO, "geometry": "nonsense"}

	assert_eq(
		generators.relocation_delta(record.generator_id),
		Vector3.ZERO,
		"a brush that is not ours cannot say where our structure went"
	)
	assert_eq(generators.edited_piece_count(record.generator_id), 0)


# ===========================================================================
# An Update that would change nothing (#1368)
# ===========================================================================


## Whether an Update of the one arch with these settings, over the defaults,
## would change nothing.
func _nothing_to_update(overrides: Dictionary = {"segments": 4}) -> bool:
	return generators.update_changes_nothing(_only_record().generator_id, _arch(overrides))


func test_the_settings_it_has_on_untouched_pieces_change_nothing():
	assert_true(_create({"segments": 4}).ok)
	assert_true(_nothing_to_update(), "a rebuild would put back the same pieces")


func test_a_different_setting_is_a_change():
	assert_true(_create({"segments": 4}).ok)
	assert_false(_nothing_to_update({"segments": 5}))
	assert_false(_nothing_to_update({"segments": 4, "radius": 150.0}))


func test_a_whole_number_handed_back_as_a_float_is_the_same_setting():
	# A SpinBox gives every value back as a float, and a level read from JSON
	# stores every number as one.
	assert_true(_create({"segments": 4}).ok)
	assert_true(_nothing_to_update({"segments": 4.0}))


func test_a_float_a_rounding_away_is_the_same_setting():
	# A SpinBox snaps what it is given to its step, and the arithmetic of that can
	# hand back a value one rounding away from the one the record holds.
	assert_true(_create({"segments": 4}).ok)
	var radius := float(_only_record().settings["radius"])
	assert_true(_nothing_to_update({"segments": 4, "radius": radius + 1e-9}))


func test_a_setting_an_older_record_lacks_reads_as_its_default():
	# A record saved before a field existed has no value for it, and one with a
	# stray key has a value no builder reads. Both are read as the builder reads
	# them, so the missing field is its default and the stray one is nothing.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	record.settings.erase("depth")
	record.settings["retired"] = 3.0
	assert_true(_nothing_to_update(), "the default it was built with")
	var deeper := float(_arch()["depth"]) + 16.0
	assert_false(_nothing_to_update({"segments": 4, "depth": deeper}), "a new depth is a change")


func test_a_record_through_the_save_format_still_has_nothing_to_update():
	assert_true(_create({"segments": 4}).ok)
	generators.restore(JSON.parse_string(JSON.stringify(generators.capture())))
	assert_true(_nothing_to_update(), "a reopened level is no reason to rebuild")


func test_a_structure_moved_as_a_whole_has_nothing_to_update():
	# A rebuild puts it back exactly where it stands, so the move is no reason to.
	assert_true(_create({"segments": 4}).ok)
	_move_whole_structure(_only_record(), Transform3D(Basis.IDENTITY, Vector3(96, 0, -40)))
	assert_true(_nothing_to_update())
	_move_whole_structure(_only_record(), _turn(90.0))
	assert_true(_nothing_to_update(), "nor is a turn")


func test_paint_is_no_reason_to_rebuild():
	assert_true(_create({"segments": 4}).ok)
	while root.get_materials().size() < 2:
		root.add_material_to_palette(StandardMaterial3D.new())
	root.assign_material_to_faces_by_id(str(_only_record().brush_ids[0]), [0], 1)
	assert_true(_nothing_to_update(), "a rebuild would carry the paint, so it changes nothing")


func test_a_piece_moved_on_its_own_is_a_change():
	assert_true(_create({"segments": 4}).ok)
	brushes.find_brush_by_id(str(_only_record().brush_ids[1])).global_position += Vector3(0, 0, 8)
	assert_false(_nothing_to_update(), "a rebuild puts it back in the row")


func test_a_reshaped_piece_is_a_change():
	assert_true(_create({"segments": 4}).ok)
	var piece = brushes.find_brush_by_id(str(_only_record().brush_ids[0]))
	piece.size = piece.size * 2.0
	assert_false(_nothing_to_update())


func test_a_deleted_piece_is_a_change():
	assert_true(_create({"segments": 4}).ok)
	brushes.delete_brush_by_id(str(_only_record().brush_ids[2]))
	assert_false(_nothing_to_update(), "a rebuild puts the piece back")


func test_a_piece_that_is_no_longer_ours_is_a_change():
	# The id is there and the brush is there, but it no longer says it is this
	# structure's, so a rebuild leaves it standing and puts a piece in its place.
	assert_true(_create({"segments": 4}).ok)
	brushes.find_brush_by_id(str(_only_record().brush_ids[0])).remove_meta("hf_generator_id")
	assert_eq(
		generators.edited_piece_count(_only_record().generator_id), 0, "not counted as edited"
	)
	assert_false(_nothing_to_update(), "but not vouched for either")


func test_a_record_with_no_signatures_cannot_say_nothing_changed():
	assert_true(_create({"segments": 4}).ok)
	_only_record().brush_signatures.clear()
	assert_eq(generators.edited_piece_count(_only_record().generator_id), 0, "nothing known")
	assert_false(_nothing_to_update(), "so an Update rebuilds, as it always did")


func test_a_structure_that_is_not_there_has_something_to_update():
	assert_false(generators.update_changes_nothing("gen_nothing", _arch()))
	assert_false(root.generator_update_changes_nothing("gen_nothing", _arch()))


# ===========================================================================
# Turning a structure, rather than only sliding it
# ===========================================================================


## Apply one rigid move to every piece, the way the Rotate command does.
func _move_whole_structure(record, move: Transform3D) -> void:
	for brush_id in record.brush_ids:
		var brush = brushes.find_brush_by_id(str(brush_id))
		if brush:
			brush.global_transform = move * brush.global_transform


func _turn(degrees: float, pivot: Vector3 = Vector3.ZERO) -> Transform3D:
	var rotation := Basis(Vector3.UP, deg_to_rad(degrees))
	return Transform3D(rotation, pivot - rotation * pivot)


func test_turning_the_whole_structure_reads_as_a_move_and_not_as_editing():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var move := _turn(90.0)

	_move_whole_structure(record, move)

	assert_eq(
		generators.edited_piece_count(record.generator_id),
		0,
		"turning a structure is not editing its pieces"
	)
	var recovered: Transform3D = generators.relocation_transform(record.generator_id)
	assert_almost_eq(recovered.basis.x, move.basis.x, Vector3.ONE * 0.001)
	assert_almost_eq(recovered.basis.z, move.basis.z, Vector3.ONE * 0.001)


func test_a_structure_that_was_turned_rebuilds_turned():
	# The defect this exists for: build an arch, turn it into the wall it belongs
	# in, widen it, and watch it square itself back up.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var move := _turn(90.0, Vector3(0.0, 0.0, 128.0))
	_move_whole_structure(record, move)
	var turned_centre := _structure_centre(record)

	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)

	assert_almost_eq(record.placement.basis.x, move.basis.x, Vector3.ONE * 0.01)
	assert_almost_eq(_structure_centre(record), turned_centre, Vector3.ONE * 1.0)
	assert_eq(
		generators.edited_piece_count(record.generator_id),
		0,
		"and the rebuilt pieces are the generated ones again"
	)


func test_a_turn_and_a_slide_together_are_still_one_move():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var move := _turn(45.0)
	move.origin += Vector3(80.0, 16.0, -24.0)

	_move_whole_structure(record, move)

	assert_eq(generators.edited_piece_count(record.generator_id), 0)
	assert_almost_eq(
		generators.relocation_transform(record.generator_id).origin, move.origin, Vector3.ONE * 0.01
	)


func test_pieces_turned_on_their_own_are_edits_rather_than_a_relocation():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	# Each piece about its own centre, which is four different moves.
	for brush_id in record.brush_ids:
		brushes.find_brush_by_id(str(brush_id)).rotate_y(0.4)

	assert_eq(
		generators.relocation_transform(record.generator_id),
		Transform3D.IDENTITY,
		"pieces that disagree were not turned together"
	)
	assert_eq(generators.edited_piece_count(record.generator_id), 4)


func test_a_mirrored_structure_is_not_treated_as_a_relocation():
	# Rebuilding through a negative-determinant basis would invert the winding of
	# every face in the structure and not look wrong until the bake.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var mirror := Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO)

	_move_whole_structure(record, mirror)

	assert_eq(generators.relocation_transform(record.generator_id), Transform3D.IDENTITY)
	assert_gt(
		generators.edited_piece_count(record.generator_id), 0, "a mirror has to be visible as one"
	)


func test_a_squashed_structure_is_not_treated_as_a_relocation():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var squash := Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), Vector3.ZERO)

	_move_whole_structure(record, squash)

	assert_eq(generators.relocation_transform(record.generator_id), Transform3D.IDENTITY)


func test_a_turn_survives_the_save_format():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var move := _turn(90.0)
	_move_whole_structure(record, move)

	generators.restore(generators.capture())

	var restored = _only_record()
	assert_eq(
		generators.edited_piece_count(restored.generator_id),
		0,
		"a reopened level must still know the structure was turned, not edited"
	)
	assert_almost_eq(
		generators.relocation_transform(restored.generator_id).basis.x,
		move.basis.x,
		Vector3.ONE * 0.001
	)


func test_a_record_written_before_piece_bases_existed_still_recovers_a_turn():
	# Older records recorded where each piece was put but not how it was turned.
	# The placement's own basis is the right answer for a missing one, because it
	# is what every piece the generator built was given.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	for brush_id in record.brush_signatures:
		record.brush_signatures[brush_id].erase("basis")
	var move := _turn(90.0)

	_move_whole_structure(record, move)

	assert_eq(generators.edited_piece_count(record.generator_id), 0)
	assert_almost_eq(
		generators.relocation_transform(record.generator_id).basis.x,
		move.basis.x,
		Vector3.ONE * 0.001
	)


# ===========================================================================
# Deciding where the structure went when the pieces do not all agree
# ===========================================================================


func test_one_stray_piece_does_not_overrule_the_eleven_that_agree():
	# The defect this exists for: drag a twelve-piece arch across the level,
	# nudge one brush, and the whole structure reads as hand-edited and jumps
	# back to the origin the moment you press Update.
	assert_true(_create({"segments": 12}).ok)
	var record = _only_record()
	var far := Vector3(512.0, 0.0, 0.0)
	_move_whole_structure(record, Transform3D(Basis.IDENTITY, far))
	brushes.find_brush_by_id(str(record.brush_ids[0])).global_position += Vector3(1.0, 0.0, 0.0)

	assert_almost_eq(
		generators.relocation_transform(record.generator_id).origin,
		far,
		Vector3.ONE * 0.01,
		"eleven pieces agreeing is where the structure is"
	)
	assert_eq(
		generators.edited_piece_count(record.generator_id),
		1,
		"and the one that disagrees is the only hand edit"
	)
	assert_false(generators.pieces_disagree_about_placement(record.generator_id))


func test_the_structure_stays_put_when_it_is_rebuilt_around_a_stray_piece():
	assert_true(_create({"segments": 12}).ok)
	var record = _only_record()
	_move_whole_structure(record, Transform3D(Basis.IDENTITY, Vector3(512.0, 0.0, 0.0)))
	brushes.find_brush_by_id(str(record.brush_ids[0])).global_position += Vector3(1.0, 0.0, 0.0)

	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 12})).ok)

	assert_almost_eq(
		_structure_centre(record).x, 512.0, 1.0, "a rebuild must not carry it back to the origin"
	)


func test_a_bare_majority_is_enough_and_a_tie_is_not():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	# Two pieces one way, two the other: nothing to call the structure's move.
	for index in 2:
		brushes.find_brush_by_id(str(record.brush_ids[index])).global_position += Vector3(64, 0, 0)
	for index in range(2, 4):
		brushes.find_brush_by_id(str(record.brush_ids[index])).global_position += Vector3(0, 0, 64)

	assert_eq(generators.relocation_transform(record.generator_id), Transform3D.IDENTITY)
	assert_true(
		generators.pieces_disagree_about_placement(record.generator_id),
		"a structure nobody can locate has to say so"
	)


func test_three_of_four_agreeing_carries_the_structure():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	var move := Vector3(64.0, 0.0, 0.0)
	for index in 3:
		brushes.find_brush_by_id(str(record.brush_ids[index])).global_position += move

	assert_almost_eq(
		generators.relocation_transform(record.generator_id).origin, move, Vector3.ONE * 0.01
	)
	assert_eq(generators.edited_piece_count(record.generator_id), 1, "the one left behind")


func test_a_mirror_cannot_out_vote_its_own_refusal():
	# Every piece agrees, and what they agree on still must not be applied.
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()

	_move_whole_structure(record, Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO))

	assert_eq(generators.relocation_transform(record.generator_id), Transform3D.IDENTITY)
	assert_true(
		generators.pieces_disagree_about_placement(record.generator_id),
		"a mirrored structure is one a rebuild cannot place"
	)


func test_an_untouched_structure_is_not_reported_as_lost():
	assert_true(_create({"segments": 4}).ok)
	assert_false(generators.pieces_disagree_about_placement(_only_record().generator_id))


func test_a_structure_with_one_piece_left_still_says_where_it_is():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	for index in range(1, 4):
		brushes.delete_brush_by_id(str(record.brush_ids[index]))
	brushes.find_brush_by_id(str(record.brush_ids[0])).global_position += Vector3(32, 0, 0)

	assert_almost_eq(
		generators.relocation_transform(record.generator_id).origin,
		Vector3(32, 0, 0),
		Vector3.ONE * 0.01,
		"the only piece there is speaks for the structure"
	)


func _structure_centre(record) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for brush_id in record.brush_ids:
		var brush = brushes.find_brush_by_id(str(brush_id))
		if brush:
			total += brush.global_position
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


# ===========================================================================
# Every generator refuses a setting it cannot build (#336, #337, #338)
# ===========================================================================


func test_every_generator_refuses_a_non_finite_setting():
	# A NaN fails `radius <= 0.0` the way it fails every comparison, so it used
	# to pass every check a builder made and build a structure of NaN brushes.
	var checked := 0
	for type in HFGeneratorSystemScript.known_types():
		for field in HFGeneratorSystemScript.settings_schema(type):
			if field["type"] == "bool" or field["type"] == "enum":
				continue
			for value in [NAN, INF, -INF]:
				var settings := {}
				settings[str(field["key"])] = value
				var result = HFGeneratorSystemScript.validate(type, settings)
				assert_false(result.ok, "%s should refuse %s = %s" % [type, field["key"], value])
				checked += 1
	assert_gt(checked, 0, "there are generator settings to check")


func test_every_generator_refuses_a_setting_past_its_schema_maximum():
	# The schema's max was the dock's SpinBox and nothing else, so a regenerate
	# from a file, an undo replay or a script walked straight past it.
	for type in HFGeneratorSystemScript.known_types():
		for field in HFGeneratorSystemScript.settings_schema(type):
			if not field.has("max") or field["type"] == "bool" or field["type"] == "enum":
				continue
			var settings := {}
			settings[str(field["key"])] = float(field["max"]) * 1000.0
			var result = HFGeneratorSystemScript.validate(type, settings)
			assert_false(result.ok, "%s should refuse a huge %s" % [type, field["key"]])


func test_an_arch_of_129000_segments_is_refused():
	var result = HFGeneratorSystemScript.validate("arch", {"segments": 129000})
	assert_false(result.ok, "129000 segments is 129000 brushes")
	assert_false(HFGeneratorSystemScript.can_build("arch", {"segments": 129000}).ok)


func test_every_generator_still_builds_at_its_defaults():
	for type in HFGeneratorSystemScript.known_types():
		var defaults = HFGeneratorSystemScript.default_settings(type)
		assert_true(HFGeneratorSystemScript.validate(type, defaults).ok, "%s defaults" % type)


# ===========================================================================
# Every field of every builder, at both bounds (#518, #519)
# ===========================================================================


## `check_ranges()` is the only guard on the paths that never saw the dock: a
## regenerate from a `.hflevel`, an undo replay, a script. Written as a walk over
## the schemas rather than a list of fields, so a builder added later is covered
## the day it is added.
func test_every_numeric_field_refuses_one_step_outside_each_bound():
	var checked := 0
	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		for entry in HFGeneratorSystemScript.settings_schema(name):
			if not (entry is Dictionary) or not entry.has("key"):
				continue
			var kind := str(entry.get("type", "float"))
			if kind != "float" and kind != "int":
				continue
			var key := str(entry["key"])
			var step: float = 1.0 if kind == "int" else 0.5
			if entry.has("min"):
				var below = HFGeneratorSystemScript.default_settings(name)
				below[key] = float(entry["min"]) - step
				assert_false(
					HFGeneratorSystemScript.validate(name, below).ok,
					"%s.%s accepted %s, below its min of %s" % [name, key, below[key], entry["min"]]
				)
				checked += 1
			if entry.has("max"):
				var above = HFGeneratorSystemScript.default_settings(name)
				above[key] = float(entry["max"]) + step
				assert_false(
					HFGeneratorSystemScript.validate(name, above).ok,
					"%s.%s accepted %s, above its max of %s" % [name, key, above[key], entry["max"]]
				)
				checked += 1
	assert_gt(checked, 0, "the walk found no bounded fields, which means it found nothing")


func test_every_enum_field_refuses_an_index_its_options_do_not_have():
	var checked := 0
	for type in HFGeneratorSystemScript.known_types():
		var name := str(type)
		for entry in HFGeneratorSystemScript.settings_schema(name):
			if not (entry is Dictionary) or str(entry.get("type", "")) != "enum":
				continue
			var key := str(entry["key"])
			var options: Array = Array(entry.get("options", []))
			var past = HFGeneratorSystemScript.default_settings(name)
			past[key] = options.size()
			assert_false(
				HFGeneratorSystemScript.validate(name, past).ok,
				"%s.%s accepted index %d of %d options" % [name, key, past[key], options.size()]
			)
			var negative = HFGeneratorSystemScript.default_settings(name)
			negative[key] = -1
			assert_false(
				HFGeneratorSystemScript.validate(name, negative).ok,
				"%s.%s accepted a negative index" % [name, key]
			)
			for index in options.size():
				var inside = HFGeneratorSystemScript.default_settings(name)
				inside[key] = index
				assert_true(
					HFGeneratorSystemScript.validate(name, inside).ok,
					"%s.%s refused index %d, which is one of its own options" % [name, key, index]
				)
			checked += 1
	assert_gt(checked, 0, "no enum field was found to check")


# ===========================================================================
# An Update keeps the brush entity a structure was tied to (#1163)
# ===========================================================================


func _pieces() -> Array:
	return Array(_only_record().brush_ids).map(
		func(brush_id): return brushes.find_brush_by_id(str(brush_id))
	)


func _tie_whole(entity_class: String, entity_name: String = "") -> void:
	root.tie_brushes_to_entity(Array(_only_record().brush_ids), entity_class, entity_name)


func test_an_update_keeps_a_tied_named_wired_arch_what_it_was():
	# It came back as plain geometry, so every wire aimed at it aimed at nothing.
	assert_true(_create({"segments": 4, "radius": 100.0}).ok)
	_tie_whole("func_wall", "arch_wall")
	root.add_entity_output(_pieces()[0], "OnUser1", "lamp", "TurnOn")
	var tie := str(_pieces()[0].get_meta("brush_entity_group", ""))

	var record = _only_record()
	assert_true(
		generators.regenerate(record.generator_id, _arch({"segments": 4, "radius": 150.0})).ok
	)
	for piece in _pieces():
		assert_eq(str(piece.get_meta("brush_entity_class", "")), "func_wall", str(piece.name))
		assert_eq(str(piece.get_meta("entity_name", "")), "arch_wall")
		assert_eq(str(piece.get_meta("brush_entity_group", "")), tie, "one entity still")
	assert_eq(root.get_entity_outputs(_pieces()[0]).size(), 1, "and wired")
	assert_eq(root.find_entities_by_name("arch_wall").size(), 4)


func test_an_arch_tied_whole_that_gains_pieces_keeps_them_all_in_it():
	assert_true(_create({"segments": 4}).ok)
	_tie_whole("func_detail")
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 6})).ok)
	assert_eq(_pieces().size(), 6)
	assert_eq(brushes.brushes_of_entity(_pieces()[5]).size(), 6, "the new pieces joined it")


func test_a_partly_tied_arch_keeps_each_piece_as_it_was():
	assert_true(_create({"segments": 4}).ok)
	root.tie_brushes_to_entity(Array(_only_record().brush_ids).slice(0, 2), "func_wall")
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 6})).ok)
	var classes: Array = _pieces().map(func(p): return str(p.get_meta("brush_entity_class", "")))
	assert_eq(classes, ["func_wall", "func_wall", "", "", "", ""], "by piece, and no more")


func test_an_untied_arch_still_updates_to_plain_geometry():
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 5})).ok)
	for piece in _pieces():
		assert_false(piece.has_meta("brush_entity_class"), str(piece.name))


func test_an_update_keeps_each_piece_its_node_name():
	# The Objects tab offers an unnamed brush entity by its pieces' node names, and
	# every Update named the new pieces on from the old, so a wire aimed at one
	# aimed at nothing afterwards.
	assert_true(_create({"segments": 4}).ok)
	_tie_whole("func_wall")
	var names: Array = _pieces().map(func(piece): return str(piece.name))
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 5})).ok)
	var after: Array = _pieces().map(func(piece): return str(piece.name))
	assert_eq(after.slice(0, 4), names, "the old pieces' names, in order")
	assert_eq(root.find_entities_by_name(names[0]).size(), 1, "and still an address")


func test_an_update_gives_back_a_name_a_new_piece_took_first():
	# Every piece is made before any is named back, and a new piece is named for its
	# id, so a piece called what a later new piece would be called lost its name to
	# it: Godot numbered it on. A prefab rebuild swaps it back (#1178), and an Update
	# now names its pieces back the same way (#1221).
	assert_true(_create({"segments": 4}).ok)
	var label := str(_pieces()[1].name).get_slice("_", 0)
	_pieces()[0].name = "%s_%d" % [label, root._brush_id_counter + 2]
	var names: Array = _pieces().map(func(piece): return str(piece.name))
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	assert_eq(_pieces().map(func(piece): return str(piece.name)), names)


func test_an_update_takes_nothing_from_a_brush_that_is_not_its_own():
	# A stale id in the record can name a brush that now belongs to something else.
	# An Update leaves that brush standing, and it used to read the piece's name,
	# entity and visgroups off it as well, so the piece made in its place joined a
	# door it had nothing to do with (#1221).
	assert_true(_create({"segments": 4}).ok)
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[1]))
	var door: Node = brushes.create_brush_from_info(
		{"size": Vector3(8, 8, 8), "center": Vector3(500, 0, 0)}
	)
	root.tie_brushes_to_entity([str(door.brush_id)], "func_door", "gate")
	root.add_selection_to_visgroup("Doors", [door])
	var ids: PackedStringArray = record.brush_ids
	ids[1] = str(door.brush_id)
	record.brush_ids = ids

	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	var put_back: Node = _pieces()[1]
	assert_eq(str(put_back.get_meta("brush_entity_class", "")), "", "no part of the door")
	assert_eq(Array(put_back.get_meta("visgroups", PackedStringArray())), [], "nor in its visgroup")
	assert_eq(root.find_entities_by_name("gate"), [door], "the door is still the one brush")


func _classes() -> Array:
	return _pieces().map(func(p): return str(p.get_meta("brush_entity_class", "")))


func test_a_deleted_piece_an_update_puts_back_rejoins_the_entity():
	# The deleted piece's capture is empty, so it came back plain geometry: a gap
	# in the wall that ignored Disable and baked into the world mesh (#1237).
	assert_true(_create({"segments": 4}).ok)
	_tie_whole("func_wall", "arch_wall")
	var tie := str(_pieces()[0].get_meta("brush_entity_group", ""))
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[2]))
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	assert_eq(_classes(), ["func_wall", "func_wall", "func_wall", "func_wall"])
	var put_back: Node = _pieces()[2]
	assert_eq(str(put_back.get_meta("entity_name", "")), "arch_wall")
	assert_eq(str(put_back.get_meta("brush_entity_group", "")), tie, "the same entity")
	assert_eq(root.find_entities_by_name("arch_wall").size(), 4)


func test_pieces_added_after_a_deletion_join_the_entity_too():
	# The deleted piece's empty capture vetoed the vote for what every piece shared.
	assert_true(_create({"segments": 4}).ok)
	_tie_whole("func_detail")
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[1]))
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 6})).ok)
	assert_eq(_pieces().size(), 6)
	assert_eq(brushes.brushes_of_entity(_pieces()[5]).size(), 6, "one entity of six")


func test_an_arch_tied_to_different_entities_gives_new_pieces_none():
	assert_true(_create({"segments": 4}).ok)
	var ids: Array = Array(_only_record().brush_ids)
	root.tie_brushes_to_entity(ids.slice(0, 2), "func_wall", "left")
	root.tie_brushes_to_entity(ids.slice(2, 4), "func_wall", "right")
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[3]))
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 6})).ok)
	assert_eq(_classes(), ["func_wall", "func_wall", "func_wall", "", "", ""], "no side guessed")
	assert_eq(root.find_entities_by_name("left").size(), 2)
	assert_eq(root.find_entities_by_name("right").size(), 1)


func test_undoing_an_update_that_put_a_piece_back_restores_the_gap():
	assert_true(_create({"segments": 4}).ok)
	_tie_whole("func_wall", "arch_wall")
	var record = _only_record()
	var ids: Array = Array(record.brush_ids)
	var gone := str(ids[2])
	brushes.delete_brush_by_id(gone)
	var before: Dictionary = root.capture_state()
	assert_true(root.regenerate_generator(record.generator_id, _arch({"segments": 4})).ok)
	assert_eq(root.find_entities_by_name("arch_wall").size(), 4)

	root.restore_state(before)
	var restored = _only_record()
	assert_eq(Array(restored.brush_ids), ids, "the old pieces' ids")
	assert_null(brushes.find_brush_by_id(gone), "the deleted piece is gone again")
	assert_eq(root.find_entities_by_name("arch_wall").size(), 3, "the rest still tied")
	assert_eq(root.edited_generator_pieces(restored.generator_id), 1, "and still warned of")


# ===========================================================================
# An Update keeps each piece in its group and visgroups (#1201)
# ===========================================================================


## An arch with every piece in group `Arch` and visgroup `Walls`, which is hidden,
## and its first piece in visgroup `Trim` as well.
func _sorted_arch() -> void:
	assert_true(_create({"segments": 4}).ok)
	root.group_selection("Arch", _pieces())
	root.add_selection_to_visgroup("Walls", _pieces())
	root.add_selection_to_visgroup("Trim", [_pieces()[0]])
	root.set_visgroup_visible("Walls", false)


func _membership(node: Node) -> Array:
	return [
		Array(node.get_meta("visgroups", PackedStringArray())),
		str(node.get_meta("group_id", "")),
		node.visible,
	]


func test_an_update_keeps_each_piece_in_its_group_and_visgroups():
	# A rebuild makes new pieces and carried neither over, so every piece fell out
	# of its group, and the pieces of a hidden visgroup showed.
	_sorted_arch()
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	var pieces := _pieces()
	assert_eq(_membership(pieces[0]), [["Walls", "Trim"], "Arch", false], "the piece in both")
	for piece in pieces.slice(1):
		assert_eq(_membership(piece), [["Walls"], "Arch", false], str(piece.name))
	assert_eq(root.get_group_members("Arch").size(), 4)


func test_pieces_an_update_adds_join_what_every_piece_shared():
	_sorted_arch()
	var record = _only_record()
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 6})).ok)
	var pieces := _pieces()
	assert_eq(pieces.size(), 6)
	assert_eq(_membership(pieces[0]), [["Walls", "Trim"], "Arch", false], "the first keeps its own")
	for piece in pieces.slice(4):
		assert_eq(_membership(piece), [["Walls"], "Arch", false], "a new piece, not in Trim")
	assert_eq(root.get_group_members("Arch").size(), 6)


func test_a_deleted_piece_an_update_puts_back_joins_what_every_piece_shared():
	_sorted_arch()
	var record = _only_record()
	brushes.delete_brush_by_id(str(record.brush_ids[2]))
	assert_true(generators.regenerate(record.generator_id, _arch({"segments": 4})).ok)
	assert_eq(_membership(_pieces()[2]), [["Walls"], "Arch", false], "hidden with the rest")
