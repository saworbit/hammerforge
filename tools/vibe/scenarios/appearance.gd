@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a face looks like: its material slot, its UV transform, its projection
## and the surface paint layers stacked on it.
##
## Everything here is written straight into the bake and into the exported
## `.map`, and none of it is re-checked on the way out. So the question each
## time is whether a value that cannot mean anything -- a slot no material sits
## in, a UV scale of zero, a NaN rotation -- is refused at the door or carried
## all the way to the file.


func id() -> String:
	return "appearance"


func summary() -> String:
	return "material slots, UV params, projections and paint layers at their edges"


func run() -> void:
	await _material_slot_range()
	await _uv_params_at_their_edges()
	await _projection_range()
	await _paint_layer_stack()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## A palette of `count` distinct materials, so slot arithmetic has something to
## be wrong about.
func _palette(root: Node3D, count: int) -> void:
	var mats: Array = []
	for i in range(count):
		var m := StandardMaterial3D.new()
		m.resource_name = "mat_%d" % i
		mats.append(m)
	root.set_materials(mats)


## Assigning a slot the palette does not have.
func _material_slot_range() -> void:
	var root: Node3D = await fresh_root()
	_palette(root, 4)
	var b = box(root, Vector3(64, 64, 64))
	var id := _bid(b)
	note("palette", "%d materials" % root.get_materials().size())
	for slot in [-2, 4, 999999]:
		root.assign_material_to_whole_brushes(slot, [id])
		await frame()
		var stored: int = b.faces[0].material_idx
		note("assign slot %d" % slot, "face 0 now reads material_idx %d" % stored)
		if stored == slot and (slot < 0 or slot >= root.get_materials().size()):
			known(
				343,
				(
					"a face can be assigned material slot %d against a palette of %d"
					% [slot, root.get_materials().size()]
				),
				"nothing rejects it, and the bake and the .map export both read that slot back"
			)
	# What the exporter does with a face pointing at nothing.
	var path := "user://vibe_appearance.map"
	root.export_map(path, "valve220")
	var text := FileAccess.get_file_as_string(path)
	var first_brush_line := ""
	for line in text.split("\n"):
		if line.find("(") == 0:
			first_brush_line = line.strip_edges()
			break
	note("exported face line", first_brush_line)
	var reader: Node3D = await fresh_root("SlotReimport")
	reader.import_map(path)
	await frame()
	for problem in HFVibe.check_invariants(reader):
		flag("re-importing a map whose faces point at a missing slot broke an invariant", problem)


## UV scale, offset and rotation, at the values that make the projection
## meaningless.
func _uv_params_at_their_edges() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var id := _bid(b)
	var cases := {
		"zero scale": [Vector2.ZERO, Vector2.ZERO, 0.0],
		"negative scale": [Vector2(-1, -1), Vector2.ZERO, 0.0],
		"NAN scale": [Vector2(NAN, NAN), Vector2.ZERO, 0.0],
		"INF offset": [Vector2.ONE, Vector2(INF, 0), 0.0],
		"NAN rotation": [Vector2.ONE, Vector2.ZERO, NAN],
		"enormous scale": [Vector2(1e12, 1e12), Vector2.ZERO, 0.0],
	}
	for label in cases:
		var c: Array = cases[label]
		root.set_face_uv_params(id, 0, c[0], c[1], c[2])
		await frame()
		var tri: Dictionary = b.faces[0].triangulate()
		var uvs: PackedVector2Array = tri["uvs"]
		var finite := true
		var spread := 0.0
		for uv in uvs:
			if not uv.is_finite():
				finite = false
			else:
				spread = maxf(spread, uv.length())
		note(label, "%d uvs, finite %s, largest %f" % [uvs.size(), finite, spread])
		if not finite:
			known(
				344,
				"UV params with a %s produce non-finite UVs" % label,
				"the bake writes those straight into the mesh, where they render as nothing"
			)
		if label == "zero scale" and spread == 0.0 and uvs.size() > 0:
			known(
				344,
				"a UV scale of zero is accepted and collapses the face's UVs to a point",
				"every vertex maps to the same texel, so the face samples one pixel"
			)
		# Put it back before the next case, so failures do not compound.
		root.reset_uv_on_face(id, 0)
		await frame()


## `reproject_face_uvs` takes a projection as a bare int.
func _projection_range() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var id := _bid(b)
	for projection in [-1, 99]:
		root.reproject_face_uvs(id, 0, projection)
		await frame()
		var stored: int = b.faces[0].uv_projection
		var tri: Dictionary = b.faces[0].triangulate()
		note(
			"reproject to %d" % projection,
			"face stores %d, %d uvs" % [stored, (tri["uvs"] as PackedVector2Array).size()]
		)
		if stored == projection:
			known(
				345,
				"a face accepts UV projection %d, which is not a projection" % projection,
				"it is stored, saved and re-loaded, and the projector falls through to its default"
			)
	# Face indices outside the brush.
	for face_idx in [-1, 999]:
		root.reset_uv_on_face(id, face_idx)
		root.reproject_face_uvs(id, face_idx, 0)
		root.set_face_uv_params(id, face_idx, Vector2.ONE, Vector2.ZERO, 0.0)
		await frame()
	note("UV calls against face indices -1 and 999", "survived, %d faces intact" % b.faces.size())
	for problem in HFVibe.check_invariants(root):
		flag("out-of-range UV calls broke an invariant", problem)


## Surface paint layers stack on a face. Nothing says how many.
func _paint_layer_stack() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var id := _bid(b)
	for _i in range(64):
		root.add_surface_paint_layer(id, 0)
	await frame()
	var layers: int = b.faces[0].paint_layers.size()
	note("added 64 surface paint layers to one face", "%d on the face" % layers)
	if layers >= 64:
		known(
			351,
			"a face accepts an unbounded stack of surface paint layers",
			"%d layers on one face, each one saved and rebuilt on every preview" % layers
		)
	for bad in [-1, 9999]:
		root.remove_surface_paint_layer(id, 0, bad)
		await frame()
	note("removing paint layer -1 and 9999", "%d layers left" % b.faces[0].paint_layers.size())
	# And through a save, to see what the stack costs on disk.
	var path := "user://vibe_appearance.hflevel"
	root.save_hflevel(path, true)
	await HFVibe.settle_save(_tree, root)
	note("level with a 64-layer face", "%d bytes" % HFVibe.file_size(path))
	for problem in HFVibe.check_invariants(root):
		flag("the paint layer stack broke an invariant", problem)
