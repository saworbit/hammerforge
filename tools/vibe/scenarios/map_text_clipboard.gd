@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Copy as `.map` text, and `.map` text pasted back in through the importer
## (#1722).
##
## Copy puts the selection on the system clipboard as `.map` text, and when the
## clipboard holds `.map` text newer than HammerForge's own copy, Ctrl+V and
## Paste at Cursor read it through the importer. That is the path a room takes
## between two projects, or out of a forum post. So the question is what a room
## is after the text round trip: as many brushes, each face on the material it had
## (by name, against a palette in a different order), its texture where it was,
## the door still one door with its name and wires, the point entities with their
## keys; placed with its bottom centre where it was asked; and whether a state
## round trip takes the paste back out, palette slots and all.
##
## The clipboard buffer and the system clipboard are both redirected for the run
## (`clipboard_path`, `system_clipboard_stand_in`), so neither the user's buffer
## nor the OS clipboard is touched, and both are put back at the end.

const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFProto = preload("res://addons/hammerforge/hf_prototype_textures.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

const TEMP_DIR := "user://vibe_map_text_clipboard"

var _old_clipboard_path := ""
var _old_stand_in: Variant = null


func id() -> String:
	return "map-text-clipboard"


func summary() -> String:
	return "Copy as .map text and paste it back: brushes, materials, UVs, ties, wires, placement"


func expected_issues() -> Array[int]:
	return [1994]


func run() -> void:
	_redirect_clipboard()
	await _round_trip()
	await _not_map_text()
	_restore_clipboard()


func _redirect_clipboard() -> void:
	_old_clipboard_path = HFPrefabSystemType.clipboard_path
	_old_stand_in = HFPrefabSystemType.system_clipboard_stand_in
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	HFPrefabSystemType.clipboard_path = TEMP_DIR.path_join("clip.hfprefab")
	HFPrefabSystemType.system_clipboard_stand_in = ""


func _restore_clipboard() -> void:
	HFPrefabSystemType.clipboard_path = _old_clipboard_path
	HFPrefabSystemType.system_clipboard_stand_in = _old_stand_in
	for f in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_DIR.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_DIR))


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _proto(pattern: String, color: String) -> Material:
	return ResourceLoader.load(HFProto.get_material_path(pattern, color)) as Material


