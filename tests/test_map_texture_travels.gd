extends GutTest

## A face's `.map` texture name kept wherever a face is made from another one (#859).
##
## `map_texture` is what the exporter writes when a face has no palette slot, and in
## this lineage the name is the surface's behaviour: `AAATRIGGER` is a trigger
## volume, `sky1` is sky. Every place that built a face from another face copied
## its fields one by one and left the name behind, so an imported trigger went back
## out as a plain solid after a resize, a Godot Duplicate, a clip, a bevel, or just
## a save and reopen, since every primitive rebuilds when its scene opens.
##
## The scene tests write the file and load it with the cache ignored. A
## `PackedScene` held in memory hands back the same FaceData objects, so it would
## keep a name that never reached the file.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const MapIO = preload("res://addons/hammerforge/map_io.gd")
const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

const SCENE_PATH := "user://test_map_texture_travels.tscn"
const MAP_PATH := "user://test_map_texture_travels.map"
const MAP_OUT := "user://test_map_texture_travels_out.map"
const TRIGGER := "AAATRIGGER"

## A name per direction, so a face that took the wrong face's data shows up as
## well as one that took none.
const BY_DIRECTION := {
	Vector3i(1, 0, 0): "wall_east",
	Vector3i(-1, 0, 0): "wall_west",
	Vector3i(0, 1, 0): "sky1",
	Vector3i(0, -1, 0): "floor1",
	Vector3i(0, 0, 1): "*water1",
	Vector3i(0, 0, -1): TRIGGER,
}

## What `copy_appearance_from()` carries and `appearance_matches()` compares.
const APPEARANCE := [
	"material_idx",
	"map_texture",
	"uv_projection",
	"uv_scale",
	"uv_offset",
	"uv_rotation",
	"legacy_wall_axes",
]
## The rest of what a face stores: its corners and what is derived from them, the
## data laid against the corners, and paint, which each caller shares or copies.
const NOT_APPEARANCE := [
	"local_verts", "normal", "bounds", "custom_uvs", "displacement", "paint_layers"
]

## A world brush named per face, and a trigger. Both are axis aligned, so both
## import as boxes, and a box rebuilds its faces when the scene opens.
const MAP_SOURCE := """{
"classname" "worldspawn"
{
( 0 0 0 ) ( 64 0 0 ) ( 64 64 0 ) floor1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 0 0 16 ) ( 64 64 16 ) ( 64 0 16 ) ceil1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 0 0 0 ) ( 0 64 0 ) ( 0 64 16 ) wall_a [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 64 0 0 ) ( 64 0 16 ) ( 64 64 16 ) wall_b [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 0 0 0 ) ( 0 0 16 ) ( 64 0 16 ) sky1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 0 64 0 ) ( 64 64 0 ) ( 64 64 16 ) *water1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
{
"classname" "trigger_once"
{
( 16 0 0 ) ( 24 0 0 ) ( 24 8 0 ) AAATRIGGER [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 16 0 8 ) ( 24 8 8 ) ( 24 0 8 ) AAATRIGGER [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 16 0 0 ) ( 16 8 0 ) ( 16 8 8 ) AAATRIGGER [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 24 0 0 ) ( 24 0 8 ) ( 24 8 8 ) AAATRIGGER [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 16 0 0 ) ( 16 0 8 ) ( 24 0 8 ) AAATRIGGER [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 16 8 0 ) ( 24 8 0 ) ( 24 8 8 ) AAATRIGGER [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
"""

var holder: Node3D


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)


func after_each():
	holder = null
	for path in [SCENE_PATH, MAP_PATH, MAP_OUT]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# Fixtures
# ===========================================================================


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _root_box(root: LevelRoot, at := Vector3.ZERO) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": root.BrushShape.BOX,
					"size": Vector3(32, 32, 32),
					"transform": Transform3D(Basis.IDENTITY, at),
					"operation": CSGShape3D.OPERATION_UNION,
				}
			)
		)
		as DraftBrush
	)


func _brush(shape: int, sides := 4) -> DraftBrush:
	var b := DraftBrush.new()
	b.brush_id = "b1"
	holder.add_child(b)
	b.shape = shape
	b.sides = sides
	b.size = Vector3(32, 32, 32)
	return b


static func _direction(face: FaceData) -> Vector3i:
	return Vector3i(face.normal.round())


static func _name_by_direction(brush: DraftBrush) -> void:
	for face in brush.get_faces():
		face.map_texture = BY_DIRECTION[_direction(face)]


static func _name_all(brush: DraftBrush, texture: String) -> void:
	for face in brush.get_faces():
		face.map_texture = texture


