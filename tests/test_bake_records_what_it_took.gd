extends GutTest

## A full bake waits a frame now and then so the editor stays responsive, and the
## editor can be edited while it waits.
##
## It recorded which brushes it built, which Bake Selected reads later, and how
## many it took, which the estimate divides by, after those waits: a brush drawn
## while it waited was in the record of a bake that never built it (#1671).
##
## And the dock's Last bake was the time without those waits, the estimate's
## number, so a mapper read a bake far shorter than the one they waited for
## (#1623).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")

## Enough brushes that the default bake waits a frame between batches of them.
const BRUSHES := 20
## How long each frame wait takes, at least, in a bake that waits slowly.
const SLOW_FRAME_MS := 15


## Every frame wait takes at least `SLOW_FRAME_MS`, as a busy editor's does.
class SlowFrames:
	extends "res://addons/hammerforge/systems/hf_bake_system.gd"

	func _wait_frames(count: int) -> bool:
		OS.delay_msec(SLOW_FRAME_MS)
		return await super(count)


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _box(root: LevelRoot, at: Vector3, brush_id: String) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D(Basis.IDENTITY, at),
				"brush_id": brush_id,
			}
		)
	)


func _level(root: LevelRoot) -> void:
	for i in BRUSHES:
		_box(root, Vector3(i * 4, 1, 0), "b%d" % i)


func test_a_brush_drawn_while_the_bake_waits_is_not_in_its_record():
	var root := _fresh_root()
	_level(root)
	assert_true(root.bake_use_face_materials, "the default bake, which waits between batches")
	# Started and left running: it stops at its first frame wait.
	root.bake()
	assert_true(root.bake_system._bake_in_flight, "the bake is waiting")
	_box(root, Vector3(0, 1, 40), "late")
	await wait_for_signal(root.bake_finished, 10)
	var record: PackedStringArray = root.baked_container.get_meta(HFBakeSystem.BAKED_BRUSH_IDS_META)
	assert_eq(record.size(), BRUSHES, "the record lists the brushes the bake took")
	assert_false(record.has("late"), "not one drawn while it waited")
	assert_eq(root.bake_system._last_bake_brush_count, BRUSHES, "and the estimate counts those")


func test_last_bake_is_the_time_the_mapper_waited():
	var root := _fresh_root()
	root.bake_system = SlowFrames.new(root)
	_level(root)
	assert_true(await root.bake())
	var waited: int = root.get_last_bake_duration_ms()
	var worked: int = root._last_bake_duration_ms
	assert_gte(waited - worked, SLOW_FRAME_MS, "Last bake takes in the waits")
	assert_gt(worked, -1, "and the estimate's time is still the work alone")


func test_the_level_health_names_the_pause_after_an_edit():
	var root := _fresh_root()
	assert_eq(root.get_level_health()["label"], "Healthy")
	for i in 101:
		_box(root, Vector3(i * 3, 1, 0), "h%d" % i)
	var health: Dictionary = root.get_level_health()
	assert_eq(health["label"], "Edits Slowing")
	assert_eq(health["severity"], 1)
	assert_string_contains(health["detail"], "pause after an edit")
	assert_string_contains(health["detail"], "HammerForge_Performance.md")
