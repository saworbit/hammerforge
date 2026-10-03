extends GutTest

## What a .map face line has to carry: the face's own texture and UV numbers,
## and one plane per flat surface rather than one per triangle of it.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const MapIOType = preload("res://addons/hammerforge/map_io.gd")
const QuakeAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")
const Valve220Adapter = preload("res://addons/hammerforge/map_adapters/hf_map_valve220.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.material_manager.clear()


func _make_material(mat_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	return mat


## A material whose albedo texture is `width` by `height` pixels.
func _textured(mat_name: String, width: int, height: int) -> StandardMaterial3D:
	var mat := _make_material(mat_name)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	mat.albedo_texture = ImageTexture.create_from_image(image)
	return mat


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"size": Vector3(32, 32, 32), "center": Vector3.ZERO, "brush_id": brush_id}
		)
		as DraftBrush
	)


## The rotation, u scale and v scale that close a face line. Both formats end on
## the same three numbers, so one reader serves both.
func _uv_tail(line: String) -> Array:
	var parts := line.split(" ", false)
	return [
		float(parts[parts.size() - 3]),
		float(parts[parts.size() - 2]),
		float(parts[parts.size() - 1]),
	]


## The face lines of the exported text, in order.
func _face_lines(text: String) -> Array:
	var out: Array = []
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("("):
			out.append(line)
	return out


## The texture token of a face line: the word after the third closing bracket.
func _texture_of(line: String) -> String:
	var tail: String = line.substr(line.rfind(")") + 1).strip_edges()
	var parts := tail.split(" ", false)
	return str(parts[0]) if parts.size() > 0 else ""


# -- The texture name reaches the file ---------------------------------------


func test_an_assigned_material_is_written_on_every_face():
	root.add_material_to_palette(_make_material("bricks"))
	_box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	assert_eq(lines.size(), 6, "A box is six planes")
	for line in lines:
		assert_eq(_texture_of(line), "bricks", "Each face should name its material")


func test_an_unset_face_falls_back_to_the_default_texture():
	root.add_material_to_palette(_make_material("bricks"))
	_box("b1")

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		assert_eq(_texture_of(line), "__default", "An unassigned face has no material to name")


func test_an_out_of_range_index_falls_back_to_the_default_texture():
	var brush := _box("b1")
	for face in brush.faces:
		face.material_idx = 7

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		assert_eq(_texture_of(line), "__default", "An index past the palette names nothing")


func test_a_name_with_a_space_is_written_as_one_token():
	assert_eq(MapIOType.texture_token("Red Brick"), "Red_Brick", "Spaces would split the field")
	assert_eq(MapIOType.texture_token("  padded  name "), "padded_name", "Runs collapse to one")
	assert_eq(MapIOType.texture_token(""), "__default", "An empty name has no token")


func test_the_uv_numbers_are_the_face_s_own():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_offset = Vector2(0.25, 0.5)
		face.uv_scale = Vector2(2, 4)
		face.uv_rotation = deg_to_rad(45.0)

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new(), 32.0))

	# In texels of a texture taken as 64 pixels, at 32 units a metre.
	for line in lines:
		assert_true(
			line.ends_with("bricks 16 32 45 0.25 0.125"),
			"Face line should carry its UVs in .map units, got: %s" % line
		)


## A `.map` rotation field is degrees. `FaceData.uv_rotation` is radians, because
## `_apply_uv_transform()` calls `Vector2.rotated()`. Writing the radians out is a
## factor of 57.3: every rotated face arrives effectively unrotated.
func test_a_rotated_face_exports_its_rotation_in_degrees():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_rotation = deg_to_rad(45.0)

	for adapter in [QuakeAdapter.new(), Valve220Adapter.new()]:
		for line in _face_lines(MapIOType.export_map_from_level(root, adapter)):
			var tail := _uv_tail(line)
			assert_almost_eq(
				tail[0],
				45.0,
				0.01,
				"%s wrote the rotation in radians: %s" % [adapter.format_name(), line]
			)


## A `.map` scale divides and `uv_scale` multiplies, so the two are reciprocal.
## Exporting the value unchanged puts the tiling out by the square of it.
func test_a_scaled_face_exports_the_reciprocal_scale():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_scale = Vector2(2, 2)

	for adapter in [QuakeAdapter.new(), Valve220Adapter.new()]:
		for line in _face_lines(MapIOType.export_map_from_level(root, adapter, 32.0)):
			var tail := _uv_tail(line)
			assert_almost_eq(tail[1], 0.25, 0.0001, "u scale of 2 is 0.25 in a .map: %s" % line)
			assert_almost_eq(tail[2], 0.25, 0.0001, "v scale of 2 is 0.25 in a .map: %s" % line)


