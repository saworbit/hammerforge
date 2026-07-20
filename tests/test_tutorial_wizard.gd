extends GutTest

const HFTutorialWizard = preload("res://addons/hammerforge/ui/hf_tutorial_wizard.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

var wizard: PanelContainer
var prefs: HFUserPrefsType


func before_each():
	prefs = HFUserPrefsType.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefsType._defaults()
	wizard = HFTutorialWizard.new()
	wizard.set_user_prefs(prefs)
	add_child_autofree(wizard)


func after_each():
	wizard = null
	prefs = null


# -- Tests ----------------------------------------------------------------------


func test_step_count():
	assert_eq(HFTutorialWizard.get_step_count(), 2, "Tutorial should teach one short workflow")


func test_initial_step_zero():
	assert_eq(wizard.get_current_step(), 0, "Should start at step 0")


func test_start_at_custom_step():
	# Start at the final step (simulating resume)
	wizard.start(null, null, 1)
	assert_eq(wizard.get_current_step(), 1, "Should resume at the final step")


func test_primary_action_emits_step_setup_action():
	var received: Array[String] = []
	wizard.action_requested.connect(func(action: String): received.append(action))
	wizard.start(null, null, 0)
	wizard._on_primary_action()
	assert_eq(received, ["setup_draw"])


func test_back_returns_to_previous_step():
	wizard.start(null, null, 0)
	wizard._on_skip()
	wizard._on_back()
	assert_eq(wizard.get_current_step(), 0)


func test_first_step_progress_is_visible():
	wizard.start(null, null, 0)
	assert_eq(int(wizard._progress.value), 1)
	assert_eq(wizard._step_counter.text, "Step 1 of 2")


func test_final_step_is_one_click_test_level():
	assert_eq(HFTutorialWizard.STEPS[1]["signal_name"], "bake_finished")
	assert_eq(HFTutorialWizard.STEPS[1]["action"], "quick_play")
	assert_eq(HFTutorialWizard.STEPS[1]["action_label"], "Test Level Now")


func test_start_step_clamped():
	wizard.start(null, null, 99)
	assert_eq(
		wizard.get_current_step(),
		HFTutorialWizard.get_step_count() - 1,
		"Oversized step should clamp to last"
	)


func test_step_persists_to_prefs():
	wizard.start(null, null, 0)
	# Advance manually via skip
	wizard._on_skip()
	assert_eq(int(prefs.get_pref("tutorial_step", 0)), 1, "Step should persist to prefs")


func test_skip_advances_step():
	wizard.start(null, null, 0)
	wizard._on_skip()
	assert_eq(wizard.get_current_step(), 1, "Skip should advance to step 1")


func test_dismiss_emits_signal():
	var received := [false]
	wizard.dismissed.connect(func(dont_show): received[0] = true)
	wizard._on_dismiss()
	assert_true(received[0], "Dismiss should emit dismissed signal")


func test_complete_emits_signal():
	var received := [false]
	wizard.completed.connect(func(): received[0] = true)
	wizard.start(null, null, 0)
	# Skip through all steps
	for i in range(HFTutorialWizard.get_step_count()):
		wizard._on_skip()
	assert_true(received[0], "Completing all steps should emit completed signal")


func test_validate_bake_success_passes_on_true():
	assert_true(wizard._validate_bake_success(true), "Should pass on successful bake")


func test_validate_bake_success_rejects_failure():
	assert_false(wizard._validate_bake_success(false), "Should reject failed bake")


func test_validate_subtract_true_when_no_root():
	# With no root set, validation should pass (permissive)
	var result: bool = wizard._validate_subtract("some_id")
	assert_true(result, "Should return true when no root available")


func test_no_root_safe():
	# Starting with no root should not error
	wizard.start(null, null, 0)
	assert_eq(wizard.get_current_step(), 0, "Should be at step 0 with no root")
	wizard._on_skip()
	assert_eq(wizard.get_current_step(), 1, "Should still advance without root")


func test_set_root_deferred_start():
	# Simulate the no-LevelRoot startup path: wizard is created without start()
	# being called, then set_root() is called later when root appears.
	var late_wizard = HFTutorialWizard.new()
	late_wizard.set_user_prefs(prefs)
	add_child_autofree(late_wizard)
	# At this point start() was never called — labels should be empty
	assert_eq(late_wizard.get_current_step(), 0, "Should be at step 0 before set_root")
	# Now simulate root appearing — set_root should do the full init
	var mock_root = Node3D.new()
	add_child_autofree(mock_root)
	late_wizard.set_root(mock_root, null)
	assert_eq(late_wizard.get_current_step(), 0, "Should be at step 0 after deferred start")
	# Verify labels are populated (not blank)
	assert_ne(late_wizard._title_label.text, "", "Title should be populated after deferred start")
	assert_ne(late_wizard._text_label.text, "", "Text should be populated after deferred start")


func test_set_root_deferred_resumes_saved_step():
	# Simulate resume: prefs say we were on the final step, and start() was never called
	prefs.set_pref("tutorial_step", 1)
	var late_wizard = HFTutorialWizard.new()
	late_wizard.set_user_prefs(prefs)
	add_child_autofree(late_wizard)
	var mock_root = Node3D.new()
	add_child_autofree(mock_root)
	late_wizard.set_root(mock_root, null)
	assert_eq(late_wizard.get_current_step(), 1, "Should resume at the saved final step")
