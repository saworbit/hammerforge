extends GutTest

## A rebuild keeps everything about a copy that its source does not hold (#1221).
##
## A prefab copy is rebuilt by a variant switch and by a Pull, and a generated
## structure by Update. Each deletes the copy's nodes and makes them again, and
## whatever a node had that the source does not say crosses over through
## `HFRebuildCarry` or is lost. Each property used to be carried by hand in each
## path, and every one missed was a bug report.
##
## `_rows()` is the one list of what a copy can have. A row sets its property on
## the nodes of a copy it applies to, reads it back, and names the rebuilds that
## keep it; the others give back what the source says, which here is what the copy
## was placed with. A property added to `HFRebuildCarry.PROPERTIES` fails
## `test_every_property_the_carry_knows_has_a_row` until it has a row here, and the
## row then holds every rebuild to it.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const DraftBrushScript = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

const VARIANT := "prefab variant switch"
const PULL := "prefab Pull"
const UPDATE := "generator Update"
const EVERY_REBUILD := [VARIANT, PULL, UPDATE]

## Not any one node's: where the copy is and which way it faces, which a rebuild
## works out from what most of its nodes say (`HFRebuildCarry.most_agreed()`).
const FRAME := "frame"

const PATH := "user://hf_test_rebuild_carry.hfprefab"

var _level: LevelRoot
var _paint: StandardMaterial3D
## What a copy is given as a whole: a quarter turn and a slide.
var _move := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(4, 0, -6))


func before_each():
	_level = LevelRoot.new()
	_level.auto_spawn_player = false
	_level.commit_freeze = false
	_level.hflevel_autosave_enabled = false
	add_child_autoqfree(_level)
	_paint = StandardMaterial3D.new()


func after_each():
	_level = null
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


# ===========================================================================
# The table
# ===========================================================================


func _rows() -> Array:
	return [
		_row(HFRebuildCarry.NODE_NAME, EVERY_REBUILD, _name_node, _node_name),
		_row(HFRebuildCarry.ENTITY_NAME, EVERY_REBUILD, _rename_entity, _entity_name, _named),
		# A name given where the source gives none is the copy's alone (#1274).
		_row(HFRebuildCarry.ENTITY_NAME, EVERY_REBUILD, _name_entity, _entity_name, _unnamed),
		_row(HFRebuildCarry.MEMBERSHIP, EVERY_REBUILD, _sort_into_groups, _membership),
		# A prefab holds its entities' classes, properties and wires, and its look.
		_row(HFRebuildCarry.ENTITY, [UPDATE], _wire_and_set, _entity, _brush),
		_row(HFRebuildCarry.APPEARANCE, [UPDATE], _paint_brush, _appearance, _brush),
		_row(FRAME, EVERY_REBUILD, _move_with_the_copy, _pose),
	]


## `applies` says which nodes of a copy, as placed, the row is about. Every node
## when it is left out.
func _row(
	property: String, kept_by: Array, set_it: Callable, read: Callable, applies := Callable()
) -> Dictionary:
	return {
		"property": property,
		"kept_by": kept_by,
		"set": set_it,
		"read": read,
		"applies": applies,
	}


func _named(node: Node) -> bool:
	return str(node.get_meta(HFBrushEntity.NAME_META, "")) != ""


func _unnamed(node: Node) -> bool:
	return not _named(node)


func _brush(node: Node) -> bool:
	return node is DraftBrushScript


func _name_node(node: Node, i: int) -> void:
	node.name = "Kept_%d" % i


func _node_name(node: Node) -> Variant:
	return str(node.name)


## A new name for each entity, the same on every node of it, so a wall of two
## leaves stays one wall.
func _rename_entity(node: Node, _i: int) -> void:
	var was := str(node.get_meta(HFBrushEntity.NAME_META, ""))
	node.set_meta(HFBrushEntity.NAME_META, "renamed_%s" % was)


func _entity_name(node: Node) -> Variant:
	return str(node.get_meta(HFBrushEntity.NAME_META, ""))


## A name for each entity the source leaves unnamed, the same on every brush of one
## tie, so a tied entity stays one entity and two stay two.
func _name_entity(node: Node, _i: int) -> void:
	var tie := str(node.get_meta(HFBrushEntity.TIE_META, ""))
	node.set_meta(HFBrushEntity.NAME_META, "own_%s" % (tie if tie != "" else str(node.name)))


