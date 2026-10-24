extends GutTest

## Every cell of the portability page's table of what each format keeps (#1706).
##
## `docs/HammerForge_Data_Portability.md` opens with a table: a row for each
## thing a level holds, a column for each file it goes through, and in each cell
## Kept, Kept as (with a note), Lost or Not applicable. These build one level that
## holds every row, take it through each format and back, and hold each cell to
## what came back, so a change to an exporter that the table does not follow
## fails here, naming the cell.
##
## Kept is a count that comes back whole and Lost is one that comes back as none,
## both read by `HFFormatCensus`. Kept as is a check of its own, in `_kept_as()`:
## a `.map` keeps texture settings as its own texture axes, so the count of faces
## with settings changes while each face still draws the same. The `.glb` is the
## bake and is not read back into a level, so each of its cells is a check on the
## file against the bake that made it. Not applicable has nothing to check beyond
## the export not counting it as left out.

const FullLevel = preload("res://tests/support/full_feature_level.gd")
const HFFormatCensus = preload("res://addons/hammerforge/hf_format_census.gd")
const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFHiddenFaces = preload("res://addons/hammerforge/hf_hidden_faces.gd")
const MapIO = preload("res://addons/hammerforge/map_io.gd")
const HFMapAdapterType = preload("res://addons/hammerforge/map_adapters/hf_map_adapter.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const DOC := "res://docs/HammerForge_Data_Portability.md"
const DIR := "user://hf_test_format_table/"
const COLUMNS := [".hflevel", ".tscn", ".map", ".glb", ".hfprefab"]

const KEPT := "Kept"
const KEPT_AS := "Kept as"
const LOST := "Lost"
const NOT_APPLICABLE := "Not applicable"

var _prefab_dir := ""


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_prefab_dir = HFPrefabSystemType.prefab_dir
	HFPrefabSystemType.prefab_dir = DIR


func after_each() -> void:
	HFPrefabSystemType.prefab_dir = _prefab_dir


func after_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


# ===========================================================================
# The table
# ===========================================================================


## The table on the page, as {row key: {format: cell}}, and what in it did not
## read, in `problems`.
func _table(problems: PackedStringArray = []) -> Dictionary:
	var text := FileAccess.get_file_as_string(DOC)
	var keys := {}
	for row in HFFormatCensus.ROWS:
		keys[str(row[2])] = str(row[0])
	var out := {}
	var columns: Array = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("|"):
			if not columns.is_empty():
				break
			continue
		var cells: Array = []
		for cell in trimmed.trim_prefix("|").trim_suffix("|").split("|"):
			cells.append(cell.strip_edges().replace("`", "").replace("**", ""))
		if columns.is_empty():
			if cells.size() > 1 and cells[1] == COLUMNS[0]:
				columns = cells.slice(1)
			continue
		if str(cells[0]).begins_with("---"):
			continue
		if not keys.has(cells[0]):
			problems.append("the table has a row %s that the census does not" % cells[0])
			continue
		var row := {}
		for i in columns.size():
			row[columns[i]] = cells[i + 1] if i + 1 < cells.size() else ""
		out[keys[cells[0]]] = row
	if columns != COLUMNS:
		problems.append("the table's columns are %s, not %s" % [columns, COLUMNS])
	return out


static func _kind(cell: String) -> String:
	if cell == KEPT or cell == LOST or cell == NOT_APPLICABLE:
		return cell
	if cell.begins_with(KEPT_AS + " "):
		return KEPT_AS
	return ""


static func _label(key: String) -> String:
	for row in HFFormatCensus.ROWS:
		if row[0] == key:
			return str(row[2]).to_lower()
	return key


func test_the_table_has_every_row_and_column_and_says_one_thing_in_each_cell():
	var problems: PackedStringArray = []
	var table := _table(problems)
	for row in HFFormatCensus.ROWS:
		if not table.has(row[0]):
			problems.append("the table has no row %s" % row[2])
			continue
		for format in COLUMNS:
			var cell := str(table[row[0]].get(format, ""))
			if _kind(cell) == "":
				problems.append("%s: %s reads %s" % [format, _label(row[0]), cell])
	assert_eq(problems, PackedStringArray(), "\n".join(problems))


## What an export names as left out is the Lost cells of its column.
func test_the_lost_cells_are_what_each_export_names_as_left_out():
	var table := _table()
	for format in COLUMNS:
		var lost: Array = []
		for row in HFFormatCensus.ROWS:
			if table.has(row[0]) and _kind(str(table[row[0]][format])) == LOST:
				lost.append(row[0])
		assert_eq(
			lost,
			HFFormatCensus.LOSES.get(format, []),
			"%s: the table's Lost cells and HFFormatCensus.LOSES" % format
		)


# ===========================================================================
# The level
# ===========================================================================


func _level() -> LevelRoot:
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## The full feature level, with a piece of every row it lacks inside its cordon,
## so the bake has them too.
func _build() -> LevelRoot:
	var level := _level()
	await FullLevel.fill(level, get_tree())
	var cylinder = level.create_brush_from_info(
		{
			"shape": level.BrushShape.CYLINDER,
			"size": Vector3(2, 3, 2),
			"center": Vector3(16, 1.5, 6)
		}
	)
	var box = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 4, 4), "center": Vector3(11, 2, 5)}
	)
	level.brush_system._ensure_faces(box)
	var faces: Array = box.get_faces()
	var layer = FaceData.PaintLayer.new()
	layer.ensure_weight_image(Vector2i(16, 16))
	faces[0].paint_layers.append(layer)
	level.create_displacement(str(box.brush_id), 2, 2)
	faces[1].smoothing_group = 2
	faces[1].uv_scale = Vector2(2, 2)
	faces[3].uv_group = 5
	faces[4].uv_group = 5
	faces[5].ensure_custom_uvs()
	faces[5].custom_uvs[0] += Vector2(0.25, 0.0)
	var lamp = (
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "lamp",
				"entity_type": "light",
				"properties": {"targetname": "lamp", "brightness": 300},
				"transform": Transform3D(Basis.IDENTITY, Vector3(11, 4.5, 5)),
			}
		)
	)
	level.add_entity_output(lamp, "OnTrigger", "lamp", "TurnOff")
	level.tie_brushes_to_entity([str(cylinder.brush_id)], "func_detail")
	level.group_selection("pair", [box, cylinder])
	var piece = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 1, 1), "center": Vector3(6, 0.5, 6)}
	)
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [piece], []
	)
	prefab.save_to_file(DIR + "piece.hfprefab")
	level.prefab_system.place(
		prefab, DIR + "piece.hfprefab", Transform3D(Basis.IDENTITY, Vector3(3, 0, 6)), "base", true
	)
	level.bake_collision_mode = 1
	# A pass the fixture's cuts started holds a combiner in the level for a frame
	# or two. The editor gives it no owner, and `_own()` would, so it would go
	# into the scene with every brush it points at.
	for _i in 30:
		await get_tree().process_frame
		if not level.get_children().any(func(c): return c is CSGCombiner3D):
			break
	return level


