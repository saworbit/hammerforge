extends GutTest

## A level taken out of the tree and put back keeps its autosave and its subtract
## preview (#928).
##
## The editor does this on every scene tab switch, and _ready() does not run the
## second time. _exit_tree() stopped both, and nothing started them again, so one
## tab switch ended autosave for the session while the Inspector still said on.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var holder: Node3D
var root: LevelRoot


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)
	root = LevelRootType.new()
	root.auto_spawn_player = false
	holder.add_child(root)
	# _ready() only starts autosave in the editor. Start it the way it does there.
	root._setup_autosave()


func after_each():
	holder = null
	root = null


## What the editor does when you switch to another scene tab and back.
func _switch_tab_away_and_back() -> void:
	holder.remove_child(root)
	assert_false(root.is_inside_tree())
	holder.add_child(root)


func test_autosave_runs_again_after_a_tab_switch():
	assert_not_null(root._autosave_timer, "the editor starts autosave on open")
	_switch_tab_away_and_back()
	assert_true(root.hflevel_autosave_enabled, "the Inspector still says on")
	assert_not_null(root._autosave_timer, "so a timer has to be running")
	if root._autosave_timer:
		assert_true(root._autosave_timer.is_inside_tree())
		assert_false(root._autosave_timer.is_stopped())
		assert_true(
			root._autosave_timer.timeout.is_connected(root._on_autosave_timeout),
			"and still saving when it fires"
		)


func test_two_tab_switches_leave_one_timer():
	_switch_tab_away_and_back()
	_switch_tab_away_and_back()
	var timers := 0
	for child in root.get_children():
		if child is Timer and child.timeout.is_connected(root._on_autosave_timeout):
			timers += 1
	assert_eq(timers, 1, "one timer saving, not one per switch")


func test_autosave_turned_off_stays_off_after_a_tab_switch():
	# In the editor the setter also frees the timer. Headless it stops short of
	# that, so the timer is still here to be torn down on the way out.
	root.hflevel_autosave_enabled = false
	_switch_tab_away_and_back()
	assert_null(root._autosave_timer, "re-entry does not restart an autosave that is off")


func test_the_subtract_preview_comes_back_after_a_tab_switch():
	root.show_subtract_preview = true
	assert_true(root.subtract_preview.is_enabled())
	_switch_tab_away_and_back()
	assert_true(root.subtract_preview.is_enabled(), "show_subtract_preview is still on")


func test_a_subtract_preview_that_was_off_stays_off():
	assert_false(root.show_subtract_preview)
	_switch_tab_away_and_back()
	assert_false(root.subtract_preview.is_enabled())