## A `.map` offset and scale are texels: the reader divides by the texture's size
## after it divides by the scale, so one repeat spans `size * scale` units. A
## face at the default repeats once a metre, 32 units, which on a 64 pixel
## texture is half a unit a texel. Written as 32, it was 64 times too large in
## another editor (#894).
func test_the_default_alignment_is_written_in_texels():
	root.add_material_to_palette(_textured("bricks", 64, 64))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])

	for adapter in [QuakeAdapter.new(), Valve220Adapter.new()]:
		for line in _face_lines(MapIOType.export_map_from_level(root, adapter, 32.0)):
			var tail := _uv_tail(line)
			assert_almost_eq(tail[1], 0.5, 0.0001, "u scale on a 64 pixel texture: %s" % line)
			assert_almost_eq(tail[2], 0.5, 0.0001, "v scale on a 64 pixel texture: %s" % line)

	for face in brush.faces:
		face.uv_offset = Vector2(0.25, 0.5)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new(), 32.0))
	for line in lines:
		assert_true(line.ends_with("bricks 16 32 0 0.5 0.5"), "offset in texels: %s" % line)


## Each axis is counted in texels of its own side of the texture.
func test_a_texture_that_is_not_square_is_counted_along_each_side():
	root.add_material_to_palette(_textured("tiles", 128, 32))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_offset = Vector2(0.25, 0.5)

	for line in _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new(), 32.0)):
		assert_true(line.ends_with("tiles 32 16 0 0.25 1"), "128 by 32 pixels: %s" % line)


## Every Quake family reader divides by the texture scale, so a zero there is a
## divide by zero at load. The default scale keeps the file loadable.
func test_a_uv_scale_of_zero_exports_as_the_default():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_scale = Vector2.ZERO

	for adapter in [QuakeAdapter.new(), Valve220Adapter.new()]:
		for line in _face_lines(MapIOType.export_map_from_level(root, adapter, 32.0)):
			var tail := _uv_tail(line)
			assert_almost_eq(tail[1], 0.5, 0.0001, "a zero scale is substituted: %s" % line)
			assert_almost_eq(tail[2], 0.5, 0.0001, "a zero scale is substituted: %s" % line)


## `adjust_uvs_for_rotation()` writes a negative scale on purpose when a turn
## flips the projection plane, and a negative scale mirrors the texture in a
## `.map`. It has to survive the inversion with its sign.
func test_a_negative_uv_scale_stays_negative():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_scale = Vector2(1, -2)

	for adapter in [QuakeAdapter.new(), Valve220Adapter.new()]:
		for line in _face_lines(MapIOType.export_map_from_level(root, adapter, 32.0)):
			var tail := _uv_tail(line)
			assert_almost_eq(tail[2], -0.25, 0.0001, "a mirrored face stays mirrored: %s" % line)


# -- One plane per flat surface ----------------------------------------------


func test_a_cylinder_exports_one_plane_per_wall_and_one_per_cap():
	for sides in [6, 8, 16]:
		root.clear_brushes()
		root.create_brush_from_info(
			{
				"size": Vector3(32, 32, 32),
				"center": Vector3.ZERO,
				"shape": LevelRootType.BrushShape.CYLINDER,
				"sides": sides
			}
		)
		var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))
		assert_eq(lines.size(), sides + 2, "A %d sided prism needs %d planes" % [sides, sides + 2])


## The default brush has `sides` 4 and `DraftBrush.round_sides()` resolves that to
## 16, which is what the viewport draws and what the bake builds. The export used
## to floor it at 6 and write a hexagon instead.
func test_a_default_cylinder_exports_at_the_resolution_it_is_drawn_at():
	(
		root
		. create_brush_from_info(
			{
				"size": Vector3(32, 32, 32),
				"center": Vector3.ZERO,
				"shape": LevelRootType.BrushShape.CYLINDER,
			}
		)
	)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	assert_eq(
		lines.size(),
		DraftBrush.DEFAULT_ROUND_SIDES + 2,
		"the exported prism has to be the cylinder that was on screen"
	)


