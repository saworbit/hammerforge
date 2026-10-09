extends GutTest

## A bake setting change was not a change (#376). `bake_dirty()` rebuilt only
## what brush dirty state said needed rebuilding, and the settings were not part
## of what could be dirty, so flipping one and baking again left the previous
## result standing with nothing about it saying so.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

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
		# The signature reads the list by name, and a name the level does not
		# have would read as null and change nothing.
		assert_true(name in root, "%s is a setting on the level" % name)
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
			TYPE_ARRAY:
				# The extra cordons, a list of boxes, and which cordons bake, a list
				# of switches.
				match (original as Array).get_typed_builtin():
					TYPE_AABB:
						var more: Array[AABB] = [AABB(Vector3(1, 1, 1), Vector3(8, 8, 8))]
						root.set(name, more)
					TYPE_BOOL:
						var off: Array[bool] = [false]
						root.set(name, off)
					var element:
						fail_test(
							(
								"%s holds %s, which this test cannot change"
								% [name, type_string(element)]
							)
						)
						continue
			_:
				# Skipping it would pass a setting this test never changed.
				fail_test(
					(
						"%s is a %s, which this test cannot change"
						% [name, type_string(typeof(original))]
					)
				)
				continue
		assert_ne(_signature(), before, "%s is in the signature" % name)
		root.set(name, original)
		assert_eq(_signature(), before, "%s put back" % name)


func test_every_bake_setting_rebuilds_through_the_tracker_and_the_dock():
	# The change tracker and the dock each kept their own list of the cordon
	# settings, so a cordon setting added to one rebuilt from that path and not the
	# other (#975). Both ask is_bake_setting() now; this walks every bake setting
	# through both.
	var watched := HFBrushChangeTracker._bake_configuration_signature(root)
	var dock := DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	for name in root.bake_system.BAKE_SETTING_NAMES:
		assert_true(watched.has(name), "the change tracker watches %s" % name)
		root._full_reconcile_needed = false
		dock._tag_bake_setting_change(name)
		assert_true(root._full_reconcile_needed, "a dock edit of %s rebuilds" % name)


## The level's bake settings that are not in the signature list, and why.
const NOT_IN_THE_LIST := {
	"bake_use_thread_pool": "decides where the work runs, not what it makes",
	"bake_material_override": "goes in by resource path, tested below",
}


func test_every_bake_setting_on_the_level_is_in_the_signature():
	# Agent Climb and Agent Slope shape the navmesh and were missing from the
	# list. The editor's change tracker reads every bake_ property and covered for
	# them; a bake with no tracker running, as from a script, kept the old navmesh.
	# A bake profile sets them too.
	for property in root.get_property_list():
		var name := str(property["name"])
		if not name.begins_with("bake_") or not (property["usage"] & PROPERTY_USAGE_EDITOR):
			continue
		if NOT_IN_THE_LIST.has(name):
			continue
		assert_true(
			name in root.bake_system.BAKE_SETTING_NAMES,
			"%s changes the bake, so changing it has to make the bake out of date" % name
		)


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
