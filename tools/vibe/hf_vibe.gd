@tool
extends RefCounted

## Shared scaffolding for the exploratory ("vibe") scenarios in
## `tools/vibe/scenarios/`.
##
## The point of those scenarios is to drive a real `LevelRoot` through long
## sequences, the way a mapper drives it, and to notice when the result is not
## what a mapper would expect. So nothing here asserts and
## nothing here stops a run: a scenario reports observations, and the ones that
## look wrong are flagged for a human to judge. See `tools/vibe/README.md`.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")


## A stable string for any value, for comparing two snapshots.
##
## Dictionary keys come back from a `.hflevel` in whatever order the JSON decode
## produced, and `str()` on a Dictionary is key-order sensitive. Comparing raw
## `str()` output therefore reports every round trip as having changed
## everything, which is worse than not checking at all -- a harness nobody
## believes gets ignored on the run that matters. Sort the keys and the problem
## goes away without hiding a real difference.
static func canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		var parts: PackedStringArray = PackedStringArray()
		for k in keys:
			parts.append("%s=%s" % [k, canonical((value as Dictionary)[k])])
		return "{%s}" % ", ".join(parts)
	if value is Array:
		var items: PackedStringArray = PackedStringArray()
		for item in value:
			items.append(canonical(item))
		return "[%s]" % ", ".join(items)
	# Floats are rounded before they are compared. Every round trip in the sweep
	# goes through a matrix or a serialiser somewhere, and both leave residue in
	# the last few bits -- four 90-degree rotations of a brush come back with a
	# uv_rotation of 1.7e-7 rather than 0. Reporting that as "the round trip
	# changed the level" is the harness flagging the float type rather than the
	# code under test, and it hides the differences that matter among the ones
	# that do not. Six decimal places is finer than any real geometry difference
	# in a project whose player is 1.6 units tall.
	if value is float:
		return "%.6f" % snappedf(value, 0.000001)
	if value is Vector2:
		return "(%.6f, %.6f)" % [value.x, value.y]
	if value is Vector3:
		return "(%.6f, %.6f, %.6f)" % [value.x, value.y, value.z]
	return str(value)


## A live `LevelRoot` in the running tree, with every editor subsystem up.
##
## `LevelRoot._should_initialize_editor_systems()` is satisfied by
## `OS.has_feature("editor")`, so the editor binary brings up the full subsystem
## graph headlessly without the plugin. The caller must `await tree.process_frame`
## once afterwards: `_ready()` runs on the frame after `add_child()`, and until it
## has, every `root.*_system` is still null.
## `auto_spawn_player` has to be set here, before `add_child()`, and not by the
## caller afterwards. `_ready()` reads it once and queues `_start_playtest()`
## with `call_deferred()`, so a scenario that writes `root.auto_spawn_player =
## false` on the line after `fresh_root()` is already too late: the playtest has
## been scheduled, a whole extra bake runs, and a `CharacterBody3D` lands in the
## physics space. Every raycast the scenario makes then has a chance of hitting
## the player rather than the level, which reads as the level being there when
## it is not -- and back, which is worse.
static func make_root(
	tree: SceneTree, node_name: String = "Level", spawn_player: bool = false
) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.set_script(LevelRootScript)
	root.auto_spawn_player = spawn_player
	tree.get_root().add_child(root)
	return root


## Block until a `save_hflevel()` has actually landed on disk.
##
## The save is threaded, and the worker is collected in `_process_hflevel_saves()`
## -- which only runs on its own under `Engine.is_editor_hint()`, so headless has
## to pump it. Polling for the file to exist instead races the writer: the
## destination is briefly absent partway through the atomic replace, so a poll
## that only checks existence can return while the old file is gone and the new
## one is not in place yet, and the load that follows then fails for no visible
## reason.
static func settle_save(tree: SceneTree, root: Node3D, max_frames: int = 600) -> bool:
	if not root.file_system:
		return false
	for _i in range(max_frames):
		root._process_hflevel_saves()
		if not root.file_system._hflevel_thread:
			return true
		await tree.process_frame
	return false