func _counts(level: Node) -> Dictionary:
	var out := {}
	for row in HFFormatCensus.ROWS:
		out[row[0]] = HFFormatCensus.count(level, row[0])
	return out


## So that no Kept cell holds for want of anything to keep.
func test_the_level_holds_every_row():
	var level := await _build()
	var counts := _counts(level)
	for key in counts:
		assert_gt(counts[key], 0, "fixture: the level holds %s" % _label(key))


# ===========================================================================
# Through each format and back
# ===========================================================================


func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return
		await get_tree().process_frame


func _through_hflevel(level: LevelRoot) -> LevelRoot:
	var path := DIR + "level.hflevel"
	assert_eq(level.save_hflevel(path, true), OK, "the .hflevel saves")
	await _finish_saving(level)
	var again := _level()
	assert_true(again.load_hflevel(path), "the .hflevel loads")
	await get_tree().process_frame
	return again


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


## Ctrl+S, then the scene opened again from disk with the cache ignored.
func _through_tscn(level: LevelRoot) -> LevelRoot:
	var path := DIR + "level.tscn"
	_own(level)
	level.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed := PackedScene.new()
	assert_eq(packed.pack(level), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, path), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var again := loaded.instantiate() as LevelRoot
	again.hflevel_autosave_enabled = false
	add_child_autoqfree(again)
	await get_tree().process_frame
	return again


