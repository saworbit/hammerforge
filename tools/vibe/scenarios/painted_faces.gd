@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What painting on a face does to the material that face already had.
##
## Surface paint composites its layers into one albedo image, and both the
## editor preview (`brush_instance._material_for_face`) and the bake
## (`baker._resolve_face_material`) then build a fresh `StandardMaterial3D`
## around that image. The question is what of the original material comes across
## when they do -- a palette material is not only an albedo colour.

const SurfacePaint = preload("res://addons/hammerforge/surface_paint.gd")


func id() -> String:
	return "painted-faces"


func summary() -> String:
	return "what a painted face keeps of the material it was painted over"


func run() -> void:
	await _painting_over_a_full_pbr_material()
	await _painting_over_a_shader_material()
	await _paint_input_at_its_edges()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _checker(colour: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return ImageTexture.create_from_image(img)


## A palette material with every slot a mapper is likely to set.
func _full_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	mat.albedo_texture = _checker(Color(0.8, 0.2, 0.2))
	mat.normal_enabled = true
	mat.normal_texture = _checker(Color(0.5, 0.5, 1.0))
	mat.normal_scale = 0.75
	mat.roughness = 0.25
	mat.roughness_texture = _checker(Color(0.4, 0.4, 0.4))
	mat.metallic = 0.5
	mat.metallic_texture = _checker(Color(0.2, 0.2, 0.2))
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.4, 0.9)
	mat.uv1_scale = Vector3(4, 4, 1)
	mat.uv1_offset = Vector3(0.25, 0.25, 0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _paint_face(brush: Node, face_index: int) -> void:
	var painter = SurfacePaint.new()
	var face = brush.faces[face_index]
	painter.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 1.0)


## The baked surface materials under a node, by name of what they are.
func _baked_materials(root: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
			if child is MeshInstance3D and child.mesh != null:
				var mi := child as MeshInstance3D
				for s in range(mi.mesh.get_surface_count()):
					var mat = mi.mesh.surface_get_material(s)
					if mat == null:
						mat = mi.get_surface_override_material(s)
					if mat != null:
						out.append(mat)
	return out


func _painting_over_a_full_pbr_material() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var source := _full_material()
	var idx: int = root.add_material_to_palette(source)
	note("palette index", idx)
	for face in b.faces:
		face.material_idx = idx
	await frame()

	await root.bake_dirty()
	await frame()
	var before := _baked_materials(root)
	note("baked surface materials before painting", before.size())
	var kept_before := 0
	for m in before:
		if m == source:
			kept_before += 1
	note("baked surfaces still carrying the palette material itself", kept_before)

	_paint_face(b, 0)
	if b.has_method("rebuild_preview"):
		b.rebuild_preview()
	await frame()
	root.tag_full_reconcile()
	await root.bake_dirty()
	await frame()

	var after := _baked_materials(root)
	note("baked surface materials after painting one face", after.size())
	var painted_mat: Material = null
	for m in after:
		if m != source and m is StandardMaterial3D:
			painted_mat = m
	if painted_mat == null:
		note("no separate material was produced for the painted face")
		return

	var std := painted_mat as StandardMaterial3D
	var lost: Array = []
	if std.normal_texture != source.normal_texture:
		lost.append("normal_texture")
	if not is_equal_approx(std.normal_scale, source.normal_scale):
		lost.append("normal_scale")
	if std.roughness_texture != source.roughness_texture:
		lost.append("roughness_texture")
	if std.metallic_texture != source.metallic_texture:
		lost.append("metallic_texture")
	if std.emission != source.emission or std.emission_enabled != source.emission_enabled:
		lost.append("emission")
	if std.uv1_scale != source.uv1_scale:
		lost.append("uv1_scale")
	if std.uv1_offset != source.uv1_offset:
		lost.append("uv1_offset")
	if std.cull_mode != source.cull_mode:
		lost.append("cull_mode")
	note(
		(
			"kept: roughness %s, metallic %s, albedo_color %s"
			% [
				is_equal_approx(std.roughness, source.roughness),
				is_equal_approx(std.metallic, source.metallic),
				std.albedo_color == source.albedo_color,
			]
		)
	)
	note("dropped by the painted-face material", lost)
	if not lost.is_empty():
		known(
			412,
			"painting on a face throws away everything about its material except three scalars",
			(
				"_resolve_face_material() (and _material_for_face() in the editor) build a new"
				+ " StandardMaterial3D around the composited albedo and copy only roughness,"
				+ " metallic and albedo_color from the original. Dropped: %s" % str(lost)
			)
		)


## The same path with a `ShaderMaterial` in the palette: the `is`
## StandardMaterial3D check fails and nothing at all is carried across.
func _painting_over_a_shader_material() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.1, 0.9, 0.2); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var idx: int = root.add_material_to_palette(mat)
	for face in b.faces:
		face.material_idx = idx
	_paint_face(b, 0)
	await frame()
	root.tag_full_reconcile()
	await root.bake_dirty()
	await frame()

	var materials := _baked_materials(root)
	var shader_surfaces := 0
	var replaced := 0
	for m in materials:
		if m == mat:
			shader_surfaces += 1
		elif m is StandardMaterial3D:
			replaced += 1
	note("baked surfaces keeping the shader material", shader_surfaces)
	note("baked surfaces replaced by a plain StandardMaterial3D", replaced)
	if replaced > 0:
		known(
			413,
			"painting on a face with a ShaderMaterial replaces it with a plain material",
			(
				"the painted branch builds a StandardMaterial3D and only copies from the base"
				+ " when the base `is StandardMaterial3D`, so a shader material is dropped"
				+ " outright: %d surface(s) came back plain. Nothing warns, and the face" % replaced
				+ " renders unlit-flat next to its neighbours."
			)
		)


