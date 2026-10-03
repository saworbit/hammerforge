extends GutTest

## #907. Godot reads V = 0 as the top row of an image, and a wall's V ran up the
## wall, so every wall and every Cylindrical side was drawn upside down. The axes
## are qbsp's now. A face somebody laid on before then keeps the axes it was laid
## on with, and so keeps its look, its paint and the records that watch it.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const PaintLayer = preload("res://addons/hammerforge/paint/hf_face_paint_layer.gd")

const SCENE_PATH := "user://test_uv_upright.tscn"


func after_each():
	if FileAccess.file_exists(SCENE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE_PATH))


## A square on the plane `projection` reads, low corners first, so corners 2 and
## 3 are a metre higher than 0 and 1.
static func _wall(projection: int) -> FaceData:
	var face := FaceData.new()
	face.uv_projection = projection
	match projection:
		FaceData.UVProjection.PLANAR_X:
			face.local_verts = PackedVector3Array(
				[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]
			)
		_:
			face.local_verts = PackedVector3Array(
				[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
			)
	return face


func test_a_point_higher_up_a_wall_gets_a_smaller_v():
	for projection in [
		FaceData.UVProjection.PLANAR_X,
		FaceData.UVProjection.PLANAR_Z,
		FaceData.UVProjection.CYLINDRICAL,
	]:
		var face := _wall(projection)
		var uvs := face._project_uvs_for_vertices(face.local_verts)
		assert_lt(
			uvs[3].y, uvs[0].y, "projection %d: the top of the image is at the top" % projection
		)


func test_box_uv_on_every_wall_of_a_box_runs_v_down():
	var root := _fresh_root()
	var box := _box(root, Vector3(3, 1, -2))
	for face in box.faces:
		if absf(face.normal.y) > 0.5:
			continue
		var uvs := face._project_uvs_for_vertices(face.local_verts)
		var top := 0
		var bottom := 0
		for i in face.local_verts.size():
			if face.local_verts[i].y > face.local_verts[top].y:
				top = i
			if face.local_verts[i].y < face.local_verts[bottom].y:
				bottom = i
		assert_lt(uvs[top].y, uvs[bottom].y, "the wall facing %s" % face.normal)


## qbsp's axes: an X wall's U runs along -Z, a Z wall's along +X.
func test_the_wall_axes_are_qbsp_s():
	assert_eq(
		FaceData.projection_axes(FaceData.UVProjection.PLANAR_X), [Vector3.FORWARD, Vector3.DOWN]
	)
	assert_eq(
		FaceData.projection_axes(FaceData.UVProjection.PLANAR_Z), [Vector3.RIGHT, Vector3.DOWN]
	)


func test_a_floor_reads_as_it_always_did():
	assert_eq(
		FaceData.projection_axes(FaceData.UVProjection.PLANAR_Y), [Vector3.RIGHT, Vector3.BACK]
	)
	assert_eq(
		FaceData.projection_axes(FaceData.UVProjection.PLANAR_Y, true),
		[Vector3.RIGHT, Vector3.BACK]
	)


func test_a_face_laid_on_before_keeps_its_axes():
	for projection in [
		FaceData.UVProjection.PLANAR_X,
		FaceData.UVProjection.PLANAR_Z,
		FaceData.UVProjection.CYLINDRICAL,
	]:
		var face := _wall(projection)
		face.legacy_wall_axes = true
		var uvs := face._project_uvs_for_vertices(face.local_verts)
		assert_gt(uvs[3].y, uvs[0].y, "projection %d keeps V running up" % projection)
	var x_wall := _wall(FaceData.UVProjection.PLANAR_X)
	x_wall.legacy_wall_axes = true
	var uvs := x_wall._project_uvs_for_vertices(x_wall.local_verts)
	assert_gt(uvs[1].x, uvs[0].x, "and an X wall keeps U running along +Z")


# -- An old .hflevel ---------------------------------------------------------


static func _record(version: int, changes: Dictionary) -> Dictionary:
	var face := _wall(FaceData.UVProjection.PLANAR_Z)
	var data := face.to_dict()
	data["uv_format_version"] = version
	data.erase("legacy_wall_axes")
	for key in changes:
		data[key] = changes[key]
	return data


func test_an_old_record_keeps_its_axes_only_where_somebody_laid_on_it():
	var cases := {
		"default": [{}, false],
		"offset": [{"uv_offset": [0.25, 0.0]}, true],
		"scale": [{"uv_scale": [2.0, 2.0]}, true],
		"rotation": [{"uv_rotation": 0.5}, true],
		"its own UVs": [{"custom_uvs": [[0, 0], [1, 0], [1, 1], [0, 1]]}, true],
		"paint": [{"paint_layers": [{"texture_path": "", "blend_mode": 0, "opacity": 1.0}]}, true],
	}
	for label in cases:
		var face := FaceData.from_dict(_record(2, cases[label][0]))
		assert_eq(face.legacy_wall_axes, cases[label][1], "a v2 face with %s" % label)


func test_a_new_record_says_which_axes_it_was_laid_on():
	var kept := FaceData.from_dict(_record(3, {"uv_offset": [0.25, 0.0], "legacy_wall_axes": true}))
	assert_true(kept.legacy_wall_axes)
	var fresh := FaceData.from_dict(_record(3, {"uv_offset": [0.25, 0.0]}))
	assert_false(fresh.legacy_wall_axes, "an offset set since #907 is on the new axes")
	var face := _wall(FaceData.UVProjection.PLANAR_Z)
	face.legacy_wall_axes = true
	assert_true(FaceData.from_dict(face.to_dict()).legacy_wall_axes, "and the mark round trips")


# -- An old scene ------------------------------------------------------------


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, at := Vector3.ZERO) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"shape": 0, "size": Vector3(2, 1, 1.5), "transform": Transform3D(Basis.IDENTITY, at)}
		)
		as DraftBrush
	)


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