func _through_map(level: LevelRoot) -> LevelRoot:
	var path := DIR + "level.map"
	assert_eq(level.export_map(path), OK, "the .map exports")
	# Into a level with the project's materials, as a round trip is: a `.map`
	# names its textures and carries no sizes, so its texture scale is read
	# against the textures the project has.
	var again := _level()
	again.set_materials(level.material_manager.materials.duplicate())
	assert_eq(again.import_map(path), OK, "the .map imports")
	await get_tree().process_frame
	return again


## Every brush and entity saved as one prefab, and that placed in an empty level.
func _through_prefab(level: LevelRoot) -> LevelRoot:
	var path := DIR + "all.hfprefab"
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system,
		level.entity_system,
		HFFormatCensus._brushes(level) + HFFormatCensus._cuts(level),
		HFFormatCensus._entities(level)
	)
	assert_eq(prefab.save_to_file(path), OK, "the prefab saves")
	var loaded = HFPrefabType.load_from_file(path)
	var again := _level()
	loaded.instantiate(again.brush_system, again.entity_system, again, Vector3.ZERO)
	await get_tree().process_frame
	return again


## The bake, and the `.glb` exported from it read back as a scene.
func _through_glb(level: LevelRoot) -> Dictionary:
	var path := DIR + "level.glb"
	assert_true(await level.bake(), "the level bakes")
	assert_eq(level.export_baked_gltf(path), OK, "the .glb exports")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(doc.append_from_file(ProjectSettings.globalize_path(path), state), OK)
	var scene := doc.generate_scene(state)
	add_child_autoqfree(scene)
	return {"bake": level.baked_container, "glb": scene}


# ===========================================================================
# The cells
# ===========================================================================


## Each cell of `format`'s column held to what came back, as a list of the
## cells that did not hold.
func _check_column(format: String, before: LevelRoot, after: Variant) -> PackedStringArray:
	var table := _table()
	var wrong: PackedStringArray = []
	var counts_before := _counts(before)
	var counts_after: Dictionary = _counts(after) if after is LevelRoot else {}
	for row in HFFormatCensus.ROWS:
		var key: String = row[0]
		if not table.has(key):
			continue
		var cell := str(table[key][format])
		var label := _label(key)
		var said := ""
		match _kind(cell):
			KEPT:
				if format == ".glb":
					said = _glb(key, cell, after)
				elif counts_after[key] != counts_before[key]:
					said = "%d of %d came back" % [counts_after[key], counts_before[key]]
			LOST:
				if format == ".glb":
					said = _glb(key, cell, after)
				elif counts_after[key] != 0:
					said = "%d of %d came back" % [counts_after[key], counts_before[key]]
			KEPT_AS:
				said = (
					_glb(key, cell, after)
					if format == ".glb"
					else _kept_as(format, key, before, after)
				)
			NOT_APPLICABLE:
				if (HFFormatCensus.LOSES.get(format, []) as Array).has(key):
					said = "the export names it as left out"
		if said != "":
			wrong.append("%s: %s said %s, but %s" % [format, label, cell, said])
	return wrong


func test_the_hflevel_column():
	var level := await _build()
	var wrong := _check_column(".hflevel", level, await _through_hflevel(level))
	assert_eq(wrong, PackedStringArray(), "\n".join(wrong))


func test_the_tscn_column():
	var level := await _build()
	var wrong := _check_column(".tscn", level, await _through_tscn(level))
	assert_eq(wrong, PackedStringArray(), "\n".join(wrong))


func test_the_map_column():
	var level := await _build()
	var wrong := _check_column(".map", level, await _through_map(level))
	assert_eq(wrong, PackedStringArray(), "\n".join(wrong))


func test_the_glb_column():
	var level := await _build()
	var wrong := _check_column(".glb", level, await _through_glb(level))
	assert_eq(wrong, PackedStringArray(), "\n".join(wrong))


