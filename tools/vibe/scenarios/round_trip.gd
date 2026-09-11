@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Does a level survive the two round trips a mapper makes constantly?
##
## Undo (`capture_state` / `restore_state`) and save-and-reopen
## (`save_hflevel` / `load_hflevel`) both claim to reproduce the level. This
## builds one rich enough to be worth losing -- per-face appearance, entities
## with wiring, visgroups, groups, a generator, a displacement, a palette -- and
## diffs what comes back. Data loss here is silent by nature: the operation
## reports success and the level is simply poorer than it was.

## Keys whose loss is already reported, mapped to the issue covering them.
## Empty while the two that were here -- #283 and #284, both the same untyped
## Array assigned to a typed property -- are fixed and holding.
const KNOWN_LOSSES := {}

## Real palette materials, loaded from disk. See the note in `_build()`.
const PALETTE_MATERIALS: Array[String] = [
	"res://materials/test_mat.tres",
	"res://addons/hammerforge/textures/prototypes/materials/proto_arrow_down_blue.tres",
	"res://addons/hammerforge/textures/prototypes/materials/proto_arrow_down_green.tres",
]


func id() -> String:
	return "round-trip"


func summary() -> String:
	return "undo and .hflevel round trips over a level with something in it"


func run() -> void:
	var root: Node3D = await fresh_root()
	_build(root)
	await frame()

	var before := HFVibe.describe_level(root)
	note(
		(
			"built %d brushes, %d entities, %d materials"
			% [before["brushes"].size(), before["entities"].size(), before["materials"].size()]
		)
	)

	note("--- capture_state then restore_state")
	var snapshot: Dictionary = root.capture_state()
	root.restore_state(snapshot)
	await frame()
	diff_levels(before, HFVibe.describe_level(root), "undo round trip")

	note("--- save_hflevel then load_hflevel into a fresh root")
	var path := "user://vibe_round_trip.hflevel"
	root.save_hflevel(path, true)
	var settled: bool = await HFVibe.settle_save(_tree, root)
	if not settled:
		flag("the save thread never finished")
		return
	note("file size", HFVibe.file_size(path))

	var reopened: Node3D = await fresh_root("Reopened")
	var loaded: bool = reopened.load_hflevel(path)
	await frame()
	if not loaded:
		flag("load_hflevel refused a file it had just written")
		return
	diff_levels(before, HFVibe.describe_level(reopened), "file round trip", KNOWN_LOSSES)


## A level with one of everything worth losing.
func _build(root: Node3D) -> void:
	# Materials must come off disk. A `.hflevel` stores the resource path of each
	# palette slot, so a StandardMaterial3D built in memory has nothing to store
	# and comes back null through no fault of the loader. Using real resources is
	# what a user's palette actually holds, and is the only way this round trip
	# says anything.
	for path in PALETTE_MATERIALS:
		var m = load(path)
		if m == null:
			flag("fixture material missing", path)
			continue
		root.material_manager.add_material(m)

	for i in range(4):
		var b = box(root, Vector3(64, 32, 64), Vector3(i * 80, 0, 0))
		var faces = b.get("faces")
		if faces is Array and (faces as Array).size() > 2:
			faces[0].material_idx = 1
			faces[1].uv_offset = Vector2(0.25, 0.5)
			faces[1].uv_scale = Vector2(2.0, 0.5)
			faces[2].uv_rotation = 45.0

	(
		root
		. create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(32, 32, 32),
				"transform": Transform3D(Basis(Vector3.UP, deg_to_rad(30)), Vector3(0, 80, 0)),
			}
		)
	)
	root.create_brush_from_info(
		{"shape": 1, "size": Vector3(20, 60, 20), "center": Vector3(-120, 0, 0), "sides": 10}
	)

	var brush_entity = box(root, Vector3(48, 48, 48), Vector3(0, 0, 200))
	brush_entity.set_meta("brush_entity_class", "func_door")

	root.create_generator("stairs", {}, Transform3D(Basis(), Vector3(300, 0, 300)))

	var defs: Dictionary = root.get_entity_definitions()
	var types: Array = defs.keys()
	if types.size() > 0:
		var spawn = (
			root
			. _create_entity_from_map(
				{
					"classname": str(types[0]),
					"origin": Vector3(5, 0, 5),
					"properties": {"targetname": "spawn"},
				}
			)
		)
		if spawn:
			spawn.name = "spawn"
		var door_type: String = str(types[types.size() - 1])
		var door = (
			root
			. _create_entity_from_map(
				{
					"classname": door_type,
					"origin": Vector3(50, 0, 5),
					"properties": {"targetname": "d1", "speed": "100"},
				}
			)
		)
		if door:
			door.name = "door_one"
			door.set_meta("entity_name", "the_door")
		if spawn:
			root.add_entity_output(spawn, "OnStart", "the_door", "Open", "1", 1.5)

	root.create_visgroup("Walls", Color(1, 0, 0))
	root.create_visgroup("Detail", Color(0, 1, 0))
	var kids: Array = root.draft_brushes_node.get_children()
	root.add_selection_to_visgroup("Walls", [kids[0], kids[1]])
	root.group_selection("GroupA", [kids[2], kids[3]])
	root.set_cordon_from_selection([kids[0], kids[1]])

	var first_id := str(kids[0].get_meta("brush_id"))
	root.displacement_system.create_displacement(first_id, 0, 2)
	root.displacement_system.set_elevation(first_id, 0, 12.0)