## Every face of `brush` that is not named for the way it faces.
static func _misnamed(brush: DraftBrush) -> Array:
	var out: Array = []
	for face in brush.get_faces():
		var want: String = BY_DIRECTION.get(_direction(face), "")
		if face.map_texture != want:
			out.append("%s named '%s'" % [_direction(face), face.map_texture])
	return out


static func _names(faces: Array) -> Array:
	var out: Array = []
	for face in faces:
		out.append(face.map_texture)
	return out


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


## Save the level the way Ctrl+S does, and open the file again.
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


func _brushes(root: LevelRoot) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			out.append(child)
	return out


# ===========================================================================
# FaceData: one definition of what a face looks like
# ===========================================================================


func test_every_field_a_face_stores_is_either_appearance_or_not():
	# A new field fails here until it is put on one side or the other. Copying
	# fields one by one, and forgetting one, is how the name went missing.
	for prop in FaceData.new().get_property_list():
		var usage: int = prop["usage"]
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE):
			continue
		var field: String = prop["name"]
		assert_true(
			APPEARANCE.has(field) != NOT_APPEARANCE.has(field),
			"'%s' is listed as appearance or not, and only one of them" % field
		)


## A value for `field` that is not what a new face starts with.
static func _changed(field: String) -> Variant:
	var value: Variant = FaceData.new().get(field)
	match typeof(value):
		TYPE_INT:
			return value + 3
		TYPE_FLOAT:
			return value + 0.5
		TYPE_STRING:
			return value + "named"
		TYPE_VECTOR2:
			return value + Vector2(2.0, 3.0)
		TYPE_BOOL:
			return not value
	return null


func test_copy_appearance_carries_every_appearance_field():
	var source := FaceData.new()
	for field in APPEARANCE:
		var value: Variant = _changed(field)
		assert_not_null(value, "the test knows how to change '%s'" % field)
		source.set(field, value)
	var face := FaceData.new()
	face.copy_appearance_from(source)
	for field in APPEARANCE:
		assert_eq(face.get(field), source.get(field), "'%s' is copied" % field)
	assert_true(face.appearance_matches(source), "and the two faces look alike")


func test_copy_texture_carries_the_slot_and_the_name_together():
	var source := FaceData.new()
	source.material_idx = 4
	source.map_texture = TRIGGER
	source.uv_scale = Vector2(2.0, 2.0)
	var face := FaceData.new()
	face.copy_texture_from(source)
	assert_eq(face.material_idx, 4, "the palette slot")
	assert_eq(face.map_texture, TRIGGER, "and the name the exporter falls back to")
	assert_eq(face.uv_scale, Vector2.ONE, "and nothing about how it is laid on")


func test_copy_appearance_leaves_the_corners_and_what_is_laid_on_them():
	var source := FaceData.new()
	source.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	source.custom_uvs = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	source.displacement = HFDisplacementDataScript.new()
	source.paint_layers.append(FaceData.PaintLayer.new())
	source.ensure_geometry()
	var face := FaceData.new()
	face.copy_appearance_from(source)
	assert_true(face.local_verts.is_empty(), "corners stay where the face put them")
	assert_true(face.custom_uvs.is_empty(), "custom UVs belong to the corners")
	assert_null(face.displacement, "and so does a sculpt")
	assert_true(face.paint_layers.is_empty(), "paint is the caller's to share or copy")


func test_faces_that_differ_only_in_one_field_do_not_look_alike():
	for field in APPEARANCE:
		var face := FaceData.new()
		var other := FaceData.new()
		other.set(field, _changed(field))
		assert_false(face.appearance_matches(other), "'%s' is part of the look" % field)
	assert_true(FaceData.new().appearance_matches(FaceData.new()), "two new faces look alike")


# ===========================================================================
# A primitive rebuilding its faces
# ===========================================================================


func test_a_resize_keeps_every_face_s_name():
	var b := _brush(DraftBrush.BrushShape.BOX)
	_name_by_direction(b)
	b.size = Vector3(64, 32, 48)
	assert_eq(b.get_faces().size(), 6, "the box rebuilt")
	assert_eq(_misnamed(b), [], "every face is still named for the way it faces")


func test_a_sides_change_keeps_a_trigger_a_trigger():
	var b := _brush(DraftBrush.BrushShape.CYLINDER, 8)
	_name_all(b, TRIGGER)
	b.sides = 12
	assert_eq(b.get_faces().size(), 14, "12 sides and two caps")
	for face in b.get_faces():
		assert_eq(face.map_texture, TRIGGER, "every face is still a trigger")