func test_the_hfprefab_column():
	var level := await _build()
	var wrong := _check_column(".hfprefab", level, await _through_prefab(level))
	assert_eq(wrong, PackedStringArray(), "\n".join(wrong))


## A Kept as cell of a format read back into a level: "" when it holds, or what
## did not.
func _kept_as(format: String, key: String, before: LevelRoot, after: LevelRoot) -> String:
	match [format, key]:
		[".map", "uv_settings"]:
			return _faces_draw_the_same(before, after)
		[".map", "hidden_faces"]:
			var text := FileAccess.get_file_as_string(DIR + "level.map")
			if not text.contains(" %s " % HFHiddenFaces.MAP_NAME):
				return "the file names no %s texture" % HFHiddenFaces.MAP_NAME
			var back := HFFormatCensus.count(after, key)
			var had := HFFormatCensus.count(before, key)
			return "" if back == had else "%d of %d came back" % [back, had]
		[".map", "entity_properties"]:
			return _properties_as_text(before, after)
	return "nothing here checks it"


## Each face with texture settings draws the same after the round trip: at each
## corner the UVs differ by the same whole number of repeats, if at all.
func _faces_draw_the_same(before: LevelRoot, after: LevelRoot) -> String:
	var others: Array = []
	for brush in HFFormatCensus._brushes(after):
		for face in brush.faces:
			if face != null:
				others.append(_world_face(brush, face))
	var checked := 0
	var off: PackedStringArray = []
	for brush in HFFormatCensus._brushes(before):
		for face in brush.faces:
			if face == null or not HFFormatCensus._laid_on(face):
				continue
			checked += 1
			var mine := _world_face(brush, face)
			var other := _same_face(others, mine)
			if other.is_empty():
				off.append(
					"%s face %d came back as no face" % [brush.brush_id, brush.faces.find(face)]
				)
				continue
			var why := _same_uvs(mine, other)
			if why != "":
				off.append("%s face %d %s" % [brush.brush_id, brush.faces.find(face), why])
	if checked == 0:
		return "no face had texture settings to check"
	if off.is_empty():
		return ""
	return "%d of %d faces draw otherwise, as %s" % [off.size(), checked, off[0]]


static func _world_face(brush: Node3D, face: Variant) -> Dictionary:
	var corners: Array = []
	for v in face.local_verts:
		corners.append(brush.global_transform * v)
	var normal := Vector3.ZERO
	if corners.size() >= 3:
		normal = (corners[2] - corners[0]).cross(corners[1] - corners[0]).normalized()
	var centre := Vector3.ZERO
	for c in corners:
		centre += c
	return {
		"corners": corners,
		"uvs": face.shown_uvs(),
		"normal": normal,
		"centre": centre / maxf(corners.size(), 1.0),
	}


static func _same_face(faces: Array, mine: Dictionary) -> Dictionary:
	for other in faces:
		if (other["normal"] as Vector3).dot(mine["normal"]) < 0.999:
			continue
		if (other["centre"] as Vector3).distance_to(mine["centre"]) < 0.02:
			return other
	return {}


static func _same_uvs(mine: Dictionary, other: Dictionary) -> String:
	var shift = null
	for i in (mine["corners"] as Array).size():
		var corner: Vector3 = mine["corners"][i]
		var j := -1
		for k in (other["corners"] as Array).size():
			if (other["corners"][k] as Vector3).distance_to(corner) < 0.02:
				j = k
		if j < 0:
			return "has no corner at %s" % corner
		var delta: Vector2 = other["uvs"][j] - mine["uvs"][i]
		if shift == null:
			shift = delta
			if (
				not delta.is_equal_approx(delta.round())
				and delta.distance_to(delta.round()) > 0.002
			):
				return "is shifted %s, not by whole repeats" % delta
		elif delta.distance_to(shift) > 0.002:
			return "is turned or stretched: %s at one corner, %s at another" % [shift, delta]
	return ""


