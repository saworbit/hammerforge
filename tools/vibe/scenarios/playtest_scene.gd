@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Test Level actually hands the player.
##
## `playtest-spawn` checks where the player's feet end up. This checks what is
## around them: the geometry, the entities, the lights and the I/O dispatcher
## that the exported `.tscn` really contains, read back off disk rather than
## taken on the exporter's word.


func id() -> String:
	return "playtest-scene"


func summary() -> String:
	return "what the exported playtest scene contains, read back off disk"


func run() -> void:
	await _what_an_entity_becomes()
	await _geometry_and_dispatcher()


func _spawn(root: Node3D, type: String, where: Vector3, authored: String) -> Node3D:
	return (
		root
		. _restore_entity_from_info(
			{
				"entity_type": type,
				"entity_class": type,
				"transform": Transform3D(Basis.IDENTITY, where),
				"properties": {},
				"name": authored,
				"entity_name": authored,
			}
		)
	)


func _describe_tree(node: Node, depth: int = 0, out: Array = []) -> Array:
	out.append("%s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()])
	for c in node.get_children():
		_describe_tree(c, depth + 1, out)
	return out


func _count_class(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count_class(c, cls)
	return n


## The level has three built-in entity classes. entities.json gives each a
## `"class"`, and the user guide documents that field as the Godot node class.
func _what_an_entity_becomes() -> void:
	var root: Node3D = await fresh_root()
	var defs = root.entity_definitions
	note("built-in entity classes", defs.keys() if defs is Dictionary else defs)

	var lamp := _spawn(root, "light_point", Vector3(0, 64, 0), "lamp_1")
	var door := _spawn(root, "door_basic", Vector3(128, 0, 0), "door_1")
	var start := _spawn(root, "player_start", Vector3(0, 0, 0), "start")
	await frame()
	note("placed light_point node class", lamp.get_class() if lamp else "none")
	note("placed door_basic node class", door.get_class() if door else "none")
	note("placed player_start node class", start.get_class() if start else "none")

	var path := "user://vibe_playtest.tscn"
	var ok: bool = root.export_playtest_scene(path)
	note("export_playtest_scene returned", ok)
	if not ok:
		flag("export_playtest_scene refused a level with three entities and no geometry")
		return
	var packed: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		flag("the exported playtest scene will not load back")
		return
	var scene: Node = packed.instantiate()
	note("playtest scene tree", _describe_tree(scene))

	var lights := _count_class(scene, "Light3D")
	var omni := _count_class(scene, "OmniLight3D")
	note("Light3D nodes in the playtest scene", lights)
	note("OmniLight3D nodes in the playtest scene", omni)
	var sun := scene.get_node_or_null("PlaytestSun")
	note("fallback PlaytestSun added", sun != null)
	if omni == 0:
		known(
			598,
			"a light entity does not become a light in the playtest scene",
			(
				(
					'entities.json gives light_point "class": "OmniLight3D" and the user '
					+ "guide documents that field as the Godot node class, but "
					+ "export_playtest_scene() duplicates the DraftEntity itself. The scene "
					+ "holds %d OmniLight3D and %d Light3D, and because a DraftEntity is not a "
					+ "Light3D the exporter decides nothing provides light and adds its own sun. "
					+ "Every light a mapper places is a billboard icon that lights nothing"
				)
				% [omni, lights]
			)
		)

	# Whatever the properties are for, they are not reaching a node either.
	if lamp:
		lamp.entity_data["energy"] = 8.0
		lamp.entity_data["range"] = 999.0
		note("light entity properties", lamp.entity_data)
	scene.free()


## Geometry and the I/O dispatcher, which is the half that does work.
func _geometry_and_dispatcher() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(512, 16, 512), Vector3(0, -8, 0))
	box(root, Vector3(64, 64, 64), Vector3(0, 32, 0))
	var button := _spawn(root, "door_basic", Vector3(64, 0, 0), "button_1")
	var door := _spawn(root, "door_basic", Vector3(192, 0, 0), "door_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	await root.bake()
	await frame()

	var path := "user://vibe_playtest2.tscn"
	var ok: bool = root.export_playtest_scene(path)
	note("export with geometry and wiring", ok)
	var packed: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		flag("the exported playtest scene will not load back")
		return
	var scene: Node = packed.instantiate()
	note("playtest scene tree", _describe_tree(scene))
	note("MeshInstance3D count", _count_class(scene, "MeshInstance3D"))
	note("StaticBody3D count", _count_class(scene, "StaticBody3D"))
	var dispatcher := scene.get_node_or_null("HFIODispatcher")
	note("I/O dispatcher present", dispatcher != null)
	if dispatcher == null:
		flag(
			"a wired level exports a playtest scene with no I/O dispatcher",
			"the button's OnPressed output has nothing to fire it"
		)
	var player := scene.get_node_or_null("PlaytestPlayer")
	note("player present", player != null)
	if player:
		note("player position", player.position)
	if door == null:
		note("door", "not created")
	scene.free()