func _session_material(label: String, colour: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	mat.albedo_color = colour
	return mat


func _point_entity(root: Node3D, type: String, node_name: String, at: Vector3):
	var e := DraftEntity.new()
	e.entity_type = type
	e.entity_class = type
	e.name = node_name
	root.add_entity(e)
	e.global_position = at
	e.set_meta("entity_name", node_name)
	return e


func _face_pointing(brush: Node, direction: Vector3) -> int:
	var best := -1
	var best_dot := -INF
	for i in brush.faces.size():
		var d: float = brush.faces[i].normal_through(brush.global_transform.basis).normalized().dot(
			direction
		)
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _world_bounds(brush: Node3D) -> AABB:
	var b := AABB()
	var first := true
	for f in brush.faces:
		for c in f.local_verts:
			var p: Vector3 = brush.global_transform * c
			b = AABB(p, Vector3.ZERO) if first else b.expand(p)
			first = false
	return b


func _material_name(root: Node3D, slot: int) -> String:
	if slot < 0:
		return "<none>"
	var names: Array = root.material_manager.get_material_names()
	return str(names[slot]) if slot < names.size() else "<slot %d missing>" % slot


## Each face of `brush` by its world normal, rounded, with its material name and
## the UV it shows at its first corner's world position.
func _faces_by_normal(root: Node3D, brush: Node3D) -> Dictionary:
	var out := {}
	for f in brush.faces:
		var n: Vector3 = f.normal_through(brush.global_transform.basis).normalized().snapped(
			Vector3.ONE * 0.01
		)
		out[str(n)] = {
			"material": _material_name(root, f.material_idx),
			"hidden": f.is_hidden(),
			"face": f,
			"brush": brush,
		}
	return out


## The UV a face shows at world point `p`, which lies on it.
func _uv_at_world(brush: Node3D, face, p: Vector3) -> Vector2:
	var local: Vector3 = brush.global_transform.affine_inverse() * p
	return face.shown_uvs_at(PackedVector3Array([local]))[0]


## Level A: the room that gets copied.
func _build(root: Node3D) -> Dictionary:
	var made := {}
	root.add_material_to_palette(_proto("checker", "blue"))
	root.add_material_to_palette(_session_material("editor_red", Color(0.9, 0.1, 0.1)))
	var wall = box(root, Vector3(4, 3, 0.25), Vector3(0, 1.5, -3))
	await frame()
	root.assign_material_to_whole_brushes(0, [_bid(wall)])
	var front := _face_pointing(wall, Vector3.BACK)
	root.assign_material_to_faces_by_id(_bid(wall), [front], 1)
	root.set_face_uv_params(_bid(wall), front, Vector2(0.5, 0.5), Vector2(0.25, 0.125), 0.0)
	var top := _face_pointing(wall, Vector3.UP)
	root.set_face_uv_params(_bid(wall), top, Vector2(1, 1), Vector2.ZERO, deg_to_rad(90.0))
	var side := _face_pointing(wall, Vector3.RIGHT)
	root.set_face_uv_params(
		_bid(wall), side, Vector2(0.5, 2.0), Vector2(0.3, 0.1), deg_to_rad(30.0)
	)
	root.add_material_to_palette(_session_material("only_in_a", Color(0.2, 0.8, 0.2)))
	var back := _face_pointing(wall, Vector3.FORWARD)
	root.assign_material_to_faces_by_id(_bid(wall), [back], 2)
	made["wall"] = wall
	var turned = box(root, Vector3(2, 1, 1), Vector3(3, 0.5, 0))
	await frame()
	root.rotate_managed_nodes([_bid(turned)], [], 1, 30.0, turned.global_position)
	root.assign_material_to_whole_brushes(1, [_bid(turned)])
	made["turned"] = turned
	var column = root.create_brush_from_info(
		{"shape": 1, "size": Vector3(1, 3, 1), "center": Vector3(-3, 1.5, 0), "sides": 8}
	)
	await frame()
	made["column"] = column
	var leaves: Array = []
	for i in 2:
		leaves.append(box(root, Vector3(0.6, 2, 0.15), Vector3(-0.3 + i * 0.6, 1, 0)))
	await frame()
	root.tie_brushes_to_entity(leaves.map(func(b): return _bid(b)), "func_door", "gate")
	made["leaves"] = leaves
	var button = box(root, Vector3(0.2, 0.2, 0.1), Vector3(1.2, 1.2, 0))
	await frame()
	root.tie_brushes_to_entity([_bid(button)], "func_button", "btn")
	root.add_entity_output(button, "OnPressed", "gate", "Open", "", 0.0, false)
	made["button"] = button
	var relay = _point_entity(root, "logic_relay", "relay", Vector3(2, 0.5, 0))
	root.add_entity_output(relay, "OnTrigger", "gate", "Close", "", 0.5, false)
	var lamp = _point_entity(root, "light_point", "lamp", Vector3(0, 2.5, -1))
	made["relay"] = relay
	made["lamp"] = lamp
	return made


func _round_trip() -> void:
	note("-- copy as .map text, paste it back --")
	var a: Node3D = await fresh_root("LevelA")
	var made: Dictionary = await _build(a)
	var brushes: Array = [made["wall"], made["turned"], made["column"], made["button"]]
	brushes.append_array(made["leaves"])
	var entities: Array = [made["relay"], made["lamp"]]
	var copied: bool = a.prefab_system.copy_to_clipboard(brushes, entities)
	var text: String = str(HFPrefabSystemType.system_clipboard_stand_in)
	note("copy", "%s, %d lines of .map text" % [copied, text.split("\n").size()])
	note("the clipboard is HammerForge's own copy", a.prefab_system.newer_map_text() == "")
	if text == "":
		flag("Copy put no .map text on the clipboard")
		await drop_root(a)
		return

	# Level B: a palette in another order, and one material A does not have.
	var b: Node3D = await fresh_root("LevelB")
	b.add_material_to_palette(_proto("brick", "orange"))
	b.add_material_to_palette(_session_material("editor_red", Color(0.9, 0.1, 0.1)))
	b.add_material_to_palette(_proto("checker", "blue"))
	var palette_before: Array = b.material_manager.get_material_names()
	var state: Dictionary = b.capture_state()
	var level_before := HFVibe.describe_level(b)
	# In place: the bottom centre of everything copied.
	var all_bounds := AABB()
	var first := true
	for brush in brushes:
		var wb := _world_bounds(brush)
		all_bounds = wb if first else all_bounds.merge(wb)
		first = false
	for e in entities:
		all_bounds = all_bounds.expand(e.global_position)
	var bottom := Vector3(
		all_bounds.get_center().x, all_bounds.position.y, all_bounds.get_center().z
	)
	var pasted: Dictionary = b.file_system.paste_map_text(text, bottom)
	await frame()
	var got_brushes: Array = pasted["brushes"]
	var got_entities: Array = pasted["entities"]
	note(
		"paste the text into another level, in place",
		(
			"%d brushes (of %d), %d entities (of %d), %d lines dropped %s"
			% [
				got_brushes.size(),
				brushes.size(),
				got_entities.size(),
				entities.size(),
				int(pasted["dropped"]),
				pasted["first_dropped"]
			]
		)
	)
	if got_brushes.size() != brushes.size():
		flag(
			"the .map text round trip changed the brush count",
			"%d of %d" % [got_brushes.size(), brushes.size()]
		)
	if got_entities.size() != entities.size():
		flag(
			"the .map text round trip changed the entity count",
			"%d of %d" % [got_entities.size(), entities.size()]
		)

	# Match each original brush to the pasted one in the same place.
	var unmatched: Array = []
	var material_diffs: Array = []
	var uv_diffs: Array = []
	for brush in brushes:
		var want := _world_bounds(brush)
		var match_brush: Node3D = null
		for g in got_brushes:
			var have := _world_bounds(g)
			if (
				have.position.distance_to(want.position) < 0.01
				and have.end.distance_to(want.end) < 0.01
			):
				match_brush = g
		if match_brush == null:
			unmatched.append(str(brush.name))
			continue
		var faces_a := _faces_by_normal(a, brush)
		var faces_b := _faces_by_normal(b, match_brush)
		for key in faces_a:
			if not faces_b.has(key):
				material_diffs.append("%s face %s missing" % [brush.name, key])
				continue
			var fa: Dictionary = faces_a[key]
			var fb: Dictionary = faces_b[key]
			if fa["material"] != fb["material"]:
				material_diffs.append(
					"%s face %s: %s -> %s" % [brush.name, key, fa["material"], fb["material"]]
				)
			# The UV each shows at the original face's first corner.
			var corner: Vector3 = brush.global_transform * (fa["face"].local_verts[0] as Vector3)
			var ua := _uv_at_world(brush, fa["face"], corner)
			var ub := _uv_at_world(match_brush, fb["face"], corner)
			var corner2: Vector3 = brush.global_transform * (fa["face"].local_verts[1] as Vector3)
			var ua2 := _uv_at_world(brush, fa["face"], corner2)
			var ub2 := _uv_at_world(match_brush, fb["face"], corner2)
			if ua.distance_to(ub) > 0.01 or ua2.distance_to(ub2) > 0.01:
				uv_diffs.append("%s face %s: %s/%s -> %s/%s" % [brush.name, key, ua, ua2, ub, ub2])
	note("brushes not found where they were", unmatched)
	note("faces whose material changed", material_diffs.size())
	note("faces whose texture moved", uv_diffs.size())
	if not unmatched.is_empty():
		flag("the .map text round trip moved or reshaped brushes", str(unmatched))
	if not material_diffs.is_empty():
		flag(
			"the .map text round trip changed faces' materials", str(material_diffs).substr(0, 600)
		)
	if not uv_diffs.is_empty():
		flag(
			"the .map text round trip moved %d faces' textures" % uv_diffs.size(),
			str(uv_diffs).substr(0, 900)
		)

	# The door, the button and the wires.
	var classes := {}
	for g in got_brushes:
		var cls := str(g.get_meta("brush_entity_class", ""))
		if cls != "":
			var key := (
				"%s/%s/%s"
				% [
					cls,
					str(g.get_meta("entity_name", "")),
					str(g.get_meta("brush_entity_group", ""))
				]
			)
			classes[key] = int(classes.get(key, 0)) + 1
	note("brush entities after the paste (class/name/tie: brushes)", classes)
	var doors := 0
	for key in classes:
		if str(key).begins_with("func_door/gate/"):
			doors += 1
			if int(classes[key]) != 2:
				flag("the door's two leaves did not come back as one door", classes)
	if doors != 1:
		flag("the pasted door is not one door named gate", classes)
	var wires: Array = b.get_all_entity_connections()
	var wire_text: Array = []
	for w in wires:
		wire_text.append(
			(
				"%s -> %s.%s delay %s"
				% [
					w.get("output_name", ""),
					w.get("target_name", ""),
					w.get("input_name", ""),
					w.get("delay", "")
				]
			)
		)
	wire_text.sort()
	note("wires after the paste", wire_text)
	if wires.size() != 2:
		flag(
			"the .map text round trip changed the wires", "%d of 2: %s" % [wires.size(), wire_text]
		)
	for e in got_entities:
		note(
			"pasted entity",
			(
				"%s %s at %s"
				% [
					e.get("entity_class"),
					str(e.get_meta("entity_name", e.name)),
					e.global_position.snapped(Vector3.ONE * 0.001)
				]
			)
		)

	# Undo: the state before the paste, palette and all.
	b.restore_state(state)
	await frame()
	var palette_after: Array = b.material_manager.get_material_names()
	note(
		"palette before the paste and after restoring", "%s / %s" % [palette_before, palette_after]
	)
	if palette_after != palette_before:
		flag(
			"restoring the state from before a .map text paste leaves the slots it minted",
			"%s -> %s" % [palette_before, palette_after]
		)
	diff_levels(level_before, HFVibe.describe_level(b), "a .map text paste then restore")

	# Paste at a cursor point: the bottom centre of what is made lands on it.
	var at := Vector3(10, 2, -5)
	var moved: Dictionary = b.file_system.paste_map_text(text, at)
	await frame()
	var mb := AABB()
	first = true
	for g in moved["brushes"]:
		var wb2 := _world_bounds(g)
		mb = wb2 if first else mb.merge(wb2)
		first = false
	for e in moved["entities"]:
		mb = mb.expand(e.global_position)
	var landed := Vector3(mb.get_center().x, mb.position.y, mb.get_center().z)
	note(
		"paste at (10, 2, -5)",
		"the bottom centre lands at %s" % landed.snapped(Vector3.ONE * 0.001)
	)
	if landed.distance_to(at) > 0.01:
		flag(
			"Paste at Cursor with .map text does not stand the paste on the point",
			"%s against %s" % [landed, at]
		)
	for problem in HFVibe.check_invariants(b):
		flag("a .map text paste broke an invariant", problem)
	for problem in HFVibe.check_solids(b, {}):
		flag("a .map text paste made a bad solid", problem)
	await drop_root(b)
	await _names_collide(a, text)
	await drop_root(a)


## The level the text lands in already has a door called gate and a lamp: the
## buffer's paste renames the copies and aims their wires at them
## (`paste-across-levels`). Does the importer's?
func _names_collide(a: Node3D, text: String) -> void:
	note("-- .map text pasted into the level it came from --")
	var before_index: Dictionary = a.entity_system.build_name_index()
	note("addresses before", before_index.keys())
	var pasted: Dictionary = a.file_system.paste_map_text(text, Vector3(0, 0, 8))
	await frame()
	var index: Dictionary = a.entity_system.build_name_index()
	var shared: Array = []
	for address in index:
		var owners := {}
		for node in index[address]:
			var tie := str(node.get_meta("brush_entity_group", ""))
			owners[tie if tie != "" else str(node.get_instance_id())] = true
		if owners.size() > 1:
			shared.append("%s x%d" % [address, owners.size()])
	note("addresses answered to by more than one entity after the paste", shared)
	var reach_old := 0
	var pasted_nodes: Array = (pasted["brushes"] as Array) + (pasted["entities"] as Array)
	for source in pasted_nodes:
		for conn in source.get_meta("entity_io_outputs", []):
			var hits: Array = a.find_entities_by_name(str(conn.get("target_name", "")))
			for h in hits:
				if not pasted_nodes.has(h):
					reach_old += 1
	note("pasted wires that reach an entity the level already had", reach_old)
	if not shared.is_empty() or reach_old > 0:
		known(
			1994,
			".map text pasted into a level that has the same names leaves two entities answering to one name",
			(
				(
					"%s; %d pasted wire hits land on the level's own entities, so the pasted button opens the old door too. "
					+ "The buffer's paste renames them (gate -> gate_2) and aims the wires at the copy"
				)
				% [shared, reach_old]
			)
		)


## Text that is not `.map` text must not be taken for it, or Ctrl+V pastes it
## through the importer instead of the copy the mapper made.
func _not_map_text() -> void:
	note("-- clipboard text that is not .map text --")
	var root: Node3D = await fresh_root()
	var samples := {
		"a sentence": "Meet at the door at 6",
		"JSON": '{\n  "name": "door",\n  "speed": 2\n}',
		"GDScript dictionary": 'var d := {\n\t"classname": "light",\n}',
		"CSS": "body {\n  color: red;\n}",
		"a block holding a classname line": '{\n"classname" "light"\n}',
	}
	for label in samples:
		var is_map: bool = root.file_system.is_map_text(samples[label])
		note("is_map_text(%s)" % label, is_map)
	await drop_root(root)