## Each point entity keeps every key but the ones a `.map` writes as its own
## lines, each value as the text the adapter writes for it: a colour as three
## numbers, a bool as 1 or 0.
func _properties_as_text(before: LevelRoot, after: LevelRoot) -> String:
	var writer := HFMapAdapterType.new()
	var mine := HFFormatCensus._point_entities(before)
	var theirs := HFFormatCensus._point_entities(after)
	if mine.size() != theirs.size():
		return "%d of %d entities came back" % [theirs.size(), mine.size()]
	for i in mine.size():
		var had: Dictionary = HFFormatCensus.HFEntityPropUtils.get_entity_data(mine[i])
		var has: Dictionary = HFFormatCensus.HFEntityPropUtils.get_entity_data(theirs[i])
		for prop in had:
			# A key with no value is no line in a `.map`.
			if prop in MapIO.RESERVED_ENTITY_KEYS or writer.format_property_value(had[prop]) == "":
				continue
			if not has.has(prop):
				return "%s lost %s" % [mine[i].name, prop]
			if writer.format_property_value(has[prop]) != writer.format_property_value(had[prop]):
				return "%s has %s as %s, not %s" % [mine[i].name, prop, has[prop], had[prop]]
	return ""


# ===========================================================================
# The .glb against the bake
# ===========================================================================


## A `.glb` cell: "" when it holds, or what did not.
func _glb(key: String, cell: String, trip: Dictionary) -> String:
	var bake: Node = trip["bake"]
	var glb: Node = trip["glb"]
	match key:
		"brushes", "shapes", "cuts", "sculpts", "floor_paint", "hidden_faces":
			var had := _triangles(bake)
			var has := _triangles(glb)
			if had == 0:
				return "the bake made no triangles"
			if has != had:
				return "it holds %d of the bake's %d triangles" % [has, had]
			if key == "hidden_faces" and _surfaces(glb).any(_is_hidden_look):
				return "a surface carries the Hidden look"
			return ""
		"uv_settings", "custom_uvs":
			return _same_vertices(bake, glb, Mesh.ARRAY_TEX_UV, "UVs")
		"smoothing":
			return _same_vertices(bake, glb, Mesh.ARRAY_NORMAL, "normals")
		"face_materials":
			var had := _surfaces(bake).filter(func(m): return m != null and m.resource_name != "")
			var names: Array = _surfaces(glb).map(func(m): return m.resource_name if m else "")
			for material in had:
				if not names.has(material.resource_name):
					return "it has no %s" % material.resource_name
			return ""
		"paint":
			var had := _surfaces(bake).filter(_textured).size()
			var has := _surfaces(glb).filter(_textured).size()
			if had == 0:
				return "the bake has no painted surface"
			return "" if has >= had else "%d of %d textured surfaces arrived" % [has, had]
		"brush_entities":
			var nonstructural := bake.get_node_or_null("Nonstructural")
			if nonstructural == null or nonstructural.get_child_count() == 0:
				return "the bake has no brush entity"
			for child in nonstructural.get_children():
				if glb.find_child(str(child.name), true, false) == null:
					return "it has no %s" % child.name
			return ""
		"entities", "entity_properties", "wires", "notes":
			if cell != LOST:
				return "nothing here checks it"
			for node in _nodes(glb):
				if not node.get_meta_list().is_empty():
					return "%s carries %s" % [node.name, node.get_meta_list()]
				if node.get_script() != null:
					return "%s carries a script" % node.name
			return ""
	return "nothing here checks it"


static func _nodes(top: Node) -> Array:
	var out: Array = []
	var stack: Array = [top]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		stack.append_array(node.get_children())
	return out


static func _meshes(top: Node) -> Array:
	return _nodes(top).filter(
		func(n): return n is MeshInstance3D and (n as MeshInstance3D).mesh != null
	)


static func _triangles(top: Node) -> int:
	var many := 0
	for node in _meshes(top):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var index = arrays[Mesh.ARRAY_INDEX]
			if index is PackedInt32Array and not (index as PackedInt32Array).is_empty():
				many += (index as PackedInt32Array).size() / 3
			else:
				many += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return many


static func _surfaces(top: Node) -> Array:
	var out: Array = []
	for node in _meshes(top):
		for s in (node as MeshInstance3D).mesh.get_surface_count():
			out.append((node as MeshInstance3D).get_active_material(s))
	return out


