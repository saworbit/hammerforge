extends GutTest

## The bake, the heightmap, the subtract preview and the brush preview each need
## a brush's bounds or a face's material, and each had its own copy of how. These
## pin that they now ask one place (#901, #902).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBakeSystemType = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFSubtractPreviewType = preload("res://addons/hammerforge/systems/hf_subtract_preview.gd")
const HFBrushToHeightmapType = preload("res://addons/hammerforge/paint/hf_brush_to_heightmap.gd")
const BakerType = preload("res://addons/hammerforge/baker.gd")
const MaterialManagerType = preload("res://addons/hammerforge/material_manager.gd")
const PaintLayer = preload("res://addons/hammerforge/paint/hf_face_paint_layer.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _long_box() -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"shape": 0, "size": Vector3(4, 1, 1), "center": Vector3(10, 0, 0)}
		)
		as DraftBrush
	)


func _assert_same_box(got: AABB, want: AABB, what: String) -> void:
	assert_almost_eq(got.position, want.position, Vector3.ONE * 0.001, "%s position" % what)
	assert_almost_eq(got.size, want.size, Vector3.ONE * 0.001, "%s size" % what)


# -- One box for a brush in the level (#901) -----------------------------------


## A brush four long on X turned a quarter turn is four long on Z. Read from its
## faces, with no mesh to read, the heightmap and the subtract preview used to
## box its size round its position and kept it four long on X.
func test_a_turned_brush_has_the_same_box_for_every_caller():
	var brush := _long_box()
	brush.rotation = Vector3(0, PI / 2, 0)
	brush.mesh_instance.mesh = null
	var bake := HFBakeSystemType.brush_world_aabb(brush, brush.global_transform)
	assert_almost_eq(bake.size, Vector3(1, 1, 4), Vector3.ONE * 0.001, "the bake turns the box")
	_assert_same_box(
		HFBrushToHeightmapType.new()._get_brush_aabb(brush), bake, "the heightmap's box"
	)
	_assert_same_box(HFSubtractPreviewType.world_aabb(brush), bake, "the subtract preview's box")


func test_a_brush_with_a_mesh_has_the_same_box_for_every_caller():
	var brush := _long_box()
	brush.rotation = Vector3(0, 0.4, 0)
	assert_not_null(brush.mesh_instance.mesh, "the brush has its preview mesh")
	var bake := HFBakeSystemType.brush_world_aabb(brush, brush.global_transform)
	_assert_same_box(
		HFBrushToHeightmapType.new()._get_brush_aabb(brush), bake, "the heightmap's box"
	)
	_assert_same_box(HFSubtractPreviewType.world_aabb(brush), bake, "the subtract preview's box")


## The subtract preview asks about brushes that are not in the tree yet, so the
## transform comes in from the caller.
func test_a_brush_out_of_the_tree_is_boxed_where_its_transform_puts_it():
	var brush := DraftBrush.new()
	brush.size = Vector3(4, 1, 1)
	brush.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2, 0, 0))
	var box := HFSubtractPreviewType.world_aabb(brush)
	assert_almost_eq(box.size, Vector3(1, 1, 4), Vector3.ONE * 0.001)
	assert_almost_eq(box.get_center(), Vector3(2, 0, 0), Vector3.ONE * 0.001)
	brush.free()


# -- One material for a face (#902) --------------------------------------------


func _named(label: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	return mat


func test_the_preview_shows_the_material_the_bake_uses():
	var manager := MaterialManagerType.new()
	var slot := _named("slot")
	manager.add_material(slot)
	var brush := _long_box()
	var face: FaceData = brush.faces[0]
	var baker := BakerType.new()
	var override := _named("override")
	var editor := _named("editor")

	face.material_idx = 0
	assert_eq(brush._material_for_face(face, manager), slot, "a palette slot wins")
	assert_eq(baker._resolve_face_material(face, manager, override, editor), slot)

	face.material_idx = -1
	brush.material_override = override
	assert_eq(brush._material_for_face(face, manager), override, "then the brush's material")
	assert_eq(baker._resolve_face_material(face, manager, override, editor), override)

	brush.material_override = null
	brush.editor_material = editor
	assert_eq(brush._material_for_face(face, manager), editor, "then the editor material")
	assert_eq(baker._resolve_face_material(face, manager, null, editor), editor)

	brush.editor_material = null
	var fallback := brush._material_for_face(face, manager) as StandardMaterial3D
	assert_eq(
		fallback.transparency,
		BaseMaterial3D.TRANSPARENCY_ALPHA,
		"and the translucent preview default only in the preview"
	)
	assert_null(baker._resolve_face_material(face, manager, null, null), "the bake has none")
	manager.free()


func test_paint_lies_over_the_same_material_in_the_preview_and_the_bake():
	var manager := MaterialManagerType.new()
	manager.add_material(_named("slot"))
	var brush := _long_box()
	var face: FaceData = brush.faces[0]
	face.material_idx = 0
	var layer := PaintLayer.new()
	layer.texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	layer.ensure_weight_image(Vector2i(4, 4))
	layer.weight_image.fill(Color.WHITE)
	face.paint_layers.append(layer)
	var shown := brush._material_for_face(face, manager) as StandardMaterial3D
	var baked := BakerType.new()._resolve_face_material(face, manager, null, null)
	assert_not_null(shown.albedo_texture, "the preview shows the paint")
	assert_not_null((baked as StandardMaterial3D).albedo_texture, "and so does the bake")
	assert_eq(shown.resource_name, "slot", "over the palette material")
	assert_eq(baked.resource_name, "slot")
	var bare := brush._material_for_face(face, manager, false)
	assert_eq(bare.resource_name, "slot", "and without paint when the caller asks")
	assert_null((bare as StandardMaterial3D).albedo_texture)
	manager.free()
