extends GutTest

## The mechanics the six previews used to each own a copy of.
##
## Hollow, carve, clip, subtract, structure and array each wrote out a container
## node, a set of `MeshInstance3D`, a ghost material and a teardown. Two of them
## even called the container by a different name from the other four. That
## duplication is what let four of them drift into placing their meshes in the
## wrong space — each was fixed on its own, because there was nowhere to fix it
## once.
##
## `tests/test_preview_placement.gd` holds the property they share. This holds the
## mechanics.

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _preview() -> HFPreviewSystem:
	return HFPreviewSystem.new(root)


# ===========================================================================
# The ghost material
# ===========================================================================


func test_a_ghost_is_unshaded_transparent_and_always_on_top():
	var material := HFPreviewSystem.ghost_material(Color(1, 0, 0, 0.5))
	assert_eq(material.albedo_color, Color(1, 0, 0, 0.5))
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_true(
		material.no_depth_test,
		"a ghost hidden behind the solid it is about to replace is not a preview"
	)


func test_a_ghost_is_one_sided_unless_it_asks_not_to_be():
	assert_ne(HFPreviewSystem.ghost_material(Color.RED).cull_mode, BaseMaterial3D.CULL_DISABLED)
	assert_eq(
		HFPreviewSystem.ghost_material(Color.RED, true).cull_mode, BaseMaterial3D.CULL_DISABLED
	)


# ===========================================================================
# The container
# ===========================================================================


func test_the_container_is_made_on_first_use_and_hangs_off_the_root():
	var preview := _preview()
	assert_null(preview._preview_container, "nothing is made before it is needed")
	preview._ensure_container()
	assert_not_null(preview._preview_container)
	assert_eq(preview._preview_container.get_parent(), root)
	preview.destroy()


func test_the_container_carries_the_name_the_preview_gives_it():
	var preview := _preview()
	preview._ensure_container()
	assert_eq(str(preview._preview_container.name), preview._preview_name())
	preview.destroy()


func test_asking_twice_does_not_make_a_second_container():
	var preview := _preview()
	# The LevelRoot has containers of its own, so the count that matters is how
	# many more children it has than it started with.
	var before := root.get_child_count()
	preview._ensure_container()
	var first := preview._preview_container
	preview._ensure_container()
	assert_eq(preview._preview_container, first)
	assert_eq(root.get_child_count(), before + 1, "one container, not two")
	preview.destroy()


func test_every_preview_names_its_container_differently():
	# Two of them used to be called `_container` and four `_preview_container`,
	# which is how a shared mechanic drifts into six of them. The scene tree still
	# has to say which overlay a node belongs to.
	var names: Array = []
	for preview in [
		HFArrayPreview.new(root),
		HFCarvePreview.new(root),
		HFClipPreview.new(root),
		HFHollowPreview.new(root),
		HFStructurePreview.new(root),
		HFSubtractPreview.new(root),
	]:
		var preview_name: String = preview._preview_name()
		assert_false(names.has(preview_name), "'%s' is used twice" % preview_name)
		assert_ne(preview_name, "Preview", "every preview overrides the default name")
		names.append(preview_name)
	assert_eq(names.size(), 6)


# ===========================================================================
# The meshes
# ===========================================================================


func test_a_made_mesh_goes_under_the_container_and_into_the_pool():
	var preview := _preview()
	var material := HFPreviewSystem.ghost_material(Color.RED)
	var mesh_instance := preview._make_mesh(material)
	assert_eq(mesh_instance.get_parent(), preview._preview_container)
	assert_eq(mesh_instance.material_override, material)
	assert_eq(
		mesh_instance.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a ghost does not cast a shadow"
	)
	assert_eq(preview._mesh_pool.size(), 1)
	preview.destroy()


func test_making_a_mesh_makes_the_container_it_needs():
	var preview := _preview()
	preview._make_mesh(HFPreviewSystem.ghost_material(Color.RED))
	assert_not_null(preview._preview_container, "a mesh has to hang off something")
	preview.destroy()


func test_the_pool_grows_to_the_count_asked_for_and_no_further():
	var preview := _preview()
	var material := HFPreviewSystem.ghost_material(Color.RED)
	preview._grow_pool(3, material)
	assert_eq(preview._mesh_pool.size(), 3)
	preview._grow_pool(5, material)
	assert_eq(preview._mesh_pool.size(), 5)
	# A preview that drew fewer pieces this time hides the leftovers rather than
	# freeing them, so the pool never shrinks.
	preview._grow_pool(2, material)
	assert_eq(preview._mesh_pool.size(), 5)
	preview.destroy()


func test_hiding_from_an_index_leaves_the_ones_before_it_showing():
	var preview := _preview()
	preview._grow_pool(4, HFPreviewSystem.ghost_material(Color.RED))
	for mesh_instance in preview._mesh_pool:
		mesh_instance.visible = true
	preview._hide_meshes_from(2)
	assert_true(preview._mesh_pool[0].visible)
	assert_true(preview._mesh_pool[1].visible)
	assert_false(preview._mesh_pool[2].visible)
	assert_false(preview._mesh_pool[3].visible)
	preview.destroy()


# ===========================================================================
# Clearing, enabling and teardown
# ===========================================================================


func test_clearing_hides_every_mesh_and_the_container():
	var preview := _preview()
	preview._grow_pool(3, HFPreviewSystem.ghost_material(Color.RED))
	for mesh_instance in preview._mesh_pool:
		mesh_instance.visible = true
	preview.set_enabled(true)
	preview.clear()
	for mesh_instance in preview._mesh_pool:
		assert_false(mesh_instance.visible)
	assert_false(preview._preview_container.visible)
	assert_false(preview.is_enabled(), "a cleared preview is not an enabled one")
	preview.destroy()


func test_enabling_makes_the_container_and_disabling_clears():
	var preview := _preview()
	preview.set_enabled(true)
	assert_true(preview.is_enabled())
	assert_not_null(preview._preview_container)
	assert_true(preview._preview_container.visible)
	preview.set_enabled(false)
	assert_false(preview.is_enabled())
	assert_false(preview._preview_container.visible)
	preview.destroy()


func test_destroy_takes_the_container_out_of_the_tree_and_frees_it():
	var preview := _preview()
	var before := root.get_child_count()
	preview._grow_pool(2, HFPreviewSystem.ghost_material(Color.RED))
	var preview_name := preview._preview_name()
	preview.destroy()
	assert_null(preview._preview_container)
	assert_eq(preview._mesh_pool.size(), 0)
	assert_null(root.get_node_or_null(preview_name), "the overlay went with the level")
	assert_eq(root.get_child_count(), before)
	assert_false(preview.is_enabled())


func test_destroy_is_safe_with_nothing_made():
	var preview := _preview()
	preview.destroy()
	assert_null(preview._preview_container)


func test_destroy_twice_is_safe():
	var preview := _preview()
	preview._make_mesh(HFPreviewSystem.ghost_material(Color.RED))
	preview.destroy()
	preview.destroy()
	assert_null(preview._preview_container)


func test_a_preview_with_no_root_makes_nothing_rather_than_failing():
	var orphan := HFPreviewSystem.new(null)
	orphan._ensure_container()
	assert_null(orphan._preview_container)
	orphan.destroy()