## `MIN_ROUND_SIDES` is 5 and the brush honours it. The export clamped it to 6.
func test_a_five_sided_cylinder_exports_five_walls():
	root.create_brush_from_info(
		{
			"size": Vector3(32, 32, 32),
			"center": Vector3.ZERO,
			"shape": LevelRootType.BrushShape.CYLINDER,
			"sides": 5
		}
	)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	assert_eq(lines.size(), 7, "five walls and two caps")


func test_no_two_cylinder_planes_are_the_same_plane():
	root.create_brush_from_info(
		{
			"size": Vector3(32, 32, 32),
			"center": Vector3.ZERO,
			"shape": LevelRootType.BrushShape.CYLINDER,
			"sides": 16
		}
	)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	var seen: Dictionary = {}
	for line in lines:
		var plane := _plane_of(line)
		var key := "%s|%.2f" % [MapIOType.normal_key(plane.normal), plane.d]
		assert_false(seen.has(key), "Two face lines describe the same plane: %s" % line)
		seen[key] = true


func test_every_cylinder_plane_faces_away_from_the_brush():
	root.create_brush_from_info(
		{
			"size": Vector3(32, 32, 32),
			"center": Vector3.ZERO,
			"shape": LevelRootType.BrushShape.CYLINDER,
			"sides": 8
		}
	)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		var plane := _plane_of(line)
		assert_gt(plane.d, 0.0, "The plane should be reached going out from the centre: %s" % line)


# -- Each cylinder plane carries the face that lies on it (#880) --------------

## Far enough off a face that it is another face's plane. Three-decimal points
## tilt a turned cap by about 0.02 at the rim of these cylinders, and the nearest
## wrong face in any of them is more than a unit away.
const OFF_FACE := 0.05


## A cylinder with each face named after its index, off the origin so that a
## plane written through the wrong point cannot pass for a right one.
func _named_cylinder(sides: int) -> DraftBrush:
	var brush := (
		root.create_brush_from_info(
			{
				"size": Vector3(32, 32, 32),
				"center": Vector3(5, 2, -3),
				"shape": LevelRootType.BrushShape.CYLINDER,
				"sides": sides
			}
		)
		as DraftBrush
	)
	for i in range(brush.faces.size()):
		brush.faces[i].map_texture = "face%d" % i
	return brush


## Every plane the export wrote with a face that does not lie on it, as
## "line: the face named, how far off". The plane is read back out of the line
## the way a .map reader reads it, rather than taken from the exporter.
func _planes_off_their_face(brush: DraftBrush) -> Array:
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))
	assert_eq(lines.size(), brush.faces.size(), "one plane per face")
	var off: Array = []
	for line in lines:
		var plane := _plane_of(line)
		var texture := _texture_of(line)
		var face: FaceData = brush.faces[int(texture.trim_prefix("face"))]
		var worst := 0.0
		for corner in face.local_verts:
			worst = maxf(worst, absf(plane.distance_to(brush.global_transform * corner)))
		if worst > OFF_FACE:
			off.append("%s: %s is %.2f off" % [line, texture, worst])
	return off


## Faces and bake come from Godot's `CylinderMesh`, which starts its ring on +Z.
## The export started on +X, which has the same corners only when the side count
## is a multiple of four, so the other cylinders exported turned against the one
## on screen with no plane on any face.
func test_a_cylinder_of_any_side_count_exports_the_prism_on_screen():
	for sides in [5, 6, 7, 9, 10, 16]:
		root.clear_brushes()
		var brush := _named_cylinder(sides)
		assert_eq(_planes_off_their_face(brush), [], "%d sides" % sides)


## A normal does not follow the basis under an uneven scale. It leans towards the
## stretched axis, and the nearest leaning normal was a neighbouring side's.
func test_a_stretched_cylinder_writes_each_plane_with_its_own_face():
	for sides in [6, 16]:
		for stretch in [Vector3(4, 1, 1), Vector3(1, 1, 4), Vector3(2, 3, 0.5)]:
			root.clear_brushes()
			var brush := _named_cylinder(sides)
			brush.scale = stretch

			assert_eq(_planes_off_their_face(brush), [], "%d sides at %s" % [sides, stretch])