func test_a_sides_change_keeps_each_cap_s_own_name():
	# Every face has the same material and UVs, and only the names tell the caps
	# from the walls. A brush whose faces all look alike hands every new face the
	# first face's look, so the name has to count as part of the look.
	var b := _brush(DraftBrush.BrushShape.CYLINDER, 8)
	for face in b.get_faces():
		var up: float = face.normal.y
		face.map_texture = "sky1" if up > 0.9 else ("floor1" if up < -0.9 else "wall_a")
	b.sides = 12
	for face in b.get_faces():
		var up: float = face.normal.y
		var want := "sky1" if up > 0.9 else ("floor1" if up < -0.9 else "wall_a")
		assert_eq(face.map_texture, want, "a face facing %s" % face.normal)


func test_a_native_duplicate_keeps_every_name():
	var b := _brush(DraftBrush.BrushShape.BOX)
	_name_by_direction(b)
	var before: Array = b.get_faces().duplicate()
	b.make_face_resources_unique()
	assert_ne(b.get_faces()[0], before[0], "the faces were copied")
	assert_eq(_misnamed(b), [], "and every copy has its name")


func test_a_brush_duplicated_in_the_scene_tree_keeps_every_name():
	var root := _fresh_root()
	var source := _root_box(root)
	_name_by_direction(source)
	# Godot's own Duplicate, then the repair HammerForge runs when it sees two
	# brushes with one id.
	var twin := source.duplicate() as DraftBrush
	root.draft_brushes_node.add_child(twin)
	root.reconcile_external_brush_structure()
	assert_ne(twin.brush_id, source.brush_id, "the copy gets its own id")
	assert_ne(twin.get_faces()[0], source.get_faces()[0], "and faces of its own")
	assert_eq(_misnamed(twin), [], "with the names")
	assert_eq(_misnamed(source), [], "and the source keeps them")


# ===========================================================================
# The scene
# ===========================================================================


func test_the_names_come_back_from_the_saved_scene():
	var root := _fresh_root()
	var brush := _root_box(root)
	_name_by_direction(brush)

	var copy := _save_and_reopen(root)
	var reopened := copy.find_brush_by_id(brush.brush_id) as DraftBrush
	assert_not_null(reopened, "the brush comes back")
	if reopened == null:
		return
	assert_ne(reopened.get_faces()[0], brush.get_faces()[0], "the faces were read from the file")
	assert_eq(_misnamed(reopened), [], "every face is still named for the way it faces")


func test_an_imported_map_saved_and_reopened_exports_its_names():
	var f := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	f.store_string(MAP_SOURCE)
	f.close()
	var root := _fresh_root()
	assert_eq(root.file_system.import_map(MAP_PATH), OK, "the map imports")
	# What the dock's Clear Palette does, to bring in materials of your own. Every
	# face is unset, so its own name is the only record of its texture.
	assert_gt(root.clear_palette(), 0, "the import filled the palette, and it is cleared")

	var copy := _save_and_reopen(root)
	assert_eq(copy.get_material_names(), [], "the palette reopens empty")
	assert_eq(copy.file_system.export_map(MAP_OUT, "valve220"), OK, "the level exports")
	var text := FileAccess.get_file_as_string(MAP_OUT)
	for expected in ["floor1", "ceil1", "wall_a", "wall_b", "sky1", "*water1", TRIGGER]:
		assert_string_contains(text, expected, "a name the source had")
	assert_false(text.contains(MapIO.DEFAULT_TEXTURE), "and no face fell back to the default")


# ===========================================================================
# Cutting and building faces from faces
# ===========================================================================


func test_both_halves_of_a_clipped_trigger_are_triggers():
	var root := _fresh_root()
	var brush := _root_box(root)
	_name_all(brush, TRIGGER)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 1, 4.0).ok, "the clip cuts")
	var pieces := _brushes(root)
	assert_eq(pieces.size(), 2, "into two")
	for piece in pieces:
		assert_eq(piece.get_faces().size(), 6, "each a box, with the cut face")
		for face in piece.get_faces():
			assert_eq(face.map_texture, TRIGGER, "every face of each half, the cut included")


func test_a_carved_trigger_stays_a_trigger():
	var root := _fresh_root()
	var target := _root_box(root)
	_name_all(target, TRIGGER)
	var carver := _root_box(root, Vector3(16, 16, 0))
	assert_true(root.carve_system.carve_with_brush(carver.brush_id).ok, "the carve cuts")
	var pieces: Array = []
	for b in _brushes(root):
		if b.brush_id != carver.brush_id:
			pieces.append(b)
	assert_gt(pieces.size(), 1, "the target was cut into pieces")
	for piece in pieces:
		assert_eq(
			_names(piece.get_faces()).count(TRIGGER),
			piece.get_faces().size(),
			"every face of every piece is a trigger"
		)


