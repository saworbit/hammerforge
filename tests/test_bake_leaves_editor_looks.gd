extends GutTest

## The editor draws a brush with nothing to draw with in a see-through tint, and
## a cut in red or orange. The bake reads a brush's preview mesh in two places: a
## brush entity that keeps its own node, and a custom shape that goes through
## CSG. Neither may carry those looks into the game (#1092, #1518).

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(center: Vector3, size: Vector3 = Vector3(2, 2, 2)) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"shape": LevelRoot.BrushShape.BOX, "size": size, "center": center}
		)
		as DraftBrush
	)


## A brush tied to `entity_class` under the name `entity_name`.
func _tied(entity_name: String, entity_class: String, center: Vector3) -> DraftBrush:
	var brush := _box(center)
	brush.set_brush_entity_class(entity_class)
	brush.set_meta("entity_name", entity_name)
	return brush


func _baked(path: String) -> Node:
	return root.baked_container.get_node_or_null("Nonstructural/%s" % path)


## The material each surface of `drawn` is drawn with.
func _drawn_with(drawn: MeshInstance3D) -> Array:
	var out: Array = []
	for i in drawn.mesh.get_surface_count():
		out.append(drawn.get_active_material(i))
	return out


func _tinted_surfaces(mesh: Mesh) -> int:
	var count := 0
	for i in mesh.get_surface_count():
		if DraftBrush.is_editor_look(mesh.surface_get_material(i)):
			count += 1
	return count


func _all_baked_materials() -> Array:
	var out: Array = []
	for node in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		out.append_array(_drawn_with(node as MeshInstance3D))
	return out


func _assert_no_editor_look(materials: Array, what: String) -> void:
	assert_gt(materials.size(), 0, "fixture: %s draws something" % what)
	for mat in materials:
		assert_false(DraftBrush.is_editor_look(mat), "%s: %s is the editor's look" % [what, mat])
		var see_through: bool = (
			mat is BaseMaterial3D
			and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		)
		assert_false(see_through, "%s: %s is see-through" % [what, mat])


# -- A brush entity that keeps its own node ------------------------------------


func test_an_unpainted_named_func_detail_bakes_with_no_material():
	var crate := _tied("crate", "func_detail", Vector3.ZERO)
	var tint: Material = crate.mesh_instance.material_override
	assert_true(DraftBrush.is_editor_look(tint), "fixture: the editor draws it in the tint")
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var baked := _baked("crate") as MeshInstance3D
	assert_not_null(baked, "the crate keeps a node of its own")
	assert_null(baked.material_override, "it bakes with no material, as an unpainted brush does")
	_assert_no_editor_look(_drawn_with(baked), "the crate")
	assert_eq(crate.mesh_instance.material_override, tint, "while the editor still draws the tint")


func test_a_named_func_detail_painted_on_some_faces_bakes_the_rest_with_none():
	var stone := StandardMaterial3D.new()
	stone.resource_name = "stone"
	var slot := root.material_manager.add_material(stone)
	var crate := _tied("crate", "func_detail", Vector3.ZERO)
	crate.faces[0].material_idx = slot
	crate.faces[1].material_idx = slot
	crate.rebuild_preview()
	assert_null(crate.mesh_instance.material_override, "fixture: it is drawn face by face")
	var preview := crate.mesh_instance.mesh
	var tinted := _tinted_surfaces(preview)
	assert_gt(tinted, 0, "fixture: the unpainted faces are drawn in the tint")
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var baked := _baked("crate") as MeshInstance3D
	assert_not_null(baked, "the crate keeps a node of its own")
	var drawn := _drawn_with(baked)
	assert_true(drawn.has(stone), "the painted faces keep their material")
	for mat in drawn:
		if mat != stone:
			assert_null(mat, "and an unpainted face bakes with none")
	assert_eq(crate.mesh_instance.mesh, preview, "the editor draws the mesh it drew")
	assert_eq(_tinted_surfaces(preview), tinted, "with its tint left on it")


func test_a_named_brush_entity_with_a_material_keeps_it():
	var painted := StandardMaterial3D.new()
	var crate := _tied("crate", "func_detail", Vector3.ZERO)
	crate.material_override = painted
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var baked := _baked("crate") as MeshInstance3D
	assert_eq(baked.material_override, painted, "a brush entity's own material is what it bakes in")


func test_an_unpainted_named_func_detail_takes_the_bake_override_as_a_grouped_one_does():
	var override := StandardMaterial3D.new()
	root.bake_material_override = override
	_tied("crate", "func_detail", Vector3.ZERO)
	var loose := _box(Vector3(10, 0, 0))
	loose.set_brush_entity_class("func_detail")
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var grouped := _baked("DetailGeometry")
	assert_not_null(grouped, "fixture: an unnamed func_detail is grouped")
	for node in grouped.find_children("*", "MeshInstance3D", true, false):
		for mat in _drawn_with(node as MeshInstance3D):
			assert_eq(mat, override, "fixture: a grouped one wears the override")
	for mat in _drawn_with(_baked("crate") as MeshInstance3D):
		assert_eq(mat, override, "and so does a named one")


