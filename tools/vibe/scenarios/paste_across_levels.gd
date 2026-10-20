@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Copy in one level, paste in another.
##
## Two open scene tabs are two `LevelRoot`s in one editor session, and the
## clipboard (#703) is a file in `user://` both of them read. That is the whole
## point of it: move a room out of one map and into the next. `test_clipboard.gd`
## pins that a corridor of three plain boxes crosses. A room a mapper would move
## is not three plain boxes. It has a material made in the session, a face
## painted differently from the rest, a two-leaf door with a button wired to it,
## entities whose names the other level already uses, a visgroup, a group, a
## sculpted floor and a generated staircase.
##
## So the question is what each of those is in the level it lands in: the same
## material or whatever the other palette holds at that number, wires aimed at
## the pasted door or at the other level's own door, names that collide or do
## not, and whether the door is still one door of its own. Then paste twice, paste
## back into the level it came from, and hold the paste against Duplicate, which
## is the other way a copy gets made.
##
## The clipboard file is shared with the user's real editor. What was on it is
## put back at the end.

const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFProto = preload("res://addons/hammerforge/hf_prototype_textures.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

const MAP_PATH := "user://paste-across-levels_import.map"

var _saved_clipboard: PackedByteArray = PackedByteArray()
var _had_clipboard := false


func id() -> String:
	return "paste-across-levels"


func summary() -> String:
	return "copy in one level, paste in another: materials, wires, names, groups and ties"


func run() -> void:
	_keep_clipboard()
	await _a_room_crosses()
	await _an_imported_map_crosses()
	await _paste_against_duplicate()
	_give_back_clipboard()
	if FileAccess.file_exists(MAP_PATH):
		DirAccess.remove_absolute(MAP_PATH)


# ---------------------------------------------------------------------------
# The clipboard belongs to the user's editor too
# ---------------------------------------------------------------------------


func _keep_clipboard() -> void:
	_had_clipboard = FileAccess.file_exists(HFPrefabSystemType.clipboard_path)
	if _had_clipboard:
		_saved_clipboard = FileAccess.get_file_as_bytes(HFPrefabSystemType.clipboard_path)
	note("a clipboard was already there, kept to put back", _had_clipboard)


func _give_back_clipboard() -> void:
	if _had_clipboard:
		var f := FileAccess.open(HFPrefabSystemType.clipboard_path, FileAccess.WRITE)
		if f:
			f.store_buffer(_saved_clipboard)
			f.close()
	elif FileAccess.file_exists(HFPrefabSystemType.clipboard_path):
		DirAccess.remove_absolute(HFPrefabSystemType.clipboard_path)


# ---------------------------------------------------------------------------
# Building the two levels
# ---------------------------------------------------------------------------


func _proto(pattern: String, color: String) -> Material:
	return ResourceLoader.load(HFProto.get_material_path(pattern, color)) as Material


## A material made in the session: no file behind it, which is what the
## inspector's New StandardMaterial3D gives and what a `.map` import mints for a
## texture the project does not have.
func _session_material(label: String, colour: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	mat.albedo_color = colour
	return mat


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _brushes(root: Node3D) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			out.append(child)
	return out


func _entities(root: Node3D) -> Array:
	var out: Array = []
	for child in root.entities_node.get_children():
		if root.is_entity_node(child):
			out.append(child)
	return out


func _face_pointing(brush: Node, direction: Vector3) -> int:
	var best := -1
	var best_dot := -INF
	for i in brush.faces.size():
		var d: float = (brush.faces[i].normal as Vector3).normalized().dot(direction)
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _point_entity(root: Node3D, type: String, node_name: String, authored: String, at: Vector3):
	var e := DraftEntity.new()
	e.entity_type = type
	e.entity_class = type
	e.name = node_name
	root.add_entity(e)
	e.global_position = at
	if authored != "":
		e.set_meta("entity_name", authored)
	return e


## Level A: the room that gets copied. Returns what the checks need to find again.
func _build_a(root: Node3D) -> Dictionary:
	var made := {}
	# Palette: one material from a file, one made in the session.
	root.add_material_to_palette(_proto("checker", "blue"))
	root.add_material_to_palette(_session_material("editor_red", Color(0.9, 0.1, 0.1)))
	made["palette"] = root.material_manager.materials.duplicate()

	var wall = box(root, Vector3(4, 3, 0.25), Vector3(0, 1.5, -3))
	await frame()
	root.assign_material_to_whole_brushes(0, [_bid(wall)])
	var painted := _face_pointing(wall, Vector3(0, 0, 1))
	root.assign_material_to_faces_by_id(_bid(wall), [painted], 1)
	made["wall"] = wall
	made["painted_face"] = painted

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

	# A point entity wired to the door, and one named like something in B.
	var relay = _point_entity(root, "logic_relay", "relay", "relay", Vector3(2, 0.5, 0))
	root.add_entity_output(relay, "OnTrigger", "gate", "Close", "", 0.0, false)
	var lamp = _point_entity(root, "light_point", "lamp", "lamp", Vector3(0, 2.5, -1))
	made["relay"] = relay
	made["lamp"] = lamp

	root.create_visgroup("Doors")
	root.add_selection_to_visgroup("Doors", leaves)
	root.group_selection("Entry", [wall, button])

	var floor_brush = box(root, Vector3(4, 0.25, 4), Vector3(0, -0.125, 0))
	await frame()
	var top := _face_pointing(floor_brush, Vector3.UP)
	root.create_displacement(_bid(floor_brush), top, 3)
	root.set_displacement_elevation(_bid(floor_brush), top, 0.5)
	made["floor"] = floor_brush
	made["floor_top"] = top

	var result = root.create_generator(
		"stairs",
		HFGeneratorSystem.default_settings("stairs"),
		Transform3D(Basis.IDENTITY, Vector3(3, 0, 2))
	)
	made["stairs_ok"] = result != null and result.ok
	await frame()
	return made


## Level B: its own palette in a different order, its own door called "gate", its
## own lamp called "lamp".
func _build_b(root: Node3D) -> Dictionary:
	var made := {}
	root.add_material_to_palette(_proto("hex", "green"))
	root.add_material_to_palette(_proto("brick", "orange"))
	made["palette"] = root.material_manager.materials.duplicate()
	var own_door = box(root, Vector3(1, 2, 0.15), Vector3(20, 1, 0))
	await frame()
	root.tie_brushes_to_entity([_bid(own_door)], "func_door", "gate")
	made["own_door"] = own_door
	made["own_lamp"] = _point_entity(root, "light_point", "lamp", "lamp", Vector3(20, 2.5, 0))
	root.create_visgroup("Lighting")
	await frame()
	return made


# ---------------------------------------------------------------------------
# What the room is in the level it lands in
# ---------------------------------------------------------------------------


func _a_room_crosses() -> void:
	note("-- a furnished room copied in A and pasted into B --")
	var a: Node3D = await fresh_root("LevelA")
	var b: Node3D = await fresh_root("LevelB")
	var made_a: Dictionary = await _build_a(a)
	var made_b: Dictionary = await _build_b(b)
	note("A's stairs built", made_a["stairs_ok"])
	note("A palette", a.material_manager.get_material_names())
	note("B palette", b.material_manager.get_material_names())

	var copied: bool = a.prefab_system.copy_to_clipboard(_brushes(a), _entities(a))
	note("copy_to_clipboard returned", copied)
	var held = a.prefab_system.clipboard_contents()
	note(
		"the clipboard holds",
		(
			"%d brushes, %d entities, material slots recorded %s"
			% [held.brush_infos.size(), held.entity_infos.size(), held.material_slots]
		)
	)

	var b_before: Array = _brushes(b)
	var e_before: Array = _entities(b)
	var pasted: Dictionary = b.prefab_system.paste_from_clipboard()
	await frame()
	var new_brushes: Array = _brushes(b).filter(func(n): return not b_before.has(n))
	var new_entities: Array = _entities(b).filter(func(n): return not e_before.has(n))
	note("pasted into B", "%d brushes, %d entities" % [new_brushes.size(), new_entities.size()])
	note("B palette after the paste", b.material_manager.get_material_names())

	_check_materials(a, b, made_a, new_brushes)
	_check_wires(b, made_b, new_brushes, new_entities)
	_check_names(b)
	_check_memberships(b, new_brushes, new_entities)
	_check_door(a, b, made_a, made_b, new_brushes)
	_check_displacement(b, made_a, new_brushes)
	_check_generator(b, new_brushes)

	note("-- the same clipboard pasted into B a second time --")
	var b_mid: Array = _brushes(b)
	var e_mid: Array = _entities(b)
	b.prefab_system.paste_from_clipboard()
	await frame()
	var second_brushes: Array = _brushes(b).filter(func(n): return not b_mid.has(n))
	var second_entities: Array = _entities(b).filter(func(n): return not e_mid.has(n))
	_check_wires(b, made_b, second_brushes, second_entities)
	_check_names(b)
	var ties := {}
	for brush in _brushes(b):
		if str(brush.get_meta("brush_entity_class", "")) == "func_door":
			ties[str(brush.get_meta("brush_entity_group", ""))] = true
	note("distinct func_door ties in B after two pastes (own + 2 copies)", ties.size())
	if ties.size() != 3:
		flag("two pastes of one door do not make two doors of their own", "%d ties" % ties.size())

	note("-- B edited, then the clipboard pasted back into A --")
	b.add_material_to_palette(_proto("checker", "red"))
	b.delete_brushes_by_id([_bid(made_b["own_door"])])
	await frame()
	var a_before: Array = _brushes(a)
	var ae_before: Array = _entities(a)
	a.prefab_system.paste_from_clipboard()
	await frame()
	var back_brushes: Array = _brushes(a).filter(func(n): return not a_before.has(n))
	var back_entities: Array = _entities(a).filter(func(n): return not ae_before.has(n))
	_check_materials(a, a, made_a, back_brushes)
	_check_wires(a, {}, back_brushes, back_entities)
	_check_names(a)
	note("A palette after pasting into itself", a.material_manager.get_material_names())
	if a.material_manager.materials.size() != (made_a["palette"] as Array).size():
		flag(
			"pasting into the level a piece came from grew its palette",
			"%d slots, was %d" % [a.material_manager.materials.size(), made_a["palette"].size()]
		)
	await drop_root(a)
	await drop_root(b)


## Each pasted face against the material its original wore in A, by what the
## material is rather than by its slot number.
func _check_materials(a: Node3D, dest: Node3D, made_a: Dictionary, pasted: Array) -> void:
	var a_palette: Array = made_a["palette"]
	var wall = made_a["wall"]
	var expected: Array = []
	for f in wall.faces:
		expected.append(a_palette[f.material_idx] if f.material_idx >= 0 else null)
	var copy = null
	for brush in pasted:
		if (
			(brush.size as Vector3).is_equal_approx(wall.size)
			and brush.faces.size() == wall.faces.size()
		):
			copy = brush
	if copy == null:
		flag("the wall did not arrive", "%d brushes pasted" % pasted.size())
		return
	var wrong: Array = []
	for i in copy.faces.size():
		var got = dest.material_manager.get_material(copy.faces[i].material_idx)
		var want = expected[i]
		if got != want:
			wrong.append(
				(
					"face %d wanted '%s', got slot %d = '%s'"
					% [i, _label(want), copy.faces[i].material_idx, _label(got)]
				)
			)
	note("%s: wall faces wearing another material than in A" % dest.name, wrong.size())
	for line in wrong:
		note("  ", line)
	if wrong.is_empty():
		return
	var painted: int = made_a["painted_face"]
	var painted_wrong := false
	for line in wrong:
		if str(line).begins_with("face %d " % painted):
			painted_wrong = true
	# Fixed in #1202: a material with no path is recorded as itself and by name.
	flag(
		"a pasted face wears another material than the one it wore in A",
		(
			(
				"in %s: %s. A's slot 1 is 'editor_red', a StandardMaterial3D with no "
				+ "resource_path, which `HFPrefab._record_material_slots()` records as itself "
				+ "and by name. Painted face wrong: %s"
			)
			% [dest.name, "; ".join(wrong), painted_wrong]
		)
	)


func _label(mat) -> String:
	if mat == null:
		return "<none>"
	if mat.resource_path != "":
		return mat.resource_path.get_file()
	return "%s (no path)" % mat.resource_name


## Where each pasted wire lands: on the pasted copies, on something the level
## already had, or on nothing.
func _check_wires(dest: Node3D, made_dest: Dictionary, pasted_b: Array, pasted_e: Array) -> void:
	var pasted_nodes: Array = pasted_b + pasted_e
	for source in pasted_nodes:
		var outputs: Array = source.get_meta("entity_io_outputs", [])
		for conn in outputs:
			var target := str(conn.get("target_name", ""))
			var hits: Array = dest.find_entities_by_name(target)
			var into_paste := hits.filter(func(n): return pasted_nodes.has(n)).size()
			var outside := hits.size() - into_paste
			note(
				(
					"%s: %s.%s -> '%s' resolves to %d pasted node(s), %d already in the level"
					% [
						dest.name,
						source.name,
						conn.get("output_name", ""),
						target,
						into_paste,
						outside
					]
				)
			)
			if hits.is_empty():
				flag("a pasted wire aims at nothing", "%s -> %s" % [source.name, target])
			elif outside > 0:
				flag(
					"a pasted wire also reaches an entity the level already had",
					"%s -> '%s' hits %d of the level's own" % [source.name, target, outside]
				)
			elif into_paste == 0:
				flag("a pasted wire missed the pasted door", "%s -> %s" % [source.name, target])


## Every address in the level answered to by one entity, a door's leaves counting
## as one.
func _check_names(dest: Node3D) -> void:
	var index: Dictionary = dest.entity_system.build_name_index()
	var shared: Array = []
	for address in index:
		var owners := {}
		for node in index[address]:
			var tie := str(node.get_meta("brush_entity_group", ""))
			owners[tie if tie != "" else str(node.get_instance_id())] = true
		if owners.size() > 1:
			shared.append("%s x%d" % [address, owners.size()])
	note("%s: addresses answered to by more than one entity" % dest.name, shared)
	if not shared.is_empty():
		flag("a paste left two entities answering to one name", "%s: %s" % [dest.name, shared])


func _check_memberships(dest: Node3D, pasted_b: Array, pasted_e: Array) -> void:
	var with_vg := 0
	var with_group := 0
	for node in pasted_b + pasted_e:
		if not (node.get_meta("visgroups", PackedStringArray()) as PackedStringArray).is_empty():
			with_vg += 1
		if str(node.get_meta("group_id", "")) != "":
			with_group += 1
	note(
		"pasted nodes in a visgroup / in a group",
		"%d / %d (the capture drops both on purpose, hf_prefab.gd:80-91)" % [with_vg, with_group]
	)
	note("%s visgroups after the paste" % dest.name, dest.get_visgroup_names())


func _check_door(
	a: Node3D, b: Node3D, made_a: Dictionary, made_b: Dictionary, pasted: Array
) -> void:
	var a_tie := str(made_a["leaves"][0].get_meta("brush_entity_group", ""))
	var b_tie := str(made_b["own_door"].get_meta("brush_entity_group", ""))
	var leaf_ties := {}
	var leaf_names := {}
	for brush in pasted:
		if str(brush.get_meta("brush_entity_class", "")) == "func_door":
			leaf_ties[str(brush.get_meta("brush_entity_group", ""))] = true
			leaf_names[str(brush.get_meta("entity_name", ""))] = true
	note("pasted door leaves: ties %s, names %s" % [leaf_ties.keys(), leaf_names.keys()])
	if leaf_ties.size() != 1:
		flag("the pasted door is not one door", "%d ties across its leaves" % leaf_ties.size())
	elif leaf_ties.has(a_tie) or leaf_ties.has(b_tie):
		flag("the pasted door shares a tie with an existing door", leaf_ties.keys())


func _check_displacement(b: Node3D, made_a: Dictionary, pasted: Array) -> void:
	var src = made_a["floor"]
	var top: int = made_a["floor_top"]
	var src_disp = src.faces[top].displacement
	for brush in pasted:
		if not (brush.size as Vector3).is_equal_approx(src.size):
			continue
		var disp = brush.faces[top].displacement if top < brush.faces.size() else null
		note(
			"pasted floor displacement",
			(
				"present %s, power %s, elevation %s (A: power %s, elevation %s)"
				% [
					disp != null,
					disp.power if disp else "-",
					disp.elevation if disp else "-",
					src_disp.power,
					src_disp.elevation
				]
			)
		)
		if disp == null:
			flag("a pasted displacement lost its sculpt")
		elif (
			disp.power != src_disp.power or not is_equal_approx(disp.elevation, src_disp.elevation)
		):
			flag("a pasted displacement came back different")
		return
	flag("the displaced floor did not arrive")


func _check_generator(b: Node3D, pasted: Array) -> void:
	var tagged := 0
	for brush in pasted:
		if str(brush.get_meta("hf_generator_id", "")) != "":
			tagged += 1
	note(
		"pasted stair pieces still tagged as a structure / structures in B",
		"%d / %d (paste is geometry, hf_prefab_system.gd:869-871)" % [tagged, b.generator_count()]
	)
	if tagged > 0 and b.generator_count() == 0:
		flag("pasted pieces name a structure the level has no record of", "%d pieces" % tagged)


# ---------------------------------------------------------------------------
# A `.map` import's placeholder materials, which are the common session-made kind
# ---------------------------------------------------------------------------


## Import a `.map` whose textures the project does not have: each becomes a
## placeholder with no path. Copy a brush of it into a level whose palette is
## already populated.
func _an_imported_map_crosses() -> void:
	note("-- a brush from an imported .map, pasted into a level with its own palette --")
	var text := (
		'{\n"classname" "worldspawn"\n{\n'
		+ "( 0 0 0 ) ( 0 64 0 ) ( 64 0 0 ) STONE_WALL 0 0 0 1 1\n"
		+ "( 0 0 64 ) ( 64 0 64 ) ( 0 64 64 ) STONE_WALL 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 64 0 0 ) ( 0 0 64 ) STONE_WALL 0 0 0 1 1\n"
		+ "( 0 64 0 ) ( 0 64 64 ) ( 64 64 0 ) STONE_WALL 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 0 0 64 ) ( 0 64 0 ) STONE_WALL 0 0 0 1 1\n"
		+ "( 64 0 0 ) ( 64 64 0 ) ( 64 0 64 ) STONE_WALL 0 0 0 1 1\n"
		+ "}\n}\n"
	)
	HFVibe.write_text(MAP_PATH, text)
	var a: Node3D = await fresh_root("ImportedA")
	var imported: int = a.import_map(MAP_PATH)
	await frame()
	note("import_map returned", imported)
	note("imported palette", a.material_manager.get_material_names())
	var b: Node3D = await fresh_root("PopulatedB")
	b.add_material_to_palette(_proto("hex", "green"))
	await frame()
	if _brushes(a).is_empty():
		flag("the .map imported no brush")
		return
	a.prefab_system.copy_to_clipboard(_brushes(a), [])
	var before: Array = _brushes(b)
	b.prefab_system.paste_from_clipboard()
	await frame()
	var pasted: Array = _brushes(b).filter(func(n): return not before.has(n))
	if pasted.is_empty():
		flag("the imported brush did not paste")
		return
	var slots := {}
	for f in pasted[0].faces:
		slots[_label(b.material_manager.get_material(f.material_idx))] = true
	note("what the pasted STONE_WALL faces wear in B", slots.keys())
	note("their .map texture name", pasted[0].faces[0].map_texture)
	var out_path := "user://paste-across-levels_b.map"
	b.export_map(out_path)
	var exported := FileAccess.get_file_as_string(out_path)
	var names_stone := exported.count("STONE_WALL")
	note("B's .map export: faces naming STONE_WALL", names_stone)
	DirAccess.remove_absolute(out_path)
	# Fixed in #1202: the placeholder crosses as itself, so B's palette and B's
	# export both say STONE_WALL.
	if not slots.has("STONE_WALL (no path)") or names_stone != pasted[0].faces.size():
		flag(
			"a brush from an imported .map pasted into another level lost its texture name",
			(
				(
					"STONE_WALL is a placeholder minted by `_mint_palette_slot()`: resource_name "
					+ "set, no path. The pasted faces are on slot %d and wear %s in B, and B's .map "
					+ "export names STONE_WALL on %d of %d faces"
				)
				% [
					pasted[0].faces[0].material_idx,
					slots.keys(),
					names_stone,
					pasted[0].faces.size()
				]
			)
		)
	await drop_root(a)
	await drop_root(b)


# ---------------------------------------------------------------------------
# Paste against Duplicate, inside one level
# ---------------------------------------------------------------------------


## What the editor's Duplicate (`plugin_edit_actions.duplicate_selected`) makes of
## the same room, built the way it builds it, against what Copy then Paste makes
## in the same level.
func _paste_against_duplicate() -> void:
	note("-- Duplicate against Copy+Paste, in one level --")
	var root: Node3D = await fresh_root("OneLevel")
	var made: Dictionary = await _build_a(root)
	var originals_b: Array = _brushes(root)
	var originals_e: Array = _entities(root)

	# Duplicate, as the plugin does it.
	var brush_infos: Array = []
	var entity_infos: Array = []
	var step: float = root.grid_snap
	for node in originals_b:
		var info: Dictionary = root.build_duplicate_info(node, Vector3(step, 0, 0))
		if not info.is_empty():
			brush_infos.append(info)
	for node in originals_e:
		var info: Dictionary = root.build_duplicate_entity_info(node, Vector3(step, 0, 0))
		if not info.is_empty():
			entity_infos.append(info)
	HFBrushEntity.fresh_identities(brush_infos, [], root.entity_system)
	root.create_managed_duplicates(brush_infos, entity_infos)
	await frame()
	var dup_b: Array = _brushes(root).filter(func(n): return not originals_b.has(n))
	var dup_e: Array = _entities(root).filter(func(n): return not originals_e.has(n))

	var after_dup_b: Array = _brushes(root)
	var after_dup_e: Array = _entities(root)
	root.prefab_system.copy_to_clipboard(originals_b, originals_e)
	root.prefab_system.paste_from_clipboard(Vector3(0, 0, 10))
	await frame()
	var paste_b: Array = _brushes(root).filter(func(n): return not after_dup_b.has(n))
	var paste_e: Array = _entities(root).filter(func(n): return not after_dup_e.has(n))

	note("duplicate made", "%d brushes, %d entities" % [dup_b.size(), dup_e.size()])
	note("paste made", "%d brushes, %d entities" % [paste_b.size(), paste_e.size()])
	for pair in [["duplicate", dup_b + dup_e], ["paste", paste_b + paste_e]]:
		var vg := 0
		var grp := 0
		var gen := 0
		var wires_to_originals := 0
		for node in pair[1]:
			if not (
				(node.get_meta("visgroups", PackedStringArray()) as PackedStringArray).is_empty()
			):
				vg += 1
			if str(node.get_meta("group_id", "")) != "":
				grp += 1
			if str(node.get_meta("hf_generator_id", "")) != "":
				gen += 1
			for conn in node.get_meta("entity_io_outputs", []):
				var hits: Array = root.find_entities_by_name(str(conn.get("target_name", "")))
				if hits.any(func(n): return originals_b.has(n) or originals_e.has(n)):
					wires_to_originals += 1
		note(
			(
				"%s: in a visgroup %d, in a group %d, structure-tagged %d, wires to the originals %d"
				% [pair[0], vg, grp, gen, wires_to_originals]
			)
		)
	note(
		"wires",
		(
			"a duplicate keeps firing at the original door on purpose (plugin_edit_actions.gd:166), "
			+ "a paste fires at its own copy -- two documented rules, not a defect"
		)
	)
	_check_names(root)
	await drop_root(root)