func test_an_inset_keeps_the_name_on_the_faces_it_adds():
	var root := _fresh_root()
	var brush := _root_box(root)
	_name_all(brush, TRIGGER)
	var count := brush.get_faces().size()
	assert_true(root.bevel_system.inset_face(brush.brush_id, 0, 4.0, 2.0), "the face is inset")
	assert_gt(brush.get_faces().size(), count, "the inset added faces")
	assert_eq(_names(brush.get_faces()).count(TRIGGER), brush.get_faces().size(), "all triggers")


func test_a_bevel_keeps_the_name_on_the_faces_it_adds():
	var root := _fresh_root()
	var brush := _root_box(root)
	_name_all(brush, TRIGGER)
	var count := brush.get_faces().size()
	var top: FaceData = null
	for face in brush.get_faces():
		if _direction(face) == Vector3i.UP:
			top = face
	# The edge is named by indices into the brush's distinct corners.
	var corners: PackedVector3Array = root.bevel_system._get_unique_verts(brush.get_faces())
	var edge := [corners.find(top.local_verts[0]), corners.find(top.local_verts[1])]
	assert_true(root.bevel_system.bevel_edge(brush.brush_id, edge, 3, 4.0), "the edge bevels")
	assert_gt(brush.get_faces().size(), count, "the bevel added faces")
	assert_eq(_names(brush.get_faces()).count(TRIGGER), brush.get_faces().size(), "all triggers")


func test_a_hull_rebuild_names_each_face_after_the_face_it_replaces():
	# What Clip to Convex rebuilds a brush from. Reaching it through the command
	# needs a brush the vertex tools will not make, so ask for the faces directly.
	var root := _fresh_root()
	var brush := _root_box(root)
	_name_by_direction(brush)
	var vertex_system = root.vertex_system
	var hull: PackedVector3Array = vertex_system._convex_hull_3d(
		vertex_system.get_brush_vertices(brush)
	)
	var rebuilt: Array = vertex_system._faces_from_convex_hull(hull, brush.get_faces())
	assert_eq(rebuilt.size(), 6, "the hull of a box is the box")
	for face in rebuilt:
		assert_eq(
			face.map_texture, BY_DIRECTION[_direction(face)], "a face facing %s" % face.normal
		)


# ===========================================================================
# A generated structure's Update
# ===========================================================================


func _arch(overrides: Dictionary = {}) -> Dictionary:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("arch")
	for key in overrides:
		settings[key] = overrides[key]
	return settings


func _create_arch(root: LevelRoot, overrides: Dictionary = {}) -> String:
	assert_true(root.create_generator("arch", _arch(overrides), Transform3D.IDENTITY).ok)
	for generator_id in root.generator_system.generators:
		return str(generator_id)
	return ""


func _piece(root: LevelRoot, generator_id: String, index: int) -> DraftBrush:
	var record = root.generator_system.generators[generator_id]
	return root.brush_system.find_brush_by_id(str(record.brush_ids[index])) as DraftBrush


func test_an_update_puts_each_face_s_name_back():
	var root := _fresh_root()
	var generator_id := _create_arch(root)
	var piece := _piece(root, generator_id, 0)
	piece.faces[0].map_texture = TRIGGER
	piece.faces[2].map_texture = "sky1"

	assert_true(root.regenerate_generator(generator_id, _arch({"depth": 96.0})).ok, "it rebuilds")

	var faces: Array = _piece(root, generator_id, 0).faces
	assert_ne(faces[0], piece.faces[0], "the piece was rebuilt")
	assert_eq(faces[0].map_texture, TRIGGER, "each face gets its own name back")
	assert_eq(faces[2].map_texture, "sky1")
	assert_eq(faces[1].map_texture, "", "and a face that had none has none")


func test_an_update_that_would_drop_a_named_piece_says_so():
	var root := _fresh_root()
	var generator_id := _create_arch(root, {"segments": 9})
	_piece(root, generator_id, 8).faces[0].map_texture = TRIGGER

	var at_risk := root.generator_appearance_at_risk(generator_id, _arch({"segments": 5}))

	assert_eq(at_risk.size(), 1, "a name is worth warning about, like paint")
	var record = root.generator_system.generators[generator_id]
	assert_eq(str(at_risk[0]), str(record.brush_ids[8]), "and the piece past the new end is named")
