extends GutTest

## Live generators: a structure that remembers what made it, and can be made
## again differently.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFGeneratorScript = preload("res://addons/hammerforge/hf_generator.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var brushes: HFBrushSystem
var generators


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.pending_node = null
	root.committed_node = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	root._material_palette = []
	root.texture_lock = false
	brushes = HFBrushSystem.new(root)
	root.brush_system = brushes
	generators = HFGeneratorSystemScript.new(root)
	root.generator_system = generators


func after_each():
	root = null
	brushes = null
	generators = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var brush_system = null
var generator_system = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var _material_palette: Array = []

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(msg: String) -> void:
	pass

func _assign_owner(node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass

func tag_full_reconcile() -> void:
	pass

func tag_brush_dirty(_id: String) -> void:
	pass

func add_material_to_palette(material: Material) -> int:
	_material_palette.append(material)
	return _material_palette.size() - 1
"""
	s.reload()
	return s


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