## Every draft brush described in a form two levels can be compared by.
##
## Deliberately excludes the brush id: ids carry a per-session prefix, so two
## runs of the same build produce different ones and a raw diff is all noise.
static func describe_brushes(root: Node3D) -> Array:
	var out: Array = []
	if not root.draft_brushes_node:
		return out
	for b in root.draft_brushes_node.get_children():
		var faces: Array = []
		var face_list = b.get("faces")
		if face_list is Array:
			for f in face_list:
				(
					faces
					. append(
						{
							"mat": f.material_idx,
							"uv_offset": f.uv_offset,
							"uv_scale": f.uv_scale,
							"uv_rotation": f.uv_rotation,
							"projection": f.uv_projection,
							"displaced": f.displacement != null,
						}
					)
				)
		var size = b.get("size")
		var extent = (size as Vector3).snapped(Vector3.ONE * 0.001) if size != null else null
		(
			out
			. append(
				{
					"position": b.global_position.snapped(Vector3.ONE * 0.001),
					"size": extent,
					"rotation":
					str(b.global_transform.basis.get_euler().snapped(Vector3.ONE * 0.001)),
					"operation": b.operation,
					"visible": b.visible,
					"entity_class": str(b.get_meta("brush_entity_class", "")),
					"generator": str(b.get_meta("hf_generator_id", "")) != "",
					"faces": faces,
				}
			)
		)
	out.sort_custom(func(a, b): return canonical(a) < canonical(b))
	return out


## Every entity described the same way, node name and authored alias both.
static func describe_entities(root: Node3D) -> Array:
	var out: Array = []
	if not root.entities_node:
		return out
	for e in root.entities_node.get_children():
		(
			out
			. append(
				{
					"node_name": str(e.name),
					"alias": str(e.get_meta("entity_name", "")),
					"type": str(e.get("entity_type")),
					"position": e.global_position,
					"data": e.get("entity_data"),
					"io": e.get_meta("entity_io_outputs", []),
				}
			)
		)
	out.sort_custom(func(a, b): return canonical(a) < canonical(b))
	return out


## The whole level in one comparable dictionary, for round-trip checks.
static func describe_level(root: Node3D) -> Dictionary:
	var d: Dictionary = {}
	d["brushes"] = describe_brushes(root)
	d["entities"] = describe_entities(root)
	# Visgroup order is however the backing dictionary iterated, which a save and
	# reload is free to change. The set is the level; the order is not.
	var visgroups: Array = Array(root.get_visgroup_names())
	visgroups.sort()
	d["visgroups"] = visgroups
	d["materials"] = root.material_manager.get_material_names() if root.material_manager else []
	d["generators"] = root.generator_system.capture().size() if root.generator_system else -1
	var layers = root.state_system.capture_paint_layers(true) if root.state_system else []
	d["paint_layers"] = layers.size()
	d["cordon_enabled"] = root.get("cordon_enabled")
	return d


## Structural facts that should hold after any sequence of operations, whatever
## the sequence was. Returns a list of human-readable violations.
##
## Used by the chaos scenario after every step, so a break is attributed to the
## operation that caused it rather than discovered at the end of the run.
static func check_invariants(root: Node3D) -> Array:
	var problems: Array = []
	if not root.draft_brushes_node:
		return problems
	var seen: Dictionary = {}
	var children: Array = root.draft_brushes_node.get_children()
	for b in children:
		var id := str(b.get_meta("brush_id", ""))
		if id == "":
			problems.append("brush with no id at %s" % b.global_position)
		elif seen.has(id):
			problems.append("duplicate brush id %s" % id)
		seen[id] = true
		var size = b.get("size")
		if size != null:
			var s: Vector3 = size
			if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
				problems.append("non-positive size %s on %s" % [s, id])
			if not s.is_finite():
				problems.append("non-finite size %s on %s" % [s, id])
		if not b.global_position.is_finite():
			problems.append("non-finite position on %s" % id)
	# A cut waiting in Pending Cuts is a live brush too, outside the draft.
	var pending: int = root.pending_node.get_child_count() if root.pending_node else 0
	if root.brush_system and root.brush_system.get_live_brush_count() != children.size() + pending:
		problems.append(
			(
				"live brush count %d disagrees with %d draft children and %d pending cuts"
				% [root.brush_system.get_live_brush_count(), children.size(), pending]
			)
		)
	return problems


