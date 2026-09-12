extends GutTest
## What a painted face renders with.
##
## Painting a face composites its paint layers over the palette material's albedo
## image. The composite used to be built on a bare `StandardMaterial3D` carrying
## three copied scalars, so everything else about the material was thrown away,
## and a `ShaderMaterial` was silently replaced by a plain one.

const FaceData = preload("res://addons/hammerforge/face_data.gd")


func _painted_image() -> Image:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 0.0, 1.0))
	return img


func _texture(color: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _full_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.5, 0.6, 1.0)
	mat.albedo_texture = _texture(Color.BLUE)
	mat.normal_enabled = true
	mat.normal_texture = _texture(Color(0.5, 0.5, 1.0, 1.0))
	mat.normal_scale = 0.75
	mat.roughness = 0.3
	mat.roughness_texture = _texture(Color.GRAY)
	mat.metallic = 0.9
	mat.metallic_texture = _texture(Color.DARK_GRAY)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.2, 0.3)
	mat.uv1_scale = Vector3(4.0, 4.0, 1.0)
	mat.uv1_offset = Vector3(0.25, 0.5, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func test_a_painted_face_keeps_everything_but_the_albedo_texture():
	var base := _full_material()
	var painted = FaceData.composite_painted_material(base, _painted_image())
	assert_true(painted is StandardMaterial3D, "The composite is a standard material")
	var std: StandardMaterial3D = painted
	assert_ne(std, base, "and not the palette material itself")
	assert_ne(std.albedo_texture, base.albedo_texture, "The albedo is the composited image")
	assert_eq(std.normal_texture, base.normal_texture, "The normal map survives")
	assert_almost_eq(std.normal_scale, 0.75, 0.001, "and its scale")
	assert_eq(std.roughness_texture, base.roughness_texture, "The roughness map survives")
	assert_eq(std.metallic_texture, base.metallic_texture, "and the metallic map")
	assert_eq(std.emission, base.emission, "The emission survives")
	assert_eq(std.uv1_scale, Vector3(4.0, 4.0, 1.0), "and the UV scale, which is the visible one")
	assert_eq(std.uv1_offset, Vector3(0.25, 0.5, 0.0), "and the UV offset")
	assert_eq(std.cull_mode, BaseMaterial3D.CULL_DISABLED, "and the cull mode")
	assert_almost_eq(std.roughness, 0.3, 0.001, "The three that were kept before are still kept")
	assert_almost_eq(std.metallic, 0.9, 0.001)
	assert_eq(std.albedo_color, base.albedo_color)


func test_painting_does_not_write_back_into_the_palette_material():
	var base := _full_material()
	var before := base.albedo_texture
	FaceData.composite_painted_material(base, _painted_image())
	assert_eq(base.albedo_texture, before, "The palette material is untouched")


func test_a_shader_material_is_kept_rather_than_replaced():
	# The atlas already refuses a ShaderMaterial rather than pretending it can
	# pack one. Building a plain StandardMaterial3D here left one baked surface
	# flat beside its neighbours with the shader gone and nothing said.
	var shader := ShaderMaterial.new()
	shader.shader = Shader.new()
	var painted = FaceData.composite_painted_material(shader, _painted_image())
	assert_eq(painted, shader, "The shader material comes back as it was")


func test_a_face_with_no_palette_material_still_gets_the_paint():
	var painted = FaceData.composite_painted_material(null, _painted_image())
	assert_true(painted is StandardMaterial3D, "The composite is the whole surface")
	assert_not_null(painted.albedo_texture, "and carries the painted albedo")


func test_no_painted_image_means_no_composite():
	var base := _full_material()
	assert_eq(
		FaceData.composite_painted_material(base, null),
		base,
		"An unpainted face keeps its material"
	)


func _painted_face() -> FaceData:
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	)
	face.ensure_geometry()
	var layer := FaceData.PaintLayer.new()
	layer.texture = _texture(Color.RED)
	layer.ensure_weight_image(Vector2i(16, 16))
	layer.weight_image.fill(Color(1, 1, 1, 1))
	face.paint_layers = [layer]
	return face


func test_the_bake_resolves_a_painted_face_the_same_way():
	# The composite the bake writes is the one people spend an afternoon on
	# before finding this: the normal map going missing, and the UV scale going
	# back to 1 so the painted face's texture is four times the size of the one
	# beside it.
	var baker = preload("res://addons/hammerforge/baker.gd").new()
	add_child_autoqfree(baker)
	var base := _full_material()
	var resolved = baker._resolve_face_material(_painted_face(), null, base, null)
	assert_true(resolved is StandardMaterial3D, "A painted face bakes to a standard material")
	assert_eq(resolved.normal_texture, base.normal_texture, "with its normal map")
	assert_eq(resolved.uv1_scale, base.uv1_scale, "and its UV scale")
	assert_ne(resolved.albedo_texture, base.albedo_texture, "and the painted albedo on it")


func test_the_bake_keeps_a_shader_material_on_a_painted_face():
	var baker = preload("res://addons/hammerforge/baker.gd").new()
	add_child_autoqfree(baker)
	var shader := ShaderMaterial.new()
	shader.shader = Shader.new()
	var resolved = baker._resolve_face_material(_painted_face(), null, shader, null)
	assert_eq(resolved, shader, "The shader survives the bake rather than being substituted")
