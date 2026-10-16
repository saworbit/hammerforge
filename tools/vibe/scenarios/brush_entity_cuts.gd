@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a cut does to a brush that is a door.
##
## The copy paths were all taught to give a brush entity a fresh tie and a name
## of its own (#1158 to #1193): prefab, paste, duplicate, arrays, generator
## Update. The cut paths are the other way a brush entity's brushes change
## number. Clip a door's leaf in two to fit a frame, hollow a trigger volume,
## carve a doorway through a func_wall, merge two leaves into one: each replaces
## one brush with others, and the others have to be the same entity, with the
## same name, the same properties and the same wires, or the door the mapper
## built is now two doors and one of them is deaf.
##
## Measured on the draft brushes by `HFBrushEntity.identity()`, which the bake,
## the runtime, the export and MCP all ask (#1148), and then once through a bake
## to say what a game would get.

const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")


func id() -> String:
	return "brush-entity-cuts"


func summary() -> String:
	return "what clip, hollow, carve, merge and extrude do to a brush tied to a door or a trigger"


func run() -> void:
	await _named_door_cut("clip")
	await _named_door_cut("hollow")
	await _named_door_cut("carve")
	await _named_door_cut("merge")
	await _named_door_cut("extrude")
	await _unnamed_tie_clip()
	await _what_a_bake_makes_of_a_clipped_door()


## A door named `gate` with a speed of its own, wired to a lamp, and a button
## wired to it. Returns the door's brush ids.
func _named_door(root: Node3D, at: Vector3, leaves: int) -> Array:
	var ids: Array = []
	for i in leaves:
		var b = box(root, Vector3(1, 2, 0.2), at + Vector3(i * 1.0, 1, 0))
		ids.append(str(b.get_meta("brush_id", "")))
	root.tie_brushes_to_entity(ids, "func_door", "gate")
	var first = root.find_brush_by_id(ids[0])
	root.set_entity_property(first, "speed", 7.0)
	root.add_entity_output(first, "OnOpen", "lamp", "TurnOn")
	return ids


func _doors(root: Node3D) -> Array:
	var out: Array = []
	for b in root._iter_managed_brush_nodes():
		if HFBrushEntity.entity_class(b) == "func_door":
			out.append(b)
	return out


func _describe(root: Node3D) -> Dictionary:
	var doors := _doors(root)
	var identities := {}
	var speeds: Array = []
	var wired := 0
	var lone := 0
	for b in doors:
		var key := HFBrushEntity.identity(b)
		if key == "":
			lone += 1
			key = "lone:%s" % b.get_meta("brush_id", "")
		identities[key] = true
		var data: Dictionary = b.get_meta("brush_entity_data", {})
		speeds.append(data.get("speed", "-"))
		if not (b.get_meta("entity_io_outputs", []) as Array).is_empty():
			wired += 1
	return {
		"brushes": doors.size(),
		"entities": identities.size(),
		"identities": identities.keys(),
		"speeds": speeds,
		"wired brushes": wired,
		"answer to gate": root.find_entities_by_name("gate").size(),
		"brushes with neither name nor tie": lone,
	}