## What `SurfacePaint.paint_at_uv()` does with numbers outside the range the UI
## hands it. UVs leave that range the moment a face tiles its texture, and the
## strength and radius come from dock controls.
func _paint_input_at_its_edges() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var painter = SurfacePaint.new()
	var face = b.faces[0]

	painter.paint_at_uv(face, 0, Vector2(0.5, 0.5), 0.25, 1.0)
	var img: Image = face.paint_layers[0].weight_image
	note("layer size", img.get_size())
	note("centre pixel after a normal stroke", img.get_pixel(128, 128))

	# A tiled face: the UV the picker returns is outside 0-1.
	var before_edge := img.get_pixel(255, 255)
	painter.paint_at_uv(face, 0, Vector2(2.5, 2.5), 0.25, 1.0)
	var after_edge := img.get_pixel(255, 255)
	note(
		"corner pixel before / after a stroke at uv (2.5, 2.5)",
		"%s / %s" % [before_edge, after_edge]
	)
	if before_edge == after_edge:
		note(
			"a UV outside 0-1 paints nothing at all",
			(
				"not a finding: paint_surface_at() clamps the UV into range before it gets here,"
				+ " so the only way in is a direct call. Worth knowing the boundary is the"
				+ " caller's rather than the painter's."
			)
		)

	# Non-finite strength: nothing guards the arithmetic.
	painter.paint_at_uv(face, 0, Vector2(0.25, 0.25), 0.1, NAN)
	var nan_pixel := img.get_pixel(64, 64)
	note("pixel painted with strength NAN", nan_pixel)
	if is_nan(nan_pixel.r):
		flag(
			"a non-finite paint strength writes NaN into the weight image",
			(
				"clamp() passes NaN through, so `img.set_pixel(x, y, Color(next, ...))` stores"
				+ " it. Every later composite of that layer is NaN from there on, and the"
				+ " weight image is what a .hflevel save writes out."
			)
		)

	# A negative radius: max(1.0, ...) makes it one pixel rather than a refusal.
	var before_neg := img.get_pixel(192, 192)
	painter.paint_at_uv(face, 0, Vector2(0.75, 0.75), -4.0, 1.0)
	note(
		"pixel at uv (0.75, 0.75) before / after a stroke with radius -4",
		"%s / %s" % [before_neg, img.get_pixel(192, 192)]
	)
