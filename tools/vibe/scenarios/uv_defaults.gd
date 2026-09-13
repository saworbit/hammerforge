@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The UVs a brush is born with, measured face by face.
##
## Every other scenario that touches texturing sets a projection first. This one
## never does: it makes the brushes the Draw tool makes and asks what the
## texture on each face would look like, by measuring the UV parallelogram each
## triangle is mapped onto. A face whose triangles have world area and no UV
## area cannot show a texture -- one row of texels is stretched across the whole
## face, which is what "smeared" means when a mapper says it.
##
## `FaceData.uv_projection` defaults to `PLANAR_Z`, and `_build_box_faces()`
## hands every face a `FaceData.new()`.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

## shape id -> label, from LevelRoot.BrushShape.
const SHAPES := {
	0: "box",
	1: "cylinder",
	2: "sphere",
	4: "wedge",
	5: "pyramid",
}


func id() -> String:
	return "uv-defaults"


func summary() -> String:
	return "whether a brush's faces are born with a projection that can show a texture"


func run() -> void:
	await _every_shape_as_drawn()
	await _what_the_box_uv_button_does()


## The UV area a face's triangles cover, against the world area they cover.
##
## The ratio is texels per square unit. Zero means the projection is edge on to
## the face: every point of the face samples the same line of the texture.
func _uv_against_world(face) -> Dictionary:
	var tri: Dictionary = face.triangulate()
	var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
	var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
	var world_area := 0.0
	var uv_area := 0.0
	if verts.size() < 3 or uvs.size() != verts.size():
		return {"world": 0.0, "uv": 0.0}
	for t in range(verts.size() / 3):
		var i := t * 3
		world_area += 0.5 * (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).length()
		var a: Vector2 = uvs[i + 1] - uvs[i]
		var b: Vector2 = uvs[i + 2] - uvs[i]
		uv_area += 0.5 * absf(a.x * b.y - a.y * b.x)
	return {"world": world_area, "uv": uv_area}


func _flat_faces(root: Node3D, shape: int) -> Array:
	var brush = root.create_brush_from_info({"shape": shape, "size": Vector3(128, 64, 32)})
	await frame()
	var out: Array = []
	if brush == null:
		return out
	for i in range(brush.get_faces().size()):
		var face = brush.get_faces()[i]
		var measured: Dictionary = _uv_against_world(face)
		(
			out
			. append(
				{
					"index": i,
					"normal": face.normal,
					"projection": face.uv_projection,
					"world": measured["world"],
					"uv": measured["uv"],
				}
			)
		)
	return out


func _every_shape_as_drawn() -> void:
	var root: Node3D = await fresh_root("UVLevel")
	note("FaceData.uv_projection default", FaceData.new().uv_projection)
	for shape in SHAPES:
		var faces: Array = await _flat_faces(root, int(shape))
		var flat := 0
		var total := 0
		var examples: Array = []
		for entry in faces:
			if float(entry["world"]) <= 0.0001:
				continue
			total += 1
			if float(entry["uv"]) <= 0.0001:
				flat += 1
				if examples.size() < 3:
					examples.append(
						(
							"face %d (normal %s)"
							% [entry["index"], entry["normal"].snapped(Vector3.ONE * 0.01)]
						)
					)
		note("%s: faces with no UV area" % SHAPES[shape], "%d of %d  %s" % [flat, total, examples])
		if flat > 0:
			flag(
				"a new %s has %d face(s) no texture can be seen on" % [SHAPES[shape], flat],
				(
					"FaceData.uv_projection defaults to PLANAR_Z -- (x, y) -> (u, v) -- and"
					+ " nothing sets a projection when a brush is made. A mesh-built shape keeps"
					+ " the source mesh's UVs wherever _face_from_ids() can carry them, which is"
					+ " why a sphere is fine; every face that falls back to the projection gets"
					+ " PLANAR_Z. On any such face whose plane contains the Z axis, or that lies"
					+ " flat in Y, one of the two UV axes is constant across the whole face, so"
					+ " it samples a single line of the texture and renders as streaks. It is on the baked"
					+ " mesh, not only in the preview: baker._build_face_groups() takes the"
					+ " same triangulate() UVs. The dock has a Box UV re-projection the mapper"
					+ " can apply by hand afterwards, per face, which is the fix being done"
					+ " manually. Examples: "
					+ str(examples)
				)
			)


## The same box with the projection the dock's re-project button applies, to
## show the defect is the default rather than the projector.
func _what_the_box_uv_button_does() -> void:
	var root: Node3D = await fresh_root("UVLevelB")
	var brush = root.create_brush_from_info({"shape": 0, "size": Vector3(128, 64, 32)})
	await frame()
	var before := 0
	var after := 0
	for face in brush.get_faces():
		if float(_uv_against_world(face)["uv"]) <= 0.0001:
			before += 1
	for face in brush.get_faces():
		face.uv_projection = FaceData.UVProjection.BOX_UV
		face.custom_uvs = PackedVector2Array()
	for face in brush.get_faces():
		if float(_uv_against_world(face)["uv"]) <= 0.0001:
			after += 1
	note("box faces with no UV area, as drawn", before)
	note("box faces with no UV area, after Box UV", after)

	# Texture lock reads the same field. A projection that does not contain the
	# face cannot be world locked through a turn either, so the lock declines.
	var top = brush.get_faces()[2]
	note("the top face's projection, as drawn", top.uv_projection)
	var locked: bool = top.adjust_uvs_for_rotation(Basis(Vector3.UP, deg_to_rad(90.0)))
	note("texture lock compensates the top face of a default box under a yaw", locked)
	if not locked:
		flag(
			"texture lock declines on a face of a brush nobody has re-projected",
			(
				"adjust_uvs_for_rotation() refuses any face whose projection plane the turn"
				+ " takes away. A projection that does not contain the face cannot be world"
				+ " locked through a turn, so a rotate with texture lock on changes nothing."
			)
		)
	var planar = brush.get_faces()[3]
	planar.uv_projection = FaceData.UVProjection.PLANAR_Z
	note(
		"the same turn on a face forced back to PLANAR_Z",
		planar.adjust_uvs_for_rotation(Basis(Vector3.UP, deg_to_rad(90.0)))
	)
	top.uv_projection = FaceData.UVProjection.BOX_UV
	var locked_box: bool = top.adjust_uvs_for_rotation(Basis(Vector3.UP, deg_to_rad(90.0)))
	note("the same face with Box UV", locked_box)