func _named_door_cut(op: String) -> void:
	var root: Node3D = await fresh_root()
	var leaves := 2 if op == "merge" else 1
	var ids := _named_door(root, Vector3(0, 0, 0), leaves)
	var before := _describe(root)
	var result = null
	match op:
		"clip":
			result = root.clip_brush_by_id(ids[0], 1, 1.0)
		"hollow":
			# A door is thin; hollow a fatter one so the walls fit.
			var fat = root.find_brush_by_id(ids[0])
			root.delete_brush_by_id(ids[0])
			var b = box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
			ids = [str(b.get_meta("brush_id", ""))]
			root.tie_brushes_to_entity(ids, "func_door", "gate")
			root.set_entity_property(b, "speed", 7.0)
			root.add_entity_output(b, "OnOpen", "lamp", "TurnOn")
			before = _describe(root)
			result = root.hollow_brush_by_id(ids[0], 0.2)
		"carve":
			var cutter = box(root, Vector3(0.4, 0.6, 1.0), Vector3(0, 1, 0))
			result = root.carve_with_brush(str(cutter.get_meta("brush_id", "")))
		"merge":
			result = root.merge_brushes_by_ids(ids)
		"extrude":
			# Extrude the top face up: a new brush beside the old one.
			var b = root.find_brush_by_id(ids[0])
			var top := -1
			var faces: Array = b.get_faces()
			for i in faces.size():
				if faces[i].normal.y > 0.9:
					top = i
			var info: Dictionary = root.extrude_face_info(ids[0], top, 0.5)
			note("extrude info carries class", info.get("brush_entity_class", "(none)"))
			if not info.is_empty():
				result = root.create_brush_from_info(info)
	await frame()
	var after := _describe(root)
	var ok_text = result
	if result is Object and result.has_method("get"):
		ok_text = "%s %s" % [result.get("ok"), result.get("message")]
	note("-- %s on door 'gate' --" % op, ok_text)
	note("  before", before)
	note("  after", after)
	if op == "extrude":
		# An extruded brush is new geometry; whether it joins the door is a choice,
		# so this is recorded rather than judged.
		await drop_root(root)
		return
	if int(after["entities"]) > 1:
		known(
			1194,
			"%s splits a named door into %d doors" % [op, int(after["entities"])],
			(
				(
					"door 'gate' was %d brush(es), one entity, speed 7, wired to a lamp. After %s "
					+ "the func_door brushes are %s; %d of them have neither a name nor a tie, so "
					+ "each is a door of its own. A wire aimed at 'gate' reaches %d brush(es)."
				)
				% [
					int(before["brushes"]),
					op,
					after["identities"],
					int(after["brushes with neither name nor tie"]),
					int(after["answer to gate"]),
				]
			)
		)
	var lost_speed := 0
	for s in after["speeds"]:
		if str(s) != "7" and str(s) != "7.0":
			lost_speed += 1
	if lost_speed > 0:
		known(
			1194,
			(
				"%s drops a door's properties from %d of %d pieces"
				% [op, lost_speed, int(after["brushes"])]
			),
			"speed was 7 on the door; after %s the pieces read %s" % [op, after["speeds"]]
		)
	if int(after["answer to gate"]) == 0:
		known(1194, "%s leaves nothing answering to the door's name 'gate'" % op, after)
	if int(before["wired brushes"]) > 0 and int(after["wired brushes"]) == 0:
		known(1194, "%s drops the door's own wires" % op, after)
	await drop_root(root)


## Two leaves tied as one door with no name, one leaf clipped.
func _unnamed_tie_clip() -> void:
	var root: Node3D = await fresh_root()
	var ids: Array = []
	for i in 2:
		var b = box(root, Vector3(1, 2, 0.2), Vector3(50 + i, 1, 0))
		ids.append(str(b.get_meta("brush_id", "")))
	root.tie_brushes_to_entity(ids, "func_door")
	root.set_entity_property(root.find_brush_by_id(ids[0]), "speed", 7.0)
	var before := _describe(root)
	var result = root.clip_brush_by_id(ids[0], 1, 1.0)
	await frame()
	var after := _describe(root)
	note("-- clip one leaf of an unnamed two-leaf door --", result.message if result else null)
	note("  before", before)
	note("  after", after)
	if int(after["entities"]) > int(before["entities"]):
		known(
			1194,
			"clipping one leaf of an unnamed door splits it into %d doors" % int(after["entities"]),
			(
				(
					"two leaves tied as one func_door (one tie, no name). Clip one leaf across Y. "
					+ "Identities after: %s. The clipped halves have no tie, so each is a door of "
					+ "its own and opens on its own."
				)
				% [after["identities"]]
			)
		)
	await drop_root(root)


## What the game gets: the clipped door baked, and its door holders counted.
func _what_a_bake_makes_of_a_clipped_door() -> void:
	var root: Node3D = await fresh_root()
	var ids := _named_door(root, Vector3(100, 0, 0), 1)
	root.clip_brush_by_id(ids[0], 1, 1.0)
	await frame()
	await root.bake(false, false)
	await frame()
	var baked: Array = []
	_collect_entities(root.baked_container, baked)
	var by_identity := {}
	for node in baked:
		var key := HFBrushEntity.baked_identity(node)
		by_identity[key] = int(by_identity.get(key, 0)) + 1
	note("baked func_door nodes by identity", by_identity)
	if by_identity.size() > 1:
		known(
			1194,
			"a clipped door bakes as %d doors" % by_identity.size(),
			"identities in the baked scene: %s" % by_identity
		)
	await drop_root(root)


func _collect_entities(node: Node, out: Array) -> void:
	if node == null:
		return
	for child in node.get_children():
		if HFBrushEntity.entity_class(child) == "func_door":
			out.append(child)
		_collect_entities(child, out)