func test_an_unpainted_door_bakes_with_no_material():
	_tied("gate", "func_door", Vector3.ZERO)
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var door := _baked("gate")
	assert_not_null(door, "the door keeps a node of its own")
	var meshes := door.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1, "fixture: one leaf")
	for mat in _drawn_with(meshes[0] as MeshInstance3D):
		assert_null(mat, "the leaf bakes with no material")


func test_a_trigger_bakes_no_mesh_to_wear_a_look():
	_tied("zone", "trigger_once", Vector3.ZERO)
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	var area := _baked("zone")
	assert_true(area is Area3D, "the trigger bakes as a volume")
	assert_eq(
		area.find_children("*", "MeshInstance3D", true, false).size(), 0, "with nothing drawn"
	)


# -- A custom shape through CSG ------------------------------------------------


## A doorway cut through a 4 x 3 x 4 room at the origin, so the bake goes
## through CSG.
func _doorway(cut_info: Dictionary = {}) -> DraftBrush:
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(1, 2, 6),
		"center": Vector3(0, 1, 0),
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
	}
	info.merge(cut_info, true)
	return root.create_brush_from_info(info) as DraftBrush


func _room() -> DraftBrush:
	return _box(Vector3(0, 1.5, 0), Vector3(4, 3, 4))


func test_an_unpainted_custom_room_bakes_solid_with_a_doorway():
	var room := _room()
	room.mark_faces_authoritative()
	assert_eq(room.shape, DraftBrush.BrushShape.CUSTOM, "fixture: a custom shape")
	_doorway()
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	_assert_no_editor_look(_all_baked_materials(), "a custom room with a doorway")


func test_an_unpainted_custom_cutter_carves_faces_with_no_material():
	_room()
	var cutter := _doorway()
	cutter.mark_faces_authoritative()
	assert_eq(cutter.shape, DraftBrush.BrushShape.CUSTOM, "fixture: a custom cutter")
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	_assert_no_editor_look(_all_baked_materials(), "the faces a custom cutter carved")


func test_a_pending_custom_cut_carves_faces_with_no_material():
	_room()
	var cutter := _doorway({"pending": true})
	cutter.mark_faces_authoritative()
	assert_true(
		DraftBrush.is_editor_look(cutter.editor_material), "fixture: drawn as a pending cut"
	)
	assert_true(await root.bake(true, false), "fixture: the level bakes")
	_assert_no_editor_look(_all_baked_materials(), "the faces a pending custom cut carved")


# -- Telling the editor's looks apart ------------------------------------------


func test_each_editor_look_is_marked_and_a_real_material_is_not():
	var brush := _box(Vector3.ZERO)
	assert_true(DraftBrush.is_editor_look(brush._default_material()), "the default")
	for op in [CSGShape3D.OPERATION_UNION, CSGShape3D.OPERATION_SUBTRACTION]:
		assert_true(DraftBrush.is_editor_look(root._make_brush_material(op)), "a drag preview")
		assert_true(
			DraftBrush.is_editor_look(root._make_brush_material(op, true, true)),
			"a cut's solid look"
		)
	assert_true(DraftBrush.is_editor_look(root._make_pending_cut_material()), "a pending cut")
	assert_false(DraftBrush.is_editor_look(StandardMaterial3D.new()), "a material of the level")
	assert_false(DraftBrush.is_editor_look(null), "or none")


## A new material each call has no identity to compare, so the mark has to be
## part of the material itself and come back from a file.
func test_the_mark_comes_back_from_a_saved_material():
	var path := "user://hf_editor_look_%d.tres" % Time.get_ticks_usec()
	var brush := _box(Vector3.ZERO)
	assert_eq(ResourceSaver.save(brush._default_material(), path), OK, "fixture: saved")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Material
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(
		DraftBrush.is_editor_look(loaded), "the reloaded default is still the editor's look"
	)


## Paint the preview laid over a look is the mapper's. It stays, laid over what
## the bake has in the look's place, as the face bake lays it.
func test_paint_over_an_editor_look_bakes_over_the_fallback():
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var painted := FaceData.composite_painted_material(root._make_pending_cut_material(), image)
	var paint: Texture2D = (painted as StandardMaterial3D).albedo_texture
	assert_true(DraftBrush.is_editor_look(painted), "fixture: the paint carries the look's mark")
	var bare := HFBakeSystem._baked_material(painted, null) as StandardMaterial3D
	assert_eq(bare.albedo_texture, paint, "the paint stays")
	assert_eq(bare.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "over nothing see-through")
	assert_false(DraftBrush.is_editor_look(bare), "and nothing of the look")
	var override := StandardMaterial3D.new()
	override.resource_name = "override"
	var over := HFBakeSystem._baked_material(painted, override) as StandardMaterial3D
	assert_eq(over.resource_name, "override", "over the bake's override when it has one")
	assert_eq(over.albedo_texture, paint)
