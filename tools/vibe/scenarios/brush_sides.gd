@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What `sides` does to a brush that has a radius.
##
## `DraftBrush.sides` is part of a brush: it is in `create_brush_from_info()`, in
## the `.hflevel`, in `HFDuplicator.shape_signature()`, and in a brush preset.
## The pyramid and the prisms build from it. This asks what the round shapes do
## with it, and what one of them costs.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

const CYLINDER := 1
const CONE := 3
const PYRAMID := 5


func id() -> String:
	return "brush-sides"


func summary() -> String:
	return "whether a cylinder or a cone is built with the number of sides it was asked for"


func run() -> void:
	await _sides_on_every_round_shape()


func _made(root: Node3D, shape: int, sides: int) -> Dictionary:
	var brush = root.create_brush_from_info(
		{"shape": shape, "size": Vector3(64, 64, 64), "sides": sides}
	)
	await frame()
	if brush == null:
		return {}
	var tri_count := 0
	for face in brush.get_faces():
		var tri: Dictionary = face.triangulate()
		tri_count += int((tri.get("verts", PackedVector3Array()) as PackedVector3Array).size() / 3)
	return {
		"sides_asked": sides,
		"sides_stored": int(brush.sides),
		"faces": brush.get_faces().size(),
		"triangles": tri_count,
	}


func _sides_on_every_round_shape() -> void:
	var root: Node3D = await fresh_root("SidesLevel")
	for shape in [["cylinder", CYLINDER], ["cone", CONE], ["pyramid", PYRAMID]]:
		var counts: Array = []
		for sides in [3, 6, 8, 16]:
			var made: Dictionary = await _made(root, int(shape[1]), sides)
			if made.is_empty():
				continue
			note(
				"%s asked for %d sides" % [shape[0], sides],
				(
					"stores sides %d, builds %d faces / %d triangles"
					% [made["sides_stored"], made["faces"], made["triangles"]]
				)
			)
			counts.append(int(made["faces"]))
		var varies := false
		for c in counts:
			if c != counts[0]:
				varies = true
		if not varies and counts.size() > 1 and shape[1] != PYRAMID:
			known(
				482,
				"a %s is the same %d faces whatever sides it is given" % [shape[0], counts[0]],
				(
					(
						"_build_base_mesh() makes a CylinderMesh and sets height and radius and"
						+ " nothing else, so `radial_segments` stays at Godot's default of 64 -- a"
						+ " %s asked for 3, 6, 8 or 16 sides is a 64-gon every time, %d faces after"
						+ " the coplanar merge. The number is not ignored quietly either: it is"
						+ " stored on the brush, written to the .hflevel, and counted in"
						+ " HFDuplicator.shape_signature(), so two brushes that differ only in"
						+ " `sides` are the same geometry and different signatures."
						+ " PrefabFactory.create_prefab() has the same gap from the other side:"
						+ " it works out safe_sides and then sets sides = 16 on the cylinder and"
						+ " the cone regardless. The pyramid on the same run honours what it was"
						+ " asked for."
					)
					% [shape[0], counts[0]]
				)
			)