## Alternate nodes in two visgroups, the second hidden, and every node in a group.
func _sort_into_groups(node: Node, i: int) -> void:
	_level.add_selection_to_visgroup("Vis_%d" % (i % 2), [node])
	_level.group_selection("Grp", [node])
	_level.set_visgroup_visible("Vis_1", false)


func _membership(node: Node) -> Variant:
	return [
		Array(node.get_meta("visgroups", PackedStringArray())),
		str(node.get_meta("group_id", "")),
		node.visible,
	]


func _wire_and_set(node: Node, i: int) -> void:
	node.set_meta(HFBrushEntity.DATA_META, {"speed": str(i)})
	var wire := {"output_name": "OnUser1", "target_name": "elsewhere", "input_name": "Trigger"}
	node.set_meta(HFBrushEntity.OUTPUTS_META, [wire])


func _entity(node: Node) -> Variant:
	return [
		HFBrushEntity.entity_class(node),
		node.get_meta(HFBrushEntity.DATA_META, {}),
		node.get_meta(HFBrushEntity.OUTPUTS_META, []),
	]


func _paint_brush(brush, i: int) -> void:
	brush.material_override = _paint
	for face in brush.faces:
		face.uv_scale = Vector2(2 + i, 3)


func _appearance(brush) -> Variant:
	return [brush.material_override, brush.faces.map(func(face): return face.uv_scale)]


func _move_with_the_copy(node, _i: int) -> void:
	node.global_transform = _move * node.global_transform


## Where a node is to a hundredth and which way it faces to a thousandth, in whole
## steps so a float's sign at zero cannot tell two of them apart.
func _pose(node) -> Variant:
	var t: Transform3D = node.global_transform
	return [
		Vector3i((t.origin * 100.0).round()),
		Vector3i((t.basis.x * 1000.0).round()),
		Vector3i((t.basis.z * 1000.0).round()),
	]


# ===========================================================================
# Running the table through a rebuild
# ===========================================================================


func _applies(row: Dictionary, node: Node) -> bool:
	return not row["applies"].is_valid() or row["applies"].call(node)


func _read_all(row: Dictionary, mask: Array, nodes: Array) -> Array:
	var out: Array = []
	for i in nodes.size():
		out.append(row["read"].call(nodes[i]) if mask[i] else "-")
	return out


## Set every row on the nodes of a copy it applies to, rebuild the copy, and hold
## each node made to what the node in its place had, or for a row the rebuild does
## not keep, to what it had as placed. Which nodes a row applies to is asked of the
## copy as placed, before any row has changed what it asks about.
func _check_every_row(rebuild: String, id: String, nodes_of: Callable) -> void:
	var rows := _rows()
	var nodes: Array = nodes_of.call(id)
	var masks: Array = rows.map(func(row): return nodes.map(func(node): return _applies(row, node)))
	var placed: Array = []
	for r in rows.size():
		placed.append(_read_all(rows[r], masks[r], nodes))
	for r in rows.size():
		for i in nodes.size():
			if masks[r][i]:
				rows[r]["set"].call(nodes[i], i)
	var given: Array = []
	for r in rows.size():
		given.append(_read_all(rows[r], masks[r], nodes))

	_rebuild(rebuild, id)

	var made: Array = nodes_of.call(id)
	assert_eq(made.size(), nodes.size(), "the %s made the copy again whole" % rebuild)
	for r in rows.size():
		var row: Dictionary = rows[r]
		assert_ne(given[r], placed[r], "the %s row changes something to keep" % row["property"])
		var wanted: Array = given[r] if rebuild in row["kept_by"] else placed[r]
		var got := _read_all(row, masks[r], made)
		assert_eq(got, wanted, "%s through a %s" % [row["property"], rebuild])


func _rebuild(rebuild: String, id: String) -> void:
	match rebuild:
		VARIANT:
			assert_true(_level.prefab_system.set_variant(id, "alt"))
		PULL:
			assert_eq(_level.prefab_system.propagate_from_source(PATH), 1)
		UPDATE:
			assert_true(_level.generator_system.regenerate(id, _arch()).ok)


# ===========================================================================
# The copies
# ===========================================================================


