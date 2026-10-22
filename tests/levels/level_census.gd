extends RefCounted

## What a loaded level holds, counted the same way by the build that saved a
## release level and by the build that loads it now (#1640).
##
## `tests/levels/<version>/expected.json` is this census as the release build
## took it, and `tests/test_release_levels.gd` takes it again with this build and
## compares. Every read here is guarded, because the release builds that run it
## are older than this file and know less: a count an older build cannot take is
## left out rather than written as nothing.


## The census of `root`, a LevelRoot with a level loaded in it.
static func of(root: Node) -> Dictionary:
	var out := {}
	var brushes := _folder_brushes(root, "draft_brushes_node")
	out["brushes"] = brushes.size()
	out["pending_cuts"] = _folder_brushes(root, "pending_node").size()
	out["committed_cuts"] = _folder_brushes(root, "committed_node").size()
	var entities: Node = root.get("entities_node")
	out["entities"] = entities.get_child_count() if entities else 0
	var every := brushes + _folder_brushes(root, "pending_node")
	var ties: Array = []
	var wires: Array = []
	var slots := {}
	var anchored := 0
	var volume := 0.0
	var box := AABB()
	var seeded := false
	for brush in every:
		var tie := str(brush.get_meta("brush_entity_class", ""))
		if tie != "":
			ties.append("%s as %s" % [str(brush.get_meta("entity_name", "")), tie])
		wires.append_array(_wires_on(brush))
		var xform: Transform3D = brush.global_transform
		var rings: Array = []
		for face in brush.get("faces"):
			if face == null:
				continue
			slots[int(face.material_idx)] = true
			if not face.uv_scale.is_equal_approx(Vector2.ONE) or face.uv_offset != Vector2.ZERO:
				anchored += 1
			var ring := PackedVector3Array()
			for point in face.local_verts:
				var at: Vector3 = xform * point
				ring.append(at)
				if seeded:
					box = box.expand(at)
				else:
					box = AABB(at, Vector3.ZERO)
					seeded = true
			rings.append(ring)
		volume += _volume(rings)
	if entities:
		for entity in entities.get_children():
			wires.append_array(_wires_on(entity))
	ties.sort()
	wires.sort()
	out["ties"] = ties
	out["wires"] = wires
	out["material_slots_in_use"] = slots.size()
	out["uv_anchored_faces"] = anchored
	out["brush_volume"] = snappedf(volume, 0.001)
	out["bounds"] = {
		"min": _rounded(box.position),
		"max": _rounded(box.end),
	}
	if root.has_method("get_visgroup_names"):
		var names := Array(root.get_visgroup_names())
		names.sort()
		out["visgroups"] = names
	var manager = root.get("material_manager")
	if manager and manager.get("materials") is Array:
		out["palette_slots"] = (manager.materials as Array).size()
	var generators = root.get("generator_system")
	if generators and generators.get("generators") is Dictionary:
		out["structures"] = (generators.generators as Dictionary).size()
	if root.get("cordon_enabled") != null:
		var extra = root.get("cordon_extra_aabbs")
		var more := (extra as Array).size() if extra is Array else 0
		out["cordons"] = (1 if bool(root.get("cordon_enabled")) else 0) + more
	return out


static func _folder_brushes(root: Node, folder_name: String) -> Array:
	var folder: Node = root.get(folder_name)
	var out: Array = []
	if folder == null:
		return out
	for child in folder.get_children():
		if child.get("faces") is Array:
			out.append(child)
	return out


## Every output on a node, as "source.Output -> target.Input". The source is the
## entity name a tied brush was given, or the node's own name.
static func _wires_on(node: Node) -> Array:
	var out: Array = []
	var source := str(node.get_meta("entity_name", ""))
	if source == "":
		source = String(node.name)
	for entry in node.get_meta("entity_io_outputs", []) as Array:
		if not (entry is Dictionary):
			continue
		(
			out
			. append(
				(
					"%s.%s -> %s.%s"
					% [
						source,
						str(entry.get("output_name", "")),
						str(entry.get("target_name", "")),
						str(entry.get("input_name", "")),
					]
				)
			)
		)
	return out


## The volume a closed solid holds, from the tetrahedra its faces make with the
## origin.
static func _volume(rings: Array) -> float:
	var total := 0.0
	for ring in rings:
		for i in range(1, ring.size() - 1):
			total += ring[0].dot(ring[i].cross(ring[i + 1]))
	return absf(total) / 6.0


static func _rounded(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