func _save_and_reopen(root: LevelRoot) -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


## A scene saved before #907 holds no `face_axes_version` and no mark on any face.
## Opening it marks the faces somebody laid on, and only those, and they draw
## exactly as they did.
func test_an_old_scene_keeps_the_look_of_the_faces_somebody_laid_on():
	var root := _fresh_root()
	var box := _box(root, Vector3(3, 1, -2))
	# The transform notification is deferred, and the copy's faces will know.
	box.sync_face_world_transform()
	var aligned := 0
	var painted := 2
	var hand := 4
	box.faces[aligned].uv_offset = Vector2(0.25, 0.5)
	box.faces[painted].paint_layers.append(PaintLayer.new())
	box.faces[painted].paint_layers[0].ensure_weight_image(Vector2i(8, 8))
	box.faces[hand].custom_uvs = PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	)
	# What the same faces drew on the old axes.
	var drawn_before: Array = []
	for face in box.faces:
		face.legacy_wall_axes = true
		drawn_before.append(face._project_uvs_for_vertices(face.local_verts))
		face.legacy_wall_axes = false
	root.face_axes_version = 0

	var reopened := _save_and_reopen(root)

	assert_eq(reopened.face_axes_version, LevelRootType.FACE_AXES_VERSION, "the step ran")
	var brush: DraftBrush = reopened.draft_brushes_node.get_child(0)
	for i in brush.faces.size():
		var face: FaceData = brush.faces[i]
		var laid := i in [aligned, painted, hand]
		assert_eq(face.legacy_wall_axes, laid, "face %d facing %s" % [i, face.normal])
		if laid:
			assert_eq(
				face._project_uvs_for_vertices(face.local_verts),
				drawn_before[i],
				"face %d draws as it did" % i
			)


func test_a_new_scene_says_its_faces_are_on_the_new_axes():
	var root := _fresh_root()
	assert_eq(root.face_axes_version, LevelRootType.FACE_AXES_VERSION)
	var box := _box(root)
	box.faces[0].uv_offset = Vector2(0.25, 0.5)

	var reopened := _save_and_reopen(root)

	var brush: DraftBrush = reopened.draft_brushes_node.get_child(0)
	assert_false(brush.faces[0].legacy_wall_axes, "an offset set today is not an old one")


func test_re_projecting_a_face_puts_it_on_the_new_axes():
	var root := _fresh_root()
	var box := _box(root)
	assert_ne(box.brush_id, "", "the brush has an id to find it by")
	box.faces[0].legacy_wall_axes = true
	root.reproject_face_uvs(box.brush_id, 0, FaceData.UVProjection.PLANAR_Z)
	assert_false(box.faces[0].legacy_wall_axes)


func test_a_copied_look_carries_the_axes():
	var source := _wall(FaceData.UVProjection.PLANAR_Z)
	source.legacy_wall_axes = true
	var copy := FaceData.new()
	copy.copy_appearance_from(source)
	assert_true(copy.legacy_wall_axes)
	assert_true(copy.appearance_matches(source))
	copy.legacy_wall_axes = false
	assert_false(copy.appearance_matches(source), "the same numbers on other axes look different")
