@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Hidden faces (#1847) promise one thing on every path: the face is left out of
## the baked mesh and its lightmap, and kept in the collision. The suite checks
## the face path, the CSG path and face materials off. This asks every other way
## a level is baked -- merged meshes, chunks, the atlas, the collision modes, Bake
## Selected, Bake Changed, and each brush entity class a floor can be tied to --
## and then what the operations that rebuild a brush's faces (merge, clip, hollow,
## carve, duplicate, arrays, a `.map` and a glTF) keep of it.
##
## And Face Direction (#1876), which swaps the look a brush draws with while it is
## on: whether any of that look reaches a bake made while it is on.

const HFHiddenFaces = preload("res://addons/hammerforge/hf_hidden_faces.gd")
const HFFaceDirection = preload("res://addons/hammerforge/hf_face_direction.gd")

## The layer the bake puts its collision on, away from the drafts' pick layer.
const BAKE_LAYER_INDEX := 9
const MAP_PATH := "user://vibe_hidden_faces.map"
const GLB_PATH := "user://vibe_hidden_faces.glb"

var _case := 0


func id() -> String:
	return "hidden-faces"


func summary() -> String:
	return "hidden faces through every bake path and every face-rebuilding operation, and face direction"


func expected_issues() -> Array[int]:
	return [2002]


func run() -> void:
	await _every_bake_path()
	await _the_operations()
	await _map_and_gltf()
	await _face_direction_and_the_bake()
	for path in [MAP_PATH, GLB_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## A new place in space for each case, so one case's collision is never another's.
func _next_origin() -> Vector3:
	_case += 1
	return Vector3(_case * 60.0, 0.0, 0.0)


func _box(root: Node3D, brush_id: String, size: Vector3, centre: Vector3, extra := {}) -> Node:
	var info := {"shape": 0, "size": size, "center": centre, "brush_id": brush_id}
	info.merge(extra, true)
	return root.create_brush_from_info(info)


static func _face_facing(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(normal) > 0.99:
			return i
	return -1


func _hide(root: Node3D, brush: Node, normal: Vector3) -> void:
	root.set_faces_hidden({str(brush.brush_id): [_face_facing(brush, normal)]}, true)


static func _meshes(node: Node, out: Array) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)
	return out


## The area of drawn triangles lying on y = `height` within `half` of `centre`.
static func _drawn_area_at(node: Node, height: float, centre: Vector3, half: float) -> float:
	var area := 0.0
	if node == null:
		return area
	for mesh_node in _meshes(node, []):
		var mesh: Mesh = mesh_node.mesh
		var place: Transform3D = mesh_node.global_transform
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var corners: Array = []
			if indices.is_empty():
				for i in verts.size():
					corners.append(i)
			else:
				corners = Array(indices)
			for i in range(0, corners.size() - 2, 3):
				var a: Vector3 = place * verts[corners[i]]
				var b: Vector3 = place * verts[corners[i + 1]]
				var c: Vector3 = place * verts[corners[i + 2]]
				var on := true
				for p in [a, b, c]:
					if absf(p.y - height) > 0.001:
						on = false
					if absf(p.x - centre.x) > half + 0.001 or absf(p.z - centre.z) > half + 0.001:
						on = false
				if on:
					area += (b - a).cross(c - a).length() * 0.5
	return area


static func _wears_hidden(node: Node) -> bool:
	if node == null:
		return false
	for mesh_node in _meshes(node, []):
		if HFHiddenFaces.has_hidden_surface(mesh_node.mesh):
			return true
		if HFHiddenFaces.is_hidden_material((mesh_node as MeshInstance3D).material_override):
			return true
	return false


func _settle_physics() -> void:
	for _i in 3:
		await _tree.physics_frame


## Where a ray from `from` to `to` meets the baked collision, or null.
func _ray(root: Node3D, from: Vector3, to: Vector3) -> Variant:
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (BAKE_LAYER_INDEX - 1))
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	return hit.get("position") if not hit.is_empty() else null


func _new_level() -> Node3D:
	var root: Node3D = await fresh_root("Hidden_%d" % (_case + 1))
	root.bake_collision_layer_index = BAKE_LAYER_INDEX
	root.hflevel_autosave_enabled = false
	return root


static func _hidden_normals(brush: Node) -> Array:
	var out: Array = []
	for face in brush.faces:
		if face != null and face.is_hidden():
			out.append(
				(brush.global_transform.basis * face.normal).normalized().snapped(
					Vector3.ONE * 0.01
				)
			)
	return out


static func _hidden_count(root: Node3D) -> int:
	var n := 0
	for b in root.draft_brushes_node.get_children():
		for face in b.faces:
			if face != null and face.is_hidden():
				n += 1
	return n


# ---------------------------------------------------------------------------
# Bake paths
# ---------------------------------------------------------------------------


## One floor, 4 x 1 x 4, its underside Hidden, baked one way: is the underside
## drawn, does a ray from below still meet it, and does a ray from above meet the
## top. A second floor beside it with nothing Hidden says the path draws at all.
func _bake_case(label: String, settings: Dictionary, tie_class: String = "", how := "full") -> void:
	var at := _next_origin()
	var root: Node3D = await _new_level()
	for key in settings:
		root.set(key, settings[key])
	var floor_brush := _box(root, "floor", Vector3(4, 1, 4), at + Vector3(0, 0.5, 0))
	var plain := _box(root, "plain", Vector3(4, 1, 4), at + Vector3(10, 0.5, 0))
	# A cut far off, so the CSG path is the one a level with a cut takes.
	if settings.get("_with_cut", false):
		_box(
			root,
			"notch",
			Vector3(1, 1, 1),
			at + Vector3(20, 0.5, 0),
			{"operation": CSGShape3D.OPERATION_SUBTRACTION}
		)
		_box(root, "notched", Vector3(4, 1, 4), at + Vector3(20, 0.5, 0))
	if tie_class != "":
		var name := "named_%d" % _case if settings.get("_named", false) else ""
		root.brush_system.tie_brushes_to_entity(["floor"], tie_class, name)
		root.brush_system.tie_brushes_to_entity(
			["plain"], tie_class, name + "b" if name != "" else ""
		)
	_hide(root, floor_brush, Vector3.DOWN)
	var all_hidden: bool = settings.get("_all", false)
	if all_hidden:
		# Every face: an invisible wall, collision only.
		root.set_faces_hidden({"floor": range(floor_brush.faces.size())}, true)
	await frame()
	match how:
		"full":
			await root.bake()
		"selected":
			# Bake with nothing hidden, then hide and Bake Selected.
			root.set_faces_hidden({"floor": [_face_facing(floor_brush, Vector3.DOWN)]}, false)
			await root.bake()
			_hide(root, floor_brush, Vector3.DOWN)
			await root.bake_selected([floor_brush, plain])
		"dirty":
			# Bake with nothing hidden, then hide and Bake Changed.
			root.set_faces_hidden({"floor": [_face_facing(floor_brush, Vector3.DOWN)]}, false)
			await root.bake()
			_hide(root, floor_brush, Vector3.DOWN)
			root.tag_brush_dirty("floor")
			await root.bake_dirty()
	await frame()
	var baked: Node = root.baked_container
	var under := _drawn_area_at(baked, at.y, at, 2.0)
	var plain_under := _drawn_area_at(baked, at.y, at + Vector3(10, 0, 0), 2.0)
	var top := _drawn_area_at(baked, at.y + 1.0, at, 2.0)
	await _settle_physics()
	var from_below = _ray(root, at + Vector3(0.3, -3, 0.2), at + Vector3(0.3, 3, 0.2))
	var from_above = _ray(root, at + Vector3(0.3, 5, 0.2), at + Vector3(0.3, -5, 0.2))
	note(
		"%s" % label,
		(
			"underside drawn %.2f m2 (plain floor %.2f), top drawn %.2f, ray from below %s, from above %s, stripes in bake %s, summary %s"
			% [
				under,
				plain_under,
				top,
				from_below,
				from_above,
				_wears_hidden(baked),
				root.bake_system.last_hidden_faces
			]
		)
	)
	if baked == null:
		flag("%s: no baked container" % label)
	else:
		if under > 0.01:
			flag(
				"%s: the Hidden underside is still drawn" % label,
				"%.2f m2 of mesh at y = %.2f" % [under, at.y]
			)
		if _wears_hidden(baked):
			flag("%s: a baked mesh wears the Hidden stripes" % label)
		if all_hidden and top > 0.01:
			flag("%s: a brush with every face Hidden still draws its top" % label, "%.2f m2" % top)
		if not all_hidden and top < 15.9:
			flag("%s: the floor's top is not drawn" % label, "%.2f m2" % top)
	var solid := tie_class != "func_illusionary"
	if solid and tie_class != "func_physbox":
		if from_below == null:
			flag(
				"%s: the Hidden underside no longer collides" % label,
				"a ray from below at %s met nothing on the bake layer" % (at + Vector3(0.3, 0, 0.2))
			)
		if from_above == null:
			flag("%s: the floor has no collision at all" % label)
	if tie_class == "func_illusionary" and (from_below != null or from_above != null):
		flag("%s: an illusionary floor collides" % label, "%s / %s" % [from_below, from_above])
	await drop_root(root)


func _every_bake_path() -> void:
	await _bake_case("face path (defaults)", {})
	await _bake_case("CSG path, face materials off", {"bake_use_face_materials": false})
	await _bake_case(
		"CSG path, face materials off, a cut in the level",
		{"bake_use_face_materials": false, "_with_cut": true}
	)
	await _bake_case("face path, a cut in the level", {"_with_cut": true})
	await _bake_case("merged meshes", {"bake_merge_meshes": true})
	await _bake_case(
		"merged meshes, face materials off",
		{"bake_merge_meshes": true, "bake_use_face_materials": false}
	)
	await _bake_case("chunked 2 m", {"bake_chunk_size": 2.0})
	await _bake_case(
		"chunked 2 m, face materials off",
		{"bake_chunk_size": 2.0, "bake_use_face_materials": false}
	)
	await _bake_case("atlas", {"bake_use_atlas": true})
	await _bake_case("lightmap UV2 + LODs", {"bake_lightmap_uv2": true, "bake_generate_lods": true})
	await _bake_case("convex collision per brush", {"bake_collision_mode": 1})
	await _bake_case("collision mode 2", {"bake_collision_mode": 2})
	await _bake_case("func_detail, grouped", {}, "func_detail")
	await _bake_case("func_detail, named", {"_named": true}, "func_detail")
	await _bake_case("func_wall", {}, "func_wall")
	await _bake_case("func_illusionary", {}, "func_illusionary")
	await _bake_case("func_physbox", {}, "func_physbox")
	await _bake_case("every face Hidden, face path", {"_all": true})
	await _bake_case(
		"every face Hidden, CSG path", {"_all": true, "bake_use_face_materials": false}
	)
	await _bake_case("every face Hidden, merged", {"_all": true, "bake_merge_meshes": true})
	await _bake_case("every face Hidden, chunked", {"_all": true, "bake_chunk_size": 2.0})
	await _bake_case(
		"every face Hidden, func_detail named", {"_all": true, "_named": true}, "func_detail"
	)
	await _bake_case("Bake Selected", {}, "", "selected")
	await _bake_case("Bake Changed", {}, "", "dirty")


# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------


func _the_operations() -> void:
	var at := _next_origin()
	var root: Node3D = await _new_level()

	# Merge: two boxes side by side, both tops Hidden. The merged top is one face
	# over both, so it should be Hidden; nothing else should be.
	var a := _box(root, "ma", Vector3(2, 1, 2), at + Vector3(-1, 0.5, 0))
	var b := _box(root, "mb", Vector3(2, 1, 2), at + Vector3(1, 0.5, 0))
	_hide(root, a, Vector3.UP)
	_hide(root, b, Vector3.UP)
	var merged: HFOpResult = root.merge_brushes_by_ids(["ma", "mb"])
	await frame()
	var hidden_after := []
	for brush in root.draft_brushes_node.get_children():
		hidden_after.append_array(_hidden_normals(brush))
	note(
		"merge of two boxes with Hidden tops",
		"%s, hidden normals after %s" % [merged.message if merged else "null", hidden_after]
	)
	if merged and merged.ok and not hidden_after.has(Vector3(0, 1, 0)):
		flag(
			"Merge drops a Hidden face",
			"both tops were Hidden; the merged brush's Hidden faces face %s" % [hidden_after]
		)

	# Merge where only one of the two tops is Hidden: the merged top covers a half
	# that was seen. Both orders, since the look comes from one source face.
	for order in [["ha", "hb"], ["hb", "ha"]]:
		var z := -10.0 if order[0] == "ha" else -15.0
		var ha := _box(root, "ha", Vector3(2, 1, 2), at + Vector3(-1, 0.5, z))
		_box(root, "hb", Vector3(2, 1, 2), at + Vector3(1, 0.5, z))
		_hide(root, ha, Vector3.UP)
		var half: HFOpResult = root.merge_brushes_by_ids(order)
		await frame()
		var tops := []
		for brush in root.draft_brushes_node.get_children():
			if absf(brush.global_position.z - (at.z + z)) < 0.5:
				for face in brush.faces:
					if (brush.global_transform.basis * face.normal).dot(Vector3.UP) > 0.99:
						tops.append(
							[
								face.is_hidden(),
								snappedf(
									HFHiddenFaces.polygon_area(
										brush.global_transform.basis, face.local_verts
									),
									0.01
								)
							]
						)
		note(
			"merge %s with only ha's top Hidden" % [order],
			"%s: tops [hidden, area] %s" % [half.message if half else "null", tops]
		)
		if order[0] == "ha":
			await root.bake()
			await frame()
			var drawn_top := _drawn_area_at(
				root.baked_container, at.y + 1.0, at + Vector3(0, 0, z), 2.0
			)
			note(
				"  baked: top drawn over the 4 x 2 merged slab",
				"%.2f m2 (hb's half alone is 4)" % drawn_top
			)
		for top in tops:
			if top[0] and top[1] > 4.01:
				known(
					2002,
					"Merge makes a whole face Hidden when only part of it was",
					(
						"merging %s, only ha's 2 x 2 top Hidden, gives one %.1f m2 top that is Hidden whole, so hb's top, which was drawn, drops out of the bake's mesh. HFConvexClip.union_of() gives each merged face the look of the largest source face on its plane, the first on a tie, and copy_appearance_from() carries face_type with it; in the other order the top comes out Normal"
						% [order, top[1]]
					)
				)

	# Clip: a floor with its underside Hidden, clipped across the middle. Each
	# piece keeps a Hidden underside, and the cut faces are Normal.
	var c := _box(root, "clipme", Vector3(4, 1, 4), at + Vector3(0, 0.5, 10))
	_hide(root, c, Vector3.DOWN)
	var clipped: HFOpResult = root.clip_brush_by_id("clipme", 0, at.x)
	await frame()
	var pieces := []
	for brush in root.draft_brushes_node.get_children():
		if absf(brush.global_position.z - 10.0) < 3.0:
			pieces.append(_hidden_normals(brush))
	note(
		"clip of a floor with a Hidden underside",
		"%s, each piece's Hidden normals %s" % [clipped.message if clipped else "null", pieces]
	)
	for piece in pieces:
		if not piece.has(Vector3(0, -1, 0)):
			flag("Clip drops a piece's Hidden underside", str(pieces))
		if piece.size() > 1:
			flag("Clip makes a cut face Hidden", str(pieces))

	# Hollow: a room whose six outer faces are Hidden, the outside of a sealed
	# room. The inside walls are new surface, there to be seen.
	var room := _box(root, "room", Vector3(6, 4, 6), at + Vector3(0, 2, 30))
	root.set_faces_hidden({"room": [0, 1, 2, 3, 4, 5]}, true)
	var centre := at + Vector3(0, 2, 30)
	var hollowed: HFOpResult = root.hollow_brush_by_id("room", 0.5)
	await frame()
	var inner_hidden := 0
	var inner := 0
	var outer_hidden := 0
	for brush in root.draft_brushes_node.get_children():
		if brush.global_position.distance_to(centre) > 6.0:
			continue
		for face in brush.faces:
			var n: Vector3 = brush.global_transform.basis * face.normal
			var mid := Vector3.ZERO
			for v in face.local_verts:
				mid += brush.global_transform * v
			mid /= face.local_verts.size()
			# A face whose normal points at the room's middle faces into it.
			var into: bool = (
				n.dot(centre - mid) > 0.0
				and (mid - centre).abs().max_axis_index() == n.abs().max_axis_index()
			)
			var on_shell: bool = (
				absf(absf(mid.x - centre.x) - 3.0) < 0.01
				or absf(absf(mid.y - centre.y) - 2.0) < 0.01
				or absf(absf(mid.z - centre.z) - 3.0) < 0.01
			)
			if into and not on_shell:
				inner += 1
				if face.is_hidden():
					inner_hidden += 1
			elif on_shell and face.is_hidden():
				outer_hidden += 1
	note(
		"hollow of a room with every outer face Hidden",
		(
			"%s: %d inner faces, %d of them Hidden; %d outer faces Hidden"
			% [hollowed.message if hollowed else "null", inner, inner_hidden, outer_hidden]
		)
	)
	if inner_hidden > 0:
		flag(
			"Hollow makes the room's inside walls Hidden",
			"%d of %d inner faces" % [inner_hidden, inner]
		)

	# Carve: a floor with a Hidden underside, a box cut through its middle.
	var f := _box(root, "carved", Vector3(4, 1, 4), at + Vector3(0, 0.5, 50))
	_hide(root, f, Vector3.DOWN)
	_box(root, "cutter", Vector3(1, 3, 1), at + Vector3(0, 0.5, 50))
	var carved: HFOpResult = root.carve_with_brush("cutter")
	await frame()
	var undersides := 0
	var hidden_up := 0
	var hidden_side := 0
	for brush in root.draft_brushes_node.get_children():
		if absf(brush.global_position.z - 50.0) > 3.0 or str(brush.brush_id) == "cutter":
			continue
		for n in _hidden_normals(brush):
			if n == Vector3(0, -1, 0):
				undersides += 1
			elif n == Vector3(0, 1, 0):
				hidden_up += 1
			else:
				hidden_side += 1
	note(
		"carve of a floor with a Hidden underside",
		(
			"%s: %d Hidden undersides, %d Hidden tops, %d Hidden sides"
			% [carved.message if carved else "null", undersides, hidden_up, hidden_side]
		)
	)
	if carved and carved.ok and (hidden_up > 0 or hidden_side > 0):
		flag("Carve makes a face it opened Hidden", "%d tops, %d sides" % [hidden_up, hidden_side])
	if carved and carved.ok and undersides == 0:
		flag("Carve drops the Hidden underside of every piece")

	# Duplicate and arrays carry it.
	var d := _box(root, "dup", Vector3(2, 1, 2), at + Vector3(0, 0.5, 70))
	_hide(root, d, Vector3.DOWN)
	var copy: Node = root.duplicate_brush(d)
	note(
		"duplicate keeps the Hidden underside",
		copy != null and _hidden_normals(copy) == [Vector3(0, -1, 0)]
	)
	if copy and _hidden_normals(copy) != [Vector3(0, -1, 0)]:
		flag("Duplicate drops a Hidden face", str(_hidden_normals(copy)))
	var before := _hidden_count(root)
	var arr = root.create_duplicate_array(PackedStringArray(["dup"]), 3, Vector3(3, 0, 0))
	await frame()
	note("a 3 copy array of it", "Hidden faces %d -> %d (%s)" % [before, _hidden_count(root), arr])

	# Undo through a state round trip.
	var state: Dictionary = root.capture_state()
	var u := _box(root, "undo_me", Vector3(2, 1, 2), at + Vector3(0, 0.5, 90))
	state = root.capture_state()
	_hide(root, u, Vector3.DOWN)
	root.restore_state(state)
	await frame()
	var back: Node = root.find_brush_by_id("undo_me")
	note(
		"undo of Hide Faces through restore_state",
		"Hidden after %s" % [_hidden_normals(back) if back else "brush gone"]
	)
	if back and not _hidden_normals(back).is_empty():
		flag("restore_state keeps a face Hidden that the state had Normal")
	await drop_root(root)


# ---------------------------------------------------------------------------
# .map and glTF
# ---------------------------------------------------------------------------


func _map_and_gltf() -> void:
	var at := _next_origin()
	var root: Node3D = await _new_level()
	var floor_brush := _box(root, "floor", Vector3(4, 1, 4), at + Vector3(0, 0.5, 0))
	_hide(root, floor_brush, Vector3.DOWN)
	# A turned one, so the Valve 220 axes have something to say.
	var turned := _box(
		root,
		"turned",
		Vector3(2, 2, 2),
		at + Vector3(8, 1, 0),
		{"transform": Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), at + Vector3(8, 1, 0))}
	)
	_hide(root, turned, Vector3.UP)
	for format in ["quake", "valve220"]:
		var err: int = root.export_map(MAP_PATH, format)
		var text := FileAccess.get_file_as_string(MAP_PATH)
		var skips := text.count(" skip ")
		var back: Node3D = await fresh_root("HiddenMap_%s" % format)
		var imported: int = back.import_map(MAP_PATH)
		await frame()
		note(
			".map %s" % format,
			(
				"export %s, 'skip' written %d times, import %s, Hidden faces read back %d of 2"
				% [error_string(err), skips, error_string(imported), _hidden_count(back)]
			)
		)
		if imported == OK and _hidden_count(back) != 2:
			flag(
				".map %s round trip changes the number of Hidden faces" % format,
				"2 -> %d" % _hidden_count(back)
			)
		await drop_root(back)

	await root.bake()
	await frame()
	var err: int = root.export_baked_gltf(GLB_PATH)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var read: int = doc.append_from_file(ProjectSettings.globalize_path(GLB_PATH), state)
	var scene: Node = doc.generate_scene(state) if read == OK else null
	var under := 0.0
	if scene:
		var holder := Node3D.new()
		_tree.get_root().add_child(holder)
		holder.add_child(scene)
		under = _drawn_area_at(scene, at.y, at, 2.0)
		var top := _drawn_area_at(scene, at.y + 1.0, at, 2.0)
		note(
			"glTF of the bake",
			(
				"write %s, read %s, underside drawn %.2f, top drawn %.2f, stripes %s"
				% [error_string(err), error_string(read), under, top, _wears_hidden(scene)]
			)
		)
		if under > 0.01:
			flag("the glTF export draws a Hidden face", "%.2f m2" % under)
		holder.queue_free()
	else:
		note(
			"glTF of the bake could not be read back",
			"write %s, read %s" % [error_string(err), error_string(read)]
		)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Face Direction
