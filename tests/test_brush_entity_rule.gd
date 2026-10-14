extends GutTest

## Every consumer of the brush entity rule sees the same entities (#1148).
##
## The bake, the runtime dispatcher, the `.map` export, the Entity panel and MCP
## each used to work out which brushes are one entity by themselves, and a change
## to the rule reached them one at a time. This builds one level holding every shape
## an entity comes in and asks each of them, so the next change to the rule fails
## here for every consumer it has not reached.

const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")
const HFMcpTools = preload("res://addons/hammerforge/mcp/hf_mcp_tools.gd")

var scene_root: Node3D
var level: LevelRoot
## Brush node name -> the node names of every brush of its entity, as the rule says.
var expected: Dictionary = {}


func before_each():
	scene_root = Node3D.new()
	add_child_autoqfree(scene_root)
	level = LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene_root.add_child(level)
	expected = {}
	_build_every_shape()


func after_each():
	scene_root = null
	level = null


func _brush(brush_id: String, x: float) -> DraftBrush:
	return (
		(
			level
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(1, 2, 0.25),
					"center": Vector3(x, 1, 0),
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)


func _expect(brushes: Array) -> void:
	var names: Array = brushes.map(func(brush): return str(brush.name))
	names.sort()
	for brush in brushes:
		expected[str(brush.name)] = names


## A named entity with no tie, as a level from before ties keeps it; an unnamed
## tie; a named tie with a property set through one brush, and a second tie under
## the same name; a class with neither a name nor a tie; a second unnamed tie; a
## class of the mapper's own; and a plain brush.
func _build_every_shape() -> void:
	var lift := [_brush("a0", 0), _brush("a1", 2)]
	for brush in lift:
		brush.set_brush_entity_class("func_door")
		brush.set_meta("entity_name", "lift")
	_expect(lift)
	var unnamed := [_brush("b0", 4), _brush("b1", 6)]
	level.tie_brushes_to_entity(["b0", "b1"], "func_door")
	_expect(unnamed)
	var gate := [_brush("c0", 8), _brush("c1", 10)]
	level.tie_brushes_to_entity(["c0", "c1"], "func_door", "gate")
	level.set_entity_properties(gate[1], {"speed": 5.0})
	# Tied on its own under the same name, so the name decides over the tie.
	var third := _brush("g0", 18)
	level.tie_brushes_to_entity(["g0"], "func_door", "gate")
	gate.append(third)
	_expect(gate)
	var wall := _brush("d0", 12)
	wall.set_brush_entity_class("func_wall")
	_expect([wall])
	var single := _brush("f0", 14)
	level.tie_brushes_to_entity(["f0"], "func_door")
	_expect([single])
	# A class of the mapper's own, with an int whose default a JSON file gives as
	# a float and a property with no default at all.
	level.entity_definitions["func_counter"] = {
		"properties":
		[
			{"name": "count", "type": "int", "default": 3.0},
			{"name": "label", "type": "string"},
		]
	}
	var counter := _brush("h0", 20)
	level.tie_brushes_to_entity(["h0"], "func_counter", "counter")
	_expect([counter])
	_brush("e0", 16)


func _entity_brushes() -> Array:
	return level.draft_brushes_node.get_children().filter(
		func(node): return HFBrushEntity.entity_class(node) != ""
	)


func _names_of(brushes: Array) -> Array:
	var names: Array = brushes.map(func(brush): return str(brush.name))
	names.sort()
	return names


# -- The draft side ---------------------------------------------------------------


func test_the_rule_groups_the_brushes_it_is_meant_to():
	var candidates := level._iter_managed_brush_nodes()
	for brush in _entity_brushes():
		assert_eq(
			_names_of(HFBrushEntity.members(brush, candidates)),
			expected[str(brush.name)],
			"%s and its entity" % brush.name
		)


func test_the_entity_panel_sees_the_same_entities():
	for brush in _entity_brushes():
		assert_eq(
			_names_of(level.brush_system.brushes_of_entity(brush)),
			expected[str(brush.name)],
			"%s and its entity" % brush.name
		)


func test_the_map_export_writes_one_block_per_entity():
	var text := MapIO.export_map_from_level(level)
	assert_eq(text.count('"classname" "func_door"'), 4, "lift, the unnamed tie, gate, the single")
	assert_eq(text.count('"classname" "func_wall"'), 1)
	assert_eq(text.count('"targetname" "lift"'), 1, "a name once per entity")
	assert_eq(text.count('"targetname" "gate"'), 1)


# -- The baked side ---------------------------------------------------------------


func _bake() -> Node3D:
	var container := Node3D.new()
	container.name = "Baked"
	scene_root.add_child(container)
	level.bake_system._append_nonstructural_brushes(container)
	return container


## The node the bake made for each brush, by the brush's node name: a door's
## holder, a wall's mesh.
func _baked_by_brush(container: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for node in container.get_node("Nonstructural").get_children():
		if node.has_method("is_open") or node is MeshInstance3D:
			out[str(node.get_meta(HFBrushEntity.BRUSH_NAME_META, node.name))] = node
	return out


func test_the_bake_carries_the_same_entities():
	var baked := _baked_by_brush(_bake())
	assert_eq(baked.size(), expected.size(), "a node for every brush entity's brush")
	for brush_name in baked:
		var identity := HFBrushEntity.baked_identity(baked[brush_name])
		var together: Array = []
		for other in baked:
			if identity != "" and HFBrushEntity.baked_identity(baked[other]) == identity:
				together.append(other)
		if together.is_empty():
			together = [brush_name]
		together.sort()
		assert_eq(together, expected[brush_name], "%s and its entity" % brush_name)


func test_the_dispatcher_sees_the_same_entities():
	var container := _bake()
	var baked := _baked_by_brush(container)
	var dispatcher := HFIORuntime.new()
	container.add_child(dispatcher)
	dispatcher.wire()
	for brush_name in baked:
		var node: Node = baked[brush_name]
		var members: Array = dispatcher._entity_members.get(
			HFBrushEntity.baked_identity(node), [node]
		)
		var together: Array = []
		for other in baked:
			if baked[other] in members:
				together.append(other)
		together.sort()
		assert_eq(together, expected[brush_name], "%s and its entity" % brush_name)


func test_the_bake_gives_each_door_the_properties_the_rule_reads():
	var baked := _baked_by_brush(_bake())
	for brush in _entity_brushes():
		if HFBrushEntity.entity_class(brush) != "func_door":
			continue
		var definition: Dictionary = level.get_entity_definition("func_door")
		assert_eq(
			baked[str(brush.name)].get_meta("entity_data", {}),
			HFBrushEntity.properties(definition, brush),
			"%s" % brush.name
		)
	var gate := _entity_brushes().filter(
		func(brush): return str(brush.get_meta("entity_name", "")) == "gate"
	)
	assert_eq(gate.size(), 3)
	for brush in gate.slice(0, 2):
		assert_eq(baked[str(brush.name)].speed, 5.0, "set through one leaf, %s has it" % brush.name)


func test_mcp_reports_what_the_bake_gives_each_brush():
	# Its doc said "as the bake reads them" while it kept a defaults helper of its
	# own (#1148).
	var baked := _baked_by_brush(_bake())
	var tools := HFMcpTools.new()
	for brush in _entity_brushes():
		var report: Dictionary = tools._brush_entity_dict(level, brush)
		var node: Node = baked[str(brush.name)]
		assert_eq(
			report["name"], str(node.get_meta("entity_name", "")), "%s's address" % brush.name
		)
		var definition: Dictionary = level.get_entity_definition(HFBrushEntity.entity_class(brush))
		assert_eq(
			report["properties"],
			HFMcpTools._plain(HFBrushEntity.properties(definition, brush)),
			"%s's properties" % brush.name
		)
		if node.has_meta("entity_data"):
			assert_eq(
				report["properties"], node.get_meta("entity_data"), "as baked, %s" % brush.name
			)
