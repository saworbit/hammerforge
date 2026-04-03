extends GutTest

const HFCoachMarks = preload("res://addons/hammerforge/ui/hf_coach_marks.gd")
const HFUserPrefs = preload("res://addons/hammerforge/hf_user_prefs.gd")

var coach: HFCoachMarks
var prefs: HFUserPrefs


func before_each():
	coach = HFCoachMarks.new()
	prefs = HFUserPrefs.new()
	prefs.data = HFUserPrefs._defaults()
	coach.set_user_prefs(prefs)
	add_child(coach)


func after_each():
	coach.free()
	coach = null
	prefs = null


# ===========================================================================
# Guide data
# ===========================================================================


func test_guides_defined():
	assert_gt(HFCoachMarks.GUIDES.size(), 0)


func test_all_guides_have_required_fields():
	for key in HFCoachMarks.GUIDES:
		var guide: Dictionary = HFCoachMarks.GUIDES[key]
		assert_true(guide.has("title"), "Guide '%s' missing title" % key)
		assert_true(guide.has("steps"), "Guide '%s' missing steps" % key)
		assert_gt(guide["steps"].size(), 0, "Guide '%s' has no steps" % key)


func test_get_guide_keys():
	var keys := HFCoachMarks.get_guide_keys()
	assert_gt(keys.size(), 0)
	assert_true("polygon" in keys)
	assert_true("vertex_edit" in keys)


# ===========================================================================
# Show / hide
# ===========================================================================


func test_initially_hidden():
	assert_false(coach.visible)


func test_show_guide_makes_visible():
	var shown := coach.show_guide("polygon")
	assert_true(shown)
	assert_true(coach.visible)


func test_show_unknown_guide_returns_false():
	var shown := coach.show_guide("nonexistent_tool")
	assert_false(shown)
	assert_false(coach.visible)


func test_hide_guide():
	coach.show_guide("polygon")
	coach.hide_guide()
	assert_false(coach.visible)
	assert_eq(coach.get_current_tool_key(), "")


func test_current_tool_key_set():
	coach.show_guide("carve")
	assert_eq(coach.get_current_tool_key(), "carve")


# ===========================================================================
# Dismissal and persistence
# ===========================================================================


func test_dismiss_hides_guide():
	coach.show_guide("polygon")
	coach._on_dismiss()
	assert_false(coach.visible)


func test_dismiss_with_dont_show_persists():
	coach.show_guide("polygon")
	coach._dont_show.button_pressed = true
	coach._on_dismiss()
	# Now trying to show again should fail
	var shown := coach.show_guide("polygon")
	assert_false(shown)


func test_dismiss_without_dont_show_allows_reshowing():
	coach.show_guide("polygon")
	coach._dont_show.button_pressed = false
	coach._on_dismiss()
	# Should still be able to show
	var shown := coach.show_guide("polygon")
	assert_true(shown)


func test_dismissed_signal_emitted():
	var received := []
	coach.guide_dismissed.connect(func(tool_key, dont_show): received.append([tool_key, dont_show]))
	coach.show_guide("carve")
	coach._dont_show.button_pressed = true
	coach._on_dismiss()
	assert_eq(received.size(), 1)
	assert_eq(received[0][0], "carve")
	assert_true(received[0][1])


# ===========================================================================
# No prefs
# ===========================================================================


func test_works_without_prefs():
	var coach2 = HFCoachMarks.new()
	add_child(coach2)
	var shown := coach2.show_guide("polygon")
	assert_true(shown)
	coach2.free()


# ===========================================================================
# Step content
# ===========================================================================


func test_polygon_steps_populated():
	coach.show_guide("polygon")
	var step_count := coach._steps_container.get_child_count()
	assert_eq(step_count, HFCoachMarks.GUIDES["polygon"]["steps"].size())


func test_title_set():
	coach.show_guide("vertex_edit")
	assert_eq(coach._title_label.text, "Vertex Editing")