## Each brush a closed solid with its faces turned out: no edge used by one face
## only, no face whose normal points back at the brush's middle. Returns one
## line a brush that is not.
##
## `seen` carries each brush's corners from the call before, and a brush whose
## corners have not moved since is not read again. A long run then pays for the
## brushes a step changed, not for the whole level every step, and a broken
## brush is named at the step that broke it, once.
static func check_solids(root: Node3D, seen: Dictionary = {}) -> Array:
	var problems: Array = []
	if not root.draft_brushes_node:
		return problems
	for b in root.draft_brushes_node.get_children():
		var faces = b.get("faces")
		if not (faces is Array):
			continue
		var corners: Array = [str(b.get_meta("brush_id", ""))]
		for f in faces:
			corners.append(f.local_verts)
		var reading := hash(corners)
		if seen.get(b.get_instance_id()) == reading:
			continue
		seen[b.get_instance_id()] = reading
		var open := open_edge_count(faces)
		var inward := inward_face_count(b)
		if open > 0 or inward > 0:
			problems.append(
				(
					"brush %s has %d open edges and %d faces turned in"
					% [str(b.get_meta("brush_id", "")), open, inward]
				)
			)
	return problems


## A cheap reading of the level that moves when an operation did something: the
## counts, and the sums of every brush's position, size and face count. Two
## equal readings either side of a step mean the step changed nothing.
static func signature(root: Node3D) -> String:
	var position_sum := Vector3.ZERO
	var size_sum := Vector3.ZERO
	var faces := 0
	var brushes: Array = root.draft_brushes_node.get_children() if root.draft_brushes_node else []
	for b in brushes:
		position_sum += b.global_position
		var size = b.get("size")
		if size is Vector3:
			size_sum += size
		var face_list = b.get("faces")
		if face_list is Array:
			faces += (face_list as Array).size()
	return canonical(
		[
			brushes.size(),
			root.entities_node.get_child_count() if root.entities_node else 0,
			root.get_visgroup_names().size(),
			root.paint_layers.layers.size() if root.paint_layers else 0,
			position_sum.snapped(Vector3.ONE * 0.001),
			size_sum.snapped(Vector3.ONE * 0.001),
			faces,
		]
	)


## What a run ended with, as one line two runs of a seed can be compared by
## (#1643): the counts, the brushes' total volume and their bounds, and how many
## edges are open and faces turned in. Nothing in it carries an id, which has a
## per session prefix.
static func outcome(root: Node3D) -> Dictionary:
	var volume := 0.0
	var open_edges := 0
	var inside_out := 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var brushes: Array = root.draft_brushes_node.get_children() if root.draft_brushes_node else []
	for b in brushes:
		var faces = b.get("faces")
		if not (faces is Array):
			continue
		var xf: Transform3D = b.global_transform
		volume += solid_volume(faces) * absf(xf.basis.determinant())
		open_edges += open_edge_count(faces)
		inside_out += inward_face_count(b)
		for f in faces:
			for v in f.local_verts:
				var world: Vector3 = xf * v
				lo = lo.min(world)
				hi = hi.max(world)
	var bounds: Array = []
	if not brushes.is_empty() and lo.is_finite():
		bounds = [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]
	return {
		"brushes": brushes.size(),
		"entities": root.entities_node.get_child_count() if root.entities_node else 0,
		"volume": volume,
		"bounds": bounds,
		"open_edges": open_edges,
		"inside_out": inside_out,
	}