# ---------------------------------------------------------------------------


static func _materials_of(node: Node) -> Array:
	var out: Array = []
	for mesh_node in _meshes(node, []):
		var mi := mesh_node as MeshInstance3D
		out.append(mi.material_override)
		for s in mi.mesh.get_surface_count():
			out.append(mi.mesh.surface_get_material(s))
	return out


## A bake made with Face Direction on against the same bake with it off: the
## structural brushes and a named func_detail, both with a palette material.
func _face_direction_and_the_bake() -> void:
	var looks: Array = []
	for shown in [false, true]:
		var at := _next_origin()
		var root: Node3D = await _new_level()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.7, 0.3)
		mat.resource_name = "VibeGreen"
		var slot: int = root.material_manager.add_material(mat)
		var wall := _box(root, "wall", Vector3(4, 2, 1), at + Vector3(0, 1, 0))
		var crate := _box(root, "crate", Vector3(1, 1, 1), at + Vector3(4, 0.5, 0))
		var plain := _box(root, "plain_crate", Vector3(1, 1, 1), at + Vector3(8, 0.5, 0))
		root.assign_material_to_whole_brushes(slot, ["wall", "crate"])
		# A brush whose material is its own, not a palette slot's.
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.8, 0.1, 0.1)
		root.create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(1, 1, 1),
				"center": at + Vector3(12, 0.5, 0),
				"brush_id": "tinted",
				"material": red
			}
		)
		root.brush_system.tie_brushes_to_entity(["tinted"], "func_detail", "tinted_%d" % _case)
		root.brush_system.tie_brushes_to_entity(["crate"], "func_detail", "crate_%d" % _case)
		root.brush_system.tie_brushes_to_entity(["plain_crate"], "func_illusionary", "")
		root.set_face_direction_view(shown)
		await frame()
		await root.bake()
		await frame()
		var used := _materials_of(root.baked_container)
		var direction := 0
		var green := 0
		var reds := 0
		for m in used:
			if m == HFFaceDirection.material():
				direction += 1
			if m == mat:
				green += 1
			if (
				m is StandardMaterial3D
				and (m as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.8, 0.1, 0.1))
			):
				reds += 1
		var surfaces := {}
		for mesh_node in _meshes(root.baked_container, []):
			surfaces[str(mesh_node.name)] = (mesh_node as MeshInstance3D).mesh.get_surface_count()
		looks.append(
			{
				"shown": shown,
				"direction": direction,
				"green": green,
				"red": reds,
				"materials": used.size(),
				"surfaces": surfaces
			}
		)
		note("bake with Face Direction %s" % ("on" if shown else "off"), looks[-1])
		if direction > 0:
			flag("a bake made with Face Direction on wears the Face Direction look", looks[-1])
		# Saved while on, a level opens with it off.
		root.set_face_direction_view(false)
		await drop_root(root)
	if looks.size() == 2 and looks[0]["red"] != looks[1]["red"]:
		flag(
			"a brush's own material is lost from a bake made with Face Direction on",
			(
				"the tinted func_detail's material is on %d baked surfaces with it off and %d with it on"
				% [looks[0]["red"], looks[1]["red"]]
			)
		)
	if looks.size() == 2 and looks[0]["green"] != looks[1]["green"]:
		flag(
			"Face Direction changes what the bake is drawn with",
			(
				"the palette material is on %d baked surfaces with it off and %d with it on"
				% [looks[0]["green"], looks[1]["green"]]
			)
		)