func test_a_turned_cylinder_writes_each_plane_with_its_own_face():
	for stretch in [Vector3.ONE, Vector3(2, 3, 0.5)]:
		root.clear_brushes()
		var brush := _named_cylinder(16)
		brush.rotation = Vector3(0.3, 0.7, -0.4)
		brush.scale = stretch

		assert_eq(_planes_off_their_face(brush), [], "turned, at %s" % stretch)


## A turned brush under a stretched parent is sheared, which no scale and turn of
## its own can be. The match is made before any of it applies.
func test_a_cylinder_under_a_stretched_parent_writes_each_plane_with_its_own_face():
	var brush := _named_cylinder(16)
	brush.rotation = Vector3(0, 0.5, 0)
	root.scale = Vector3(3, 1, 1)
	var basis := brush.global_transform.basis
	assert_gt(absf(basis.x.dot(basis.z)), 1.0, "the brush is sheared")

	assert_eq(_planes_off_their_face(brush), [])


## The plane a face line describes, read the way a .map reader reads it.
func _plane_of(line: String) -> Plane:
	var re := RegEx.new()
	re.compile("\\(([^\\)]+)\\)")
	var matches := re.search_all(line)
	var pts: Array = []
	for i in range(3):
		var parts := matches[i].get_string(1).strip_edges().split(" ", false)
		pts.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	var normal: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	return Plane(normal, normal.dot(pts[0]))


# -- Round trip ---------------------------------------------------------------