static func _textured(material: Variant) -> bool:
	return material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null


static func _is_hidden_look(material: Variant) -> bool:
	return material != null and HFHiddenFaces.is_hidden_material(material)


## Each baked mesh's `array` against its `.glb` mesh, vertex by vertex: a UV
## within a thousandth, a normal within half a degree, as glTF keeps it, a
## direction of length one. "" when they match.
static func _same_vertices(bake: Node, glb: Node, array: int, what: String) -> String:
	var theirs := _meshes(glb)
	var compared := 0
	for node in _meshes(bake):
		var other: MeshInstance3D = _counterpart(bake, node, glb, theirs)
		if other == null:
			return "it has no mesh like %s" % bake.get_path_to(node)
		theirs.erase(other)
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var had = mesh.surface_get_arrays(s)[array]
			var has = other.mesh.surface_get_arrays(s)[array]
			if had == null or has == null or had.size() != has.size():
				return "%s surface %d has other %s" % [node.name, s, what]
			for i in had.size():
				var off: float = (
					rad_to_deg(had[i].normalized().angle_to(has[i].normalized()))
					if array == Mesh.ARRAY_NORMAL
					else had[i].distance_to(has[i]) * 1000.0
				)
				if off > 0.5 if array == Mesh.ARRAY_NORMAL else off > 1.0:
					return (
						"%s surface %d has %s at a corner, not %s" % [node.name, s, has[i], had[i]]
					)
				compared += 1
	return "" if compared > 0 else "the bake has no %s" % what


## The `.glb` mesh among `candidates` that `node` became: under the same parent,
## with the same surfaces of the same sizes. Not by name alone, because glTF
## makes every node name unique and a second `BakedMesh_0` comes back renamed.
static func _counterpart(bake: Node, node: Node, glb: Node, candidates: Array) -> Node:
	var mesh: Mesh = (node as MeshInstance3D).mesh
	var parent := str(bake.get_path_to(node.get_parent()))
	for other in candidates:
		if str(glb.get_path_to(other.get_parent())) != parent:
			continue
		var theirs: Mesh = (other as MeshInstance3D).mesh
		if theirs.get_surface_count() != mesh.get_surface_count():
			continue
		var alike := true
		for s in mesh.get_surface_count():
			if theirs.surface_get_array_len(s) != mesh.surface_get_array_len(s):
				alike = false
				break
		if alike:
			return other
	return null


# ===========================================================================
# What the exports say
# ===========================================================================


func _said(level: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for i in get_signal_emit_count(level, "user_message"):
		out.append(str(get_signal_parameters(level, "user_message", i)[0]))
	return out


func test_each_export_names_what_it_left_out():
	var level := await _build()
	watch_signals(level)
	assert_eq(level.export_map(DIR + "said.map"), OK)
	assert_true(await level.bake(), "the level bakes")
	assert_eq(level.export_baked_gltf(DIR + "said.glb"), OK)
	var said := _said(level)
	for format in [".map", ".glb"]:
		var expected := "%s export %s" % [format, HFFormatCensus.left_out(level, format)]
		assert_has(said, expected, "the %s export says what it left out" % format)
	assert_string_contains(HFFormatCensus.left_out(level, ".map"), "2 cordons")


## A prefab is saved from a selection, and names what of the selection it left
## out rather than what of the level.
func test_a_prefab_names_what_of_its_selection_it_left_out():
	var level := _level()
	var kept = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)}
	)
	var other = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(2, 2, 2), "center": Vector3(5, 1, 0)}
	)
	level.create_visgroup("walls")
	level.visgroup_system.add_to_visgroup(kept, "walls")
	level.create_visgroup("elsewhere")
	level.visgroup_system.add_to_visgroup(other, "elsewhere")
	level.cordon_enabled = true
	watch_signals(level)
	assert_ne(level.prefab_system.quick_save_prefab([kept], [], "piece"), "", "the prefab saves")
	assert_has(_said(level), "Prefab 'piece' left out 1 visgroup", "its own visgroup only")