## The volume a brush's faces enclose, in its own space: the sum of the signed
## tetrahedra each face fans out to the origin, turned positive.
static func solid_volume(faces: Array) -> float:
	var six_volume := 0.0
	for f in faces:
		var verts: Array = Array(f.local_verts)
		for i in range(1, verts.size() - 1):
			six_volume += (verts[0] as Vector3).dot((verts[i] as Vector3).cross(verts[i + 1]))
	return absf(six_volume) / 6.0


## Edges used by one face only. A closed solid has none.
##
## Corners are matched by distance, not by rounding to a grid: two copies of a
## corner either side of a grid line round apart, and a clip that put one at
## y = 36.6185 counted four open edges on a closed brush.
static func open_edge_count(faces: Array) -> int:
	var corners: Array[Vector3] = []
	var uses: Dictionary = {}
	for f in faces:
		var verts: Array = Array(f.local_verts)
		for i in verts.size():
			var a := _corner_index(corners, verts[i])
			var b := _corner_index(corners, verts[(i + 1) % verts.size()])
			var key := Vector2i(mini(a, b), maxi(a, b))
			uses[key] = int(uses.get(key, 0)) + 1
	var open := 0
	for key in uses:
		if uses[key] == 1:
			open += 1
	return open


static func _corner_index(corners: Array[Vector3], point: Vector3) -> int:
	for i in corners.size():
		if corners[i].distance_to(point) <= 0.001:
			return i
	corners.append(point)
	return corners.size() - 1


## How many face normals on a brush point the wrong way.
##
## The convention across the codebase is clockwise winding seen from outside, so
## on a convex brush a face normal should point away from the centroid. Counts
## the faces whose normal points back at it instead.
##
## Only meaningful on a convex solid: on something genuinely concave -- a torus,
## a carved shell -- inward-facing surfaces are the shape, not a defect. And the
## comparison is made against the *normalised* direction with a tolerance,
## because on a finely tessellated shape a sliver triangle sitting almost on the
## centroid produces a direction that is numerical noise, which a raw sign test
## reads as inverted.
static func inward_face_count(brush: Node3D, tolerance: float = 0.01) -> int:
	var faces = brush.get("faces")
	if not (faces is Array):
		return 0
	var centroid := Vector3.ZERO
	var n := 0
	for f in faces:
		for v in f.local_verts:
			centroid += v
			n += 1
	if n == 0:
		return 0
	centroid /= float(n)
	var scale := local_extent(brush).length()
	var inward := 0
	for f in faces:
		if f.local_verts.size() < 3 or f.normal.length() < 0.5:
			continue
		var face_centre := Vector3.ZERO
		for v in f.local_verts:
			face_centre += v
		face_centre /= float(f.local_verts.size())
		var outward := face_centre - centroid
		# A face centred on the centroid has no meaningful outward direction.
		if outward.length() < scale * 0.001:
			continue
		if f.normal.normalized().dot(outward.normalized()) < -tolerance:
			inward += 1
	return inward


## The extent the brush's own face geometry actually occupies, in local space.
##
## Compare it against the brush's `size` to catch geometry that has escaped the
## shape it claims to be -- the two agreeing is what makes a brush a brush.
static func local_extent(brush: Node3D) -> Vector3:
	var faces = brush.get("faces")
	if not (faces is Array) or (faces as Array).is_empty():
		return Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for f in faces:
		for v in f.local_verts:
			lo = lo.min(v)
			hi = hi.max(v)
	return hi - lo


## Write `text` to `path`, creating the directory. For building the malformed
## input files a loader is then pointed at.
static func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


## Size on disk in bytes, 0 when the file is not there.
static func file_size(path: String) -> int:
	return FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).size()
