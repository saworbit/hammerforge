extends GutTest

## The showcase level is the one in the README hero, the docs' how-it-works strip
## and every dock screenshot, and Run Check on it has to come back clean. It was
## laid out on the old Quake-family grid, a 48 by 64 m hall with 26 m walls, and
## its dais steps rose 0.70 m over the 0.40 m the playtest player steps up, so
## `docs/images/ui_console.png` showed the check reporting the showcase's own
## stairs (#1331). `tools/build_showcase_scene.gd` builds it in metres now, and
## these hold it there: the check runs on the scene it writes, the way Run Check
## runs it, and the hall stays the size the User Guide's World Scale describes.

const HFPlayerMetrics = preload("res://addons/hammerforge/hf_player_metrics.gd")

const SHOWCASE := "res://samples/hf_demo_showcase.tscn"
# The staged copies the how-it-works strip is captured from, built by the same
# script from the same layout.
const STAGES := [
	"res://samples/hf_demo_step1.tscn",
	"res://samples/hf_demo_step2.tscn",
	"res://samples/hf_demo_step3.tscn",
]


## The scene at `path`, in the tree with the editor-only conveniences off, as the
## other tests build their LevelRoot.
func _open(path: String) -> LevelRoot:
	var packed: PackedScene = load(path)
	assert_not_null(packed, path + " loads")
	if packed == null:
		return null
	var level := packed.instantiate() as LevelRoot
	assert_not_null(level, path + " is a LevelRoot scene")
	if level == null:
		return null
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## What Run Check reports: `HFDockManageHandler.run_validation()` reads
## `validate_level(false)["issues"]`.
func _run_check(level: LevelRoot) -> Array:
	return level.validate_level(false).get("issues", [])


func test_run_check_on_the_showcase_reports_no_issues() -> void:
	var level := _open(SHOWCASE)
	if level == null:
		return
	assert_gt(level.brush_system.get_live_brush_count(), 60, "the whole hall is in the scene")
	var issues := _run_check(level)
	assert_eq(issues.size(), 0, "Run Check on the showcase reports: %s" % str(issues))


func test_the_showcase_is_built_in_metres() -> void:
	var level := _open(SHOWCASE)
	if level == null:
		return
	# A room is eight to twelve metres across and a wall a few metres tall; the
	# hall with its corner towers fits well inside twice that. The old layout
	# spanned 54 by 72 m and 32 m up.
	var bounds: AABB = level._compute_level_aabb()
	assert_lt(bounds.size.x, 16.0, "the hall is metres across, not Quake units")
	assert_lt(bounds.size.z, 20.0, "the hall is metres deep, not Quake units")
	assert_lt(bounds.size.y, 10.0, "the walls and towers are metres tall")
	# Only the floor slab reaches below the ground the player stands on.
	assert_almost_eq(bounds.position.y, -0.5, 0.001, "the floor's top is the ground at y=0")


func test_every_dais_step_is_one_the_player_walks_up() -> void:
	var level := _open(SHOWCASE)
	if level == null:
		return
	var step_height := float(HFPlayerMetrics.standing()["step_height"])
	var last_top := 0.0
	for i in range(3):
		var step := level.draft_brushes_node.get_node_or_null("DaisStep%d" % i) as DraftBrush
		assert_not_null(step, "DaisStep%d is in the showcase" % i)
		if step == null:
			return
		var top: float = step.global_position.y + step.size.y * 0.5
		assert_true(
			top - last_top <= step_height,
			"DaisStep%d rises %.2f m, within the %.2f m step" % [i, top - last_top, step_height]
		)
		last_top = top


func test_the_staged_scenes_pass_the_check_too() -> void:
	for path in STAGES:
		var level := _open(path)
		if level == null:
			continue
		var issues := _run_check(level)
		assert_eq(issues.size(), 0, "%s reports: %s" % [path, str(issues)])
