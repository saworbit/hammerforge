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


## `MaterialManager` carried `record_usage`, `release_usage`, `rebuild_usage`,
## `find_unused_materials` and `get_usage_count`. Nothing called any of them, and
## `rebuild_usage()` counted `child.material_override` rather than
## `FaceData.material_idx`, which is the only way HammerForge assigns a material.
## The block was removed (#375); this checks it has not come back.
func _the_usage_tracker() -> void:
	var root: Node3D = await fresh_root()
	var mm = root.get_material_manager()
	var gone: Array = []
	for method in [
		"record_usage",
		"release_usage",
		"rebuild_usage",
		"find_unused_materials",
		"get_usage_count",
	]:
		if mm.has_method(method):
			gone.append(method)
	note(
		"usage-tracking methods still on MaterialManager",
		"%d: %s" % [gone.size(), gone] if not gone.is_empty() else "none, as of #375"
	)
	if not gone.is_empty():
		known(
			375,
			"the material usage tracker is back",
			(
				(
					"%s is on MaterialManager again. It counted child.material_override, "
					+ "never FaceData.material_idx, so it reported the material every face "
					+ "in the level was painted with as unused."
				)
				% [gone]
			)
		)
