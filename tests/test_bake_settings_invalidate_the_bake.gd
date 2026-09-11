extends GutTest

## A bake setting change was not a change (#376). `bake_dirty()` rebuilt only
## what brush dirty state said needed rebuilding, and the settings were not part
## of what could be dirty, so flipping one and baking again left the previous
## result standing with nothing about it saying so.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String, position: Vector3) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"size": Vector3(64, 64, 64),
					"brush_id": brush_id,
					"transform": Transform3D(Basis.IDENTITY, position),
				}
			)
		)
		as DraftBrush
	)


func _signature() -> int:
	return root.bake_system.bake_settings_signature()


func test_every_setting_that_changes_the_bake_changes_the_signature():
	var before := _signature()
	for name in root.bake_system.BAKE_SETTING_NAMES:
		var original = root.get(name)
		match typeof(original):
			TYPE_BOOL:
				root.set(name, not original)
			TYPE_INT:
				root.set(name, original + 1)
			TYPE_FLOAT:
				root.set(name, original + 1.0)
			TYPE_AABB:
				root.set(name, AABB(Vector3(1, 1, 1), Vector3(8, 8, 8)))
			_:
				continue
		assert_ne(_signature(), before, "%s is in the signature" % name)
		root.set(name, original)
		assert_eq(_signature(), before, "%s put back" % name)


func test_the_material_override_is_in_the_signature():
	var before := _signature()
	root.bake_material_override = StandardMaterial3D.new()
	assert_ne(_signature(), before, "the override decides how the bake looks")
	root.bake_material_override = null
	assert_eq(_signature(), before)


func test_a_level_that_has_never_baked_still_reports_nothing_to_do():
	root._dirty_brush_ids = {}
	root._full_reconcile_needed = false
	var ok: bool = await root.bake_dirty()
	assert_false(ok, "no bake has happened, so there is no result to go stale")
	assert_eq(root.bake_system.get_last_bake_status(), 4, "still NOTHING_TO_DO")


func test_a_rebake_after_a_setting_changes_rebuilds_rather_than_doing_nothing():
	_box("a", Vector3.ZERO)
	_box("b", Vector3(256, 0, 0))
	assert_true(await root.bake(), "the first bake")
	root._dirty_brush_ids = {}
	root._full_reconcile_needed = false

	# Nothing changed: the rebake still declines, as it always did.
	assert_false(await root.bake_dirty(), "no changes at all is still nothing to do")

	# One setting flipped, no brush touched.
	root.bake_visible_only = not root.bake_visible_only
	assert_true(
		await root.bake_dirty(),
		"a changed setting is a change, so the result is built from the settings that are set"
	)


func test_a_rebake_after_the_cordon_changes_rebuilds():
	_box("a", Vector3.ZERO)
	assert_true(await root.bake())
	root._dirty_brush_ids = {}
	root._full_reconcile_needed = false
	root.cordon_enabled = true
	assert_true(await root.bake_dirty(), "the cordon decides which brushes are in the bake")
