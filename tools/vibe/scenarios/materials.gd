@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The material palette: the array every `FaceData.material_idx` is an index
## into.
##
## Two things make this worth poking at. The palette is positional, so anything
## that changes its length has to repoint every face above the change or repaint
## brushes nobody touched. And the manager carries a usage-tracking block that
## decides which materials are "unused", which is the kind of answer that gets
## acted on destructively.


func id() -> String:
	return "materials"


func summary() -> String:
	return "palette slots, the remap when one is removed, and the usage tracker"


func run() -> void:
	await _removing_a_slot_repoints_the_faces_above_it()
	await _removing_a_slot_reaches_every_brush_container()
	await _the_usage_tracker()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _mat(colour: Color, path_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.resource_name = path_name
	return m


func _face_slots(brush: Node3D) -> Array:
	var out: Array = []
	for face in brush.faces:
		out.append(face.material_idx if face != null else null)
	return out


## Four materials, a brush whose faces point at slots 0..3, then slot 1 removed.
## Faces on slot 1 should go unset; faces on 2 and 3 should follow the material
## they were on, not the index.
func _removing_a_slot_repoints_the_faces_above_it() -> void:
	var root: Node3D = await fresh_root()
	root.set_materials(
		[
			_mat(Color.RED, "red"),
			_mat(Color.GREEN, "green"),
			_mat(Color.BLUE, "blue"),
			_mat(Color.WHITE, "white")
		]
	)
	var b := box(root, Vector3(64, 64, 64))
	for i in range(b.faces.size()):
		b.faces[i].material_idx = i % 4
	await frame()

	var before := _face_slots(b)
	note("palette", root.get_material_names())
	note("face slots before", before)

	root.remove_material_from_palette(1)
	await frame()
	var after := _face_slots(b)
	note("palette after removing slot 1", root.get_material_names())
	note("face slots after", after)

	# Every face that was on 1 is unset; every face above 1 has moved down one.
	var expected: Array = []
	for slot in before:
		if slot == 1:
			expected.append(-1)
		elif slot > 1:
			expected.append(slot - 1)
		else:
			expected.append(slot)
	if after != expected:
		flag(
			"removing a palette slot did not repoint the faces above it correctly",
			"expected %s, got %s" % [expected, after]
		)
	else:
		note("the remap is right for draft brushes", "%s -> %s" % [before, after])


## `_remap_face_material_indices()` walks `_iter_managed_brush_nodes()`. A level
## also holds brushes under `pending_node` and `committed_node`.
func _removing_a_slot_reaches_every_brush_container() -> void:
	var root: Node3D = await fresh_root()
	root.set_materials(
		[_mat(Color.RED, "red"), _mat(Color.GREEN, "green"), _mat(Color.BLUE, "blue")]
	)

	var containers: Dictionary = {
		"draft": root.draft_brushes_node,
		"pending": root.pending_node,
		"committed": root.committed_node,
	}
	var made: Dictionary = {}
	for label in containers:
		var parent: Node = containers[label]
		if parent == null:
			note("%s container" % label, "not present on this root")
			continue
		var b := box(root, Vector3(32, 32, 32))
		if b.get_parent() != parent:
			b.get_parent().remove_child(b)
			parent.add_child(b)
		for face in b.faces:
			face.material_idx = 2
		made[label] = b
	await frame()

	for label in made:
		note("%s brush face slots before" % label, _face_slots(made[label]))
	root.remove_material_from_palette(0)
	await frame()

	for label in made:
		var slots := _face_slots(made[label])
		note("%s brush face slots after removing slot 0" % label, slots)
		for s in slots:
			if int(s) == 2:
				flag(
					(
						"removing a palette slot left a %s brush pointing past the end of the palette"
						% label
					),
					(
						"the palette is now %d long and this brush's faces still say 2 -- _remap_face_material_indices() did not reach the %s container"
						% [root.get_materials().size(), label]
					)
				)
				break


## `MaterialManager` carries `record_usage`, `release_usage`, `rebuild_usage`,
## `find_unused_materials` and `get_usage_count`. What calls them, and what would
## they say if something did.
func _the_usage_tracker() -> void:
	var root: Node3D = await fresh_root()
	var mm = root.get_material_manager()
	# Written to disk so they have a resource_path. The tracker is keyed on that
	# string and skips any material without one, so an in-memory palette would
	# make it look right by accident.
	var red := _mat(Color.RED, "red")
	var green := _mat(Color.GREEN, "green")
	ResourceSaver.save(red, "user://vibe_red.tres")
	ResourceSaver.save(green, "user://vibe_green.tres")
	red.take_over_path("user://vibe_red.tres")
	green.take_over_path("user://vibe_green.tres")
	root.set_materials([red, green])

	# Use them the only way HammerForge actually assigns a material: per face.
	var b := box(root, Vector3(64, 64, 64))
	for face in b.faces:
		face.material_idx = 0
	await frame()

	mm.rebuild_usage(root.draft_brushes_node)
	var unused = mm.find_unused_materials()
	note("palette", root.get_material_names())
	note("every face of the one brush is on slot 0", _face_slots(b))
	var unused_names: Array = []
	for m in unused:
		unused_names.append(m.resource_path)
	note("find_unused_materials() after rebuild_usage()", "%d: %s" % [unused.size(), unused_names])
	note("usage count for the material every face is on", mm.get_usage_count(red.resource_path))

	var with_paths := 0
	for m in root.get_materials():
		if m != null and m.resource_path != "":
			with_paths += 1
	note(
		"palette materials that have a resource_path",
		"%d of %d" % [with_paths, root.get_materials().size()]
	)

	# What rebuild_usage actually reads.
	note(
		"rebuild_usage reads",
		"child.material_override on the direct children of the node it is given -- never face.material_idx"
	)
	known(
		375,
		"the material usage tracker is keyed on the wrong thing and has no caller",
		(
			"every face of the level's only brush is on '%s', and after rebuild_usage() its usage count is %d and find_unused_materials() returns %s -- the tracker counts `child.material_override`, never FaceData.material_idx; record_usage, release_usage, rebuild_usage, find_unused_materials and get_usage_count have no caller anywhere in the repo, tests included"
			% [red.resource_path, mm.get_usage_count(red.resource_path), unused_names]
		)
	)