func test_a_box_material_survives_an_export_and_import():
	root.add_material_to_palette(_make_material("floor"))
	root.add_material_to_palette(_make_material("wall"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(1, ["b1"])
	var path := "user://hf_test_map_fidelity.map"
	assert_eq(root.export_map(path), OK, "Export should succeed")

	assert_eq(root.import_map(path), OK, "Import should succeed")

	var imported: Array = root.get_all_draft_brushes()
	assert_eq(imported.size(), 1, "One brush should come back")
	for face in imported[0].faces:
		assert_eq(face.material_idx, 1, "Each face should point back at 'wall'")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_per_face_materials_survive_an_export_and_import():
	root.add_material_to_palette(_make_material("floor"))
	root.add_material_to_palette(_make_material("wall"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(1, ["b1"])
	# Face 2 is the top of the box. Give it a different material from the rest.
	brush.faces[2].material_idx = 0
	var top_normal: Vector3 = brush.faces[2].normal
	var path := "user://hf_test_map_fidelity_perface.map"
	root.export_map(path)

	root.import_map(path)

	var imported: Array = root.get_all_draft_brushes()
	var found_top := false
	for face in imported[0].faces:
		if face.normal.dot(top_normal) > 0.99:
			found_top = true
			assert_eq(face.material_idx, 0, "The top should come back as 'floor'")
		else:
			assert_eq(face.material_idx, 1, "and every other face as 'wall'")
	assert_true(found_top, "The top face should be among the imported faces")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A texture the palette does not hold used to leave the face unset, and the name
## with it, so a fresh import -- which is always into an empty palette -- dropped
## every texture in the file and exported `__default` back (#662). The name is
## kept on the face now, and mints a placeholder slot so the palette mirrors the
## file. A placeholder carries no resource path: a `.map` names a texture without
## saying where it lives, and guessing would put a broken reference on the face.
func test_a_texture_the_palette_does_not_hold_is_minted_rather_than_dropped():
	root.add_material_to_palette(_make_material("wall"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	var path := "user://hf_test_map_fidelity_unknown.map"
	root.export_map(path)
	# The palette the file was written against is gone by the time it is read.
	root.material_manager.clear()
	root.add_material_to_palette(_make_material("something_else"))

	root.import_map(path)

	var imported: Array = root.get_all_draft_brushes()
	assert_eq(imported.size(), 1, "The brush should still import")
	assert_has(root.get_material_names(), "wall", "the name the file used is in the palette")
	for face in imported[0].faces:
		assert_eq(str(face.map_texture), "wall", "and the face records what it was called")
		assert_ne(face.material_idx, -1, "pointing at the slot minted for it")
		var slot: Material = root.material_manager.get_material(face.material_idx)
		assert_not_null(slot, "the slot holds a placeholder")
		assert_eq(
			slot.resource_path,
			"",
			"with no resource path, because the file did not say where the texture lives"
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_texture_token_is_read_off_a_face_line():
	var parsed := MapIOType.parse_map_text(
		(
			"{\n"
			+ '"classname" "worldspawn"\n'
			+ "{\n"
			+ "( 16 -16 -16 ) ( 16 16 -16 ) ( 16 16 16 ) my_tex 1 2 3 4 5\n"
			+ "}\n"
			+ "}"
		)
	)

	assert_eq(parsed["errors"].size(), 0, "The line should parse")


# -- Alignment comes back (#885) ----------------------------------------------


## Different numbers on every face, so a face that came back with a neighbour's
## alignment cannot pass.
func _align_every_face(brush: DraftBrush) -> void:
	for i in brush.faces.size():
		var face: FaceData = brush.faces[i]
		face.uv_offset = Vector2(0.25 + 0.03 * i, 0.5 - 0.02 * i)
		face.uv_scale = Vector2(2.0 + 0.25 * i, 1.5 - 0.05 * i)
		face.uv_rotation = 0.5 - 0.07 * i
	brush.rebuild_preview()


## What each face looks like and which way it faces, kept apart from the brush.
func _copies_of(faces: Array) -> Array:
	var out: Array = []
	for face in faces:
		var copy := FaceData.new()
		copy.normal = face.normal
		copy.copy_appearance_from(face)
		out.append(copy)
	return out


## The face of `brush` that faces the way `normal` does.
func _face_facing(brush: DraftBrush, normal: Vector3) -> FaceData:
	for face in brush.faces:
		if face.normal.dot(normal) > 0.999:
			return face
	return null


func _assert_same_alignment(got: FaceData, want: FaceData, what: String) -> void:
	assert_almost_eq(got.uv_offset, want.uv_offset, Vector2.ONE * 0.001, "%s offset" % what)
	assert_almost_eq(got.uv_scale, want.uv_scale, Vector2.ONE * 0.001, "%s scale" % what)
	assert_almost_eq(got.uv_rotation, want.uv_rotation, 0.001, "%s rotation" % what)


func test_every_face_s_alignment_survives_an_export_and_import():
	# Counted in texels of each side of the texture on the way out and back, so a
	# texture that is not square is in here as well as one with no size (#894).
	for material in [_make_material("bricks"), _textured("tiles", 128, 32)]:
		root.material_manager.clear()
		root.add_material_to_palette(material)
		for format in ["quake", "valve220"]:
			root.clear_brushes()
			# Away from the origin, so an offset folded with the brush's placement
			# on the way in would show.
			var box := (
				root.create_brush_from_info(
					{"size": Vector3(32, 32, 32), "center": Vector3(40, 8, -24), "brush_id": "box"}
				)
				as DraftBrush
			)
			var cylinder := (
				(
					root
					. create_brush_from_info(
						{
							"shape": LevelRootType.BrushShape.CYLINDER,
							"sides": 16,
							"size": Vector3(32, 32, 32),
							"center": Vector3(-60, 0, 30),
							"brush_id": "cyl",
						}
					)
				)
				as DraftBrush
			)
			root.assign_material_to_whole_brushes(0, ["box", "cyl"])
			_align_every_face(box)
			_align_every_face(cylinder)
			var wanted := {"box": _copies_of(box.faces), "cylinder": _copies_of(cylinder.faces)}
			var path := "user://hf_test_map_alignment_%s.map" % format
			assert_eq(root.export_map(path, format), OK, "%s export" % format)

			assert_eq(root.import_map(path), OK, "%s import" % format)

			var imported: Array = root.get_all_draft_brushes()
			assert_eq(imported.size(), 2, "%s: both brushes come back" % format)
			for brush in imported:
				var which := "box" if brush.global_position.x > 0.0 else "cylinder"
				var originals: Array = wanted[which]
				assert_eq(brush.faces.size(), originals.size(), "%s: face count" % format)
				for original in originals:
					var got := _face_facing(brush, original.normal)
					assert_not_null(got, "%s: a face facing %s" % [format, original.normal])
					if got:
						_assert_same_alignment(
							got, original, "%s %s %s" % [format, which, original.normal]
						)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A one box file exported at 32 units to the metre, with every face line's
## numbers replaced by `tail`. Without the `_hf_` keys it is a file HammerForge
## did not write: nothing else in it says where it came from.
func _one_box_map(written_here: bool, tail: String) -> String:
	_box("b1")
	var text := MapIOType.export_map_from_level(root, QuakeAdapter.new(), 32.0, true)
	root.clear_brushes()
	var out: Array = []
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with('"_hf_') and not written_here:
			continue
		if line.begins_with("("):
			line = line.substr(0, line.rfind(")") + 1) + " bricks " + tail
		out.append(line)
	return "\n".join(out)


func _import_text(text: String, file_name: String) -> Array:
	var path := "user://%s" % file_name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	assert_eq(root.import_map(path), OK, "the file imports")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return root.get_all_draft_brushes()


## A HammerForge file at its own units with the numbers the default alignment
## exports as is the default alignment, so a face nobody aligned is not changed
## by being read back.
func test_the_default_numbers_in_a_hammerforge_file_import_at_the_defaults():
	var brushes := _import_text(_one_box_map(true, "0 0 0 0.5 0.5"), "hf_identity.map")
	assert_eq(brushes.size(), 1)
	for face in brushes[0].faces:
		_assert_same_alignment(face, FaceData.new(), "face %s" % face.normal)


## Another editor writes the same texels, so its numbers read the same way: a
## 64 pixel texture, from the palette or taken as that size when the palette
## does not have it (#894).
func test_another_editor_s_alignment_is_read_in_texels():
	var want := FaceData.new()
	want.uv_offset = Vector2(0.25, 0.125)
	want.uv_rotation = deg_to_rad(45.0)
	want.uv_scale = Vector2.ONE
	for in_palette in [false, true]:
		root.clear_brushes()
		root.material_manager.clear()
		if in_palette:
			root.add_material_to_palette(_textured("bricks", 64, 64))
		var text := _one_box_map(false, "16 8 45 0.5 0.5")
		var brushes := _import_text(text, "foreign_aligned.map")
		assert_eq(brushes.size(), 1)
		for face in brushes[0].faces:
			_assert_same_alignment(face, want, "palette %s, face %s" % [in_palette, face.normal])


## And against the size of the texture the palette holds under that name.
func test_another_editor_s_alignment_is_read_against_the_palette_texture():
	root.add_material_to_palette(_textured("bricks", 128, 32))
	var want := FaceData.new()
	want.uv_offset = Vector2(0.125, 0.25)
	want.uv_scale = Vector2(0.5, 2.0)
	var brushes := _import_text(_one_box_map(false, "16 8 0 0.5 0.5"), "foreign_tiles.map")
	assert_eq(brushes.size(), 1)
	for face in brushes[0].faces:
		_assert_same_alignment(face, want, "face %s" % face.normal)


## The export writes a UV scale of zero as scale 1, because every compiler
## divides by it (#344). That substitution is one way: it reads back as 1.
func test_a_substituted_scale_comes_back_as_one():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_scale = Vector2(0.0, 2.0)
	var path := "user://hf_test_map_alignment_zero.map"
	root.export_map(path)

	root.import_map(path)

	for face in root.get_all_draft_brushes()[0].faces:
		assert_almost_eq(face.uv_scale, Vector2(1.0, 2.0), Vector2.ONE * 0.001)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_alignment_numbers_are_read_off_both_kinds_of_face_line():
	var face_re := RegEx.new()
	face_re.compile("\\(([^\\)]+)\\)")
	var points := "( 16 -16 -16 ) ( 16 16 -16 ) ( 16 16 16 )"
	var quake := MapIOType._parse_face_line("%s bricks 1.5 -2 30 0.5 4" % points, face_re)
	assert_eq(quake.get("texture"), "bricks")
	assert_eq(quake.get("alignment"), [1.5, -2.0, 30.0, 0.5, 4.0], "Classic Quake")
	var valve := MapIOType._parse_face_line(
		"%s bricks [ 0 1 0 1.5 ] [ 0 0 -1 -2 ] 30 0.5 4" % points, face_re
	)
	assert_eq(valve.get("texture"), "bricks")
	assert_eq(valve.get("alignment"), [1.5, -2.0, 30.0, 0.5, 4.0], "Valve 220")
	# Quake 2 and 3 add content flags, surface flags and a value after the scale.
	var quake2 := MapIOType._parse_face_line(
		"%s e1u1/floor 1.5 -2 30 0.5 4 0 0 0" % points, face_re
	)
	assert_eq(quake2.get("alignment"), [1.5, -2.0, 30.0, 0.5, 4.0], "trailing flags are ignored")
	var bare := MapIOType._parse_face_line("%s bricks" % points, face_re)
	assert_eq(bare.get("texture"), "bricks", "a line with no numbers still has its texture")
	assert_false(bare.has("alignment"), "and no alignment")
	var broken := MapIOType._parse_face_line("%s bricks 1 two 3 4 5" % points, face_re)
	assert_false(broken.has("alignment"), "a number that is not one is no alignment")


# -- Box UV agrees with the Valve 220 axes (#887, #895) ----------------------


## The planar axis a pair of Valve 220 texture axes stands for.
static func _axis_of(axes: Array) -> int:
	if axes[0] == Vector3.BACK and axes[1] == Vector3.UP:
		return FaceData.UVProjection.PLANAR_X
	if axes[0] == Vector3.RIGHT and axes[1] == Vector3.BACK:
		return FaceData.UVProjection.PLANAR_Y
	if axes[0] == Vector3.RIGHT and axes[1] == Vector3.UP:
		return FaceData.UVProjection.PLANAR_Z
	return -1


## Writes face lines as Valve 220 does, and keeps each one beside its face.
class RecordingValve220:
	extends "res://addons/hammerforge/map_adapters/hf_map_valve220.gd"

	var written: Array = []

	func format_face_line(
		a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
	) -> String:
		var line := super(a, b, c, texture, face_data)
		written.append([face_data, line])
		return line


## The two texture axes of a Valve 220 face line.
static func _valve_axes(line: String) -> Array:
	var out: Array = []
	var bracket := RegEx.new()
	bracket.compile("\\[([^\\]]+)\\]")
	for found in bracket.search_all(line):
		var parts := found.get_string(1).split(" ", false)
		out.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return out


## A Box UV brush at `centre`, turned by `turn` (Euler radians) and stretched by
## `stretch`, its faces told where it is the way the transform notification
## tells them.
func _placed(shape: int, centre: Vector3, turn: Vector3, stretch: Vector3) -> DraftBrush:
	var brush := (
		root.create_brush_from_info({"shape": shape, "size": Vector3(32, 32, 32), "center": centre})
		as DraftBrush
	)
	brush.rotation = turn
	brush.scale = stretch
	brush.sync_face_world_transform()
	for face in brush.faces:
		face.uv_projection = FaceData.UVProjection.BOX_UV
	return brush


## Every face line carries the axes of the projection the viewport draws on that
## face. At exactly 45 degrees either axis is a fair answer, so the export has
## to ask the face rather than work it out again: away from the origin, the
## plane normal it builds from the written points can sit a rounding error past
## 45 degrees the other way, and 2 of the 6 faces of a box turned about Y were
## written with the other axis.
func test_every_valve_220_face_carries_the_axes_the_viewport_draws():
	var box := LevelRootType.BrushShape.BOX
	var wedge := LevelRootType.BrushShape.WEDGE
	var eighth := PI / 4.0
	var cases := [
		[box, Vector3(eighth, 0, 0), Vector3.ONE],
		[box, Vector3(0, eighth, 0), Vector3.ONE],
		[box, Vector3(0, 0, eighth), Vector3.ONE],
		[box, Vector3(0, deg_to_rad(30.0), 0), Vector3(2, 1, 1)],
		[box, Vector3(0.3, 0.7, 0), Vector3(1, 2, 1)],
		[wedge, Vector3(0, eighth, 0), Vector3(1, 1, 3)],
		[wedge, Vector3(0, 0.3, 0), Vector3.ONE],
		# The stretched wedges of #887.
		[wedge, Vector3.ZERO, Vector3(1, 4, 1)],
		[wedge, Vector3.ZERO, Vector3(4, 1, 1)],
		[wedge, Vector3.ZERO, Vector3(1, 1, 4)],
	]
	for centre in [Vector3.ZERO, Vector3(40, 8, -24), Vector3(128, 0, 64)]:
		for case in cases:
			var brush := _placed(case[0], centre, case[1], case[2])
			var adapter := RecordingValve220.new()
			MapIOType._brush_to_map_lines(brush, adapter)
			assert_gt(adapter.written.size(), 0, "%s writes face lines" % [case])
			for entry in adapter.written:
				var face: FaceData = entry[0]
				assert_eq(
					_axis_of(_valve_axes(entry[1])),
					face._box_projection_axis_in(face.world_transform),
					(
						"shape %d at %s turned %s stretched %s: the face facing %s"
						% [case[0], centre, case[1], case[2], face.normal]
					)
				)
			root.clear_brushes()