## Two leaves tied as one wall named `wall`, a third tied as an unnamed detail, a
## lamp named `lamp` and an unnamed spot, saved with two variants alike and placed
## as a linked copy. Returns the copy's id.
func _prefab_copy() -> String:
	var leaves: Array = [_leaf(-41), _leaf(-39)]
	_level.tie_brushes_to_entity(
		leaves.map(func(leaf): return str(leaf.brush_id)), "func_wall", "wall"
	)
	var detail := _leaf(-40)
	_level.tie_brushes_to_entity([str(detail.brush_id)], "func_detail")
	var lights := [_light("Lamp", "lamp"), _light("Spot", "")]
	var prefab = HFPrefabType.capture_from_selection(
		_level.brush_system, _level.entity_system, leaves + [detail], lights
	)
	var base: Dictionary = prefab.get_variant_data("base")
	prefab.set_variant_data(
		"alt", base["brush_infos"].duplicate(true), base["entity_infos"].duplicate(true)
	)
	assert_eq(prefab.save_to_file(PATH), OK)
	var placed: Dictionary = prefab.instantiate(
		_level.brush_system, _level.entity_system, _level, Vector3(10, 0, 0)
	)
	return _level.prefab_system.register_instance(
		PATH, placed["brush_ids"], placed["entity_nodes"], true
	)


func _light(node_name: String, entity_name: String) -> DraftEntity:
	var light := DraftEntity.new()
	light.name = node_name
	light.entity_type = "light"
	light.entity_class = "light"
	light.set_meta("is_entity", true)
	if entity_name != "":
		light.set_meta(HFBrushEntity.NAME_META, entity_name)
	_level.entities_node.add_child(light)
	light.global_position = Vector3(-40, 3, 0)
	return light


func _leaf(x: float) -> Node:
	return _level.create_brush_from_info({"size": Vector3(1, 2, 0.25), "center": Vector3(x, 1, 0)})


func _prefab_nodes(iid: String) -> Array:
	var rec = _level.prefab_system.get_instance(iid)
	var out: Array = []
	for brush_id in rec.brush_ids:
		out.append(_level.find_brush_by_id(str(brush_id)))
	for uid in rec.entity_uids:
		out.append(_level.entity_system.find_entity_by_prefab_uid(str(uid)))
	return out


func _arch() -> Dictionary:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("arch")
	settings["segments"] = 4
	return settings


## A four piece arch, its first two pieces tied as an entity named `arch` and the
## other two as an unnamed one. Returns its id.
func _structure() -> String:
	assert_true(_level.create_generator("arch", _arch(), Transform3D.IDENTITY).ok)
	var generator_id: String = _level.generator_system.generators.keys()[0]
	var pieces := Array(_level.generator_system.generator_for_id(generator_id).brush_ids)
	_level.tie_brushes_to_entity(pieces.slice(0, 2), "func_wall", "arch")
	_level.tie_brushes_to_entity(pieces.slice(2), "func_detail")
	return generator_id


func _structure_nodes(generator_id: String) -> Array:
	var record = _level.generator_system.generator_for_id(generator_id)
	return Array(record.brush_ids).map(func(brush_id): return _level.find_brush_by_id(brush_id))


# ===========================================================================
# Every rebuild against every row
# ===========================================================================


func test_a_variant_switch_keeps_what_the_prefab_does_not_hold():
	_check_every_row(VARIANT, _prefab_copy(), _prefab_nodes)


func test_a_pull_keeps_what_the_prefab_does_not_hold():
	_check_every_row(PULL, _prefab_copy(), _prefab_nodes)


func test_an_update_keeps_everything_but_the_shape():
	_check_every_row(UPDATE, _structure(), _structure_nodes)


func test_every_property_the_carry_knows_has_a_row():
	var listed: Array = []
	for row in _rows():
		if row["property"] != FRAME and not row["property"] in listed:
			listed.append(row["property"])
	listed.sort()
	var known: Array = HFRebuildCarry.PROPERTIES.duplicate()
	known.sort()
	assert_eq(listed, known, "each property the carry knows needs a row saying who keeps it")


## The carry alone, one node to the node made in its place, for every property at
## once: what each row reads off the one, the other reads back.
func test_every_property_goes_from_a_node_to_the_one_made_in_its_place():
	var old := _leaf(0)
	_level.tie_brushes_to_entity([str(old.brush_id)], "func_wall", "wall")
	var rows: Array = _rows().filter(
		func(row): return row["property"] != FRAME and _applies(row, old)
	)
	for row in rows:
		row["set"].call(old, 0)
	var had: Array = rows.map(func(row): return row["read"].call(old))
	var carry := HFRebuildCarry.capture(
		[["piece", old]], HFRebuildCarry.PROPERTIES, _level.visgroup_system
	)
	_level.brush_system.delete_brush(old)

	var made := _leaf(0)
	carry.restore([["piece", made]])
	for r in rows.size():
		assert_eq(rows[r]["read"].call(made), had[r], rows[r]["property"])
