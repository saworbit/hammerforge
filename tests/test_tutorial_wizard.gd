extends GutTest

const HFTutorialWizard = preload("res://addons/hammerforge/ui/hf_tutorial_wizard.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

var wizard: PanelContainer
var prefs: HFUserPrefsType


func before_each():
	prefs = HFUserPrefsType.new()
	prefs.data = HFUserPrefsType._defaults()
	wizard = HFTutorialWizard.new()
	wizard.set_user_prefs(prefs)
	add_child_autofree(wizard)


func after_each():
	wizard = null
	prefs = null


# -- Tests ----------------------------------------------------------------------


func test_step_count():
	assert_eq(HFTutorialWizard.get_step_count(), 5, "Tutorial should have 5 steps")


func test_initial_step_zero():
	assert_eq(wizard.get_current_step(), 0, "Should start at step 0")


func test_start_at_custom_step():
	# Start at step 2 (simulating resume)
	wizard.start(null, null, 2)
	assert_eq(wizard.get_current_step(), 2, "Should resume at step 2")


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
	wizard._on_skip()
	assert_eq(wizard.get_current_step(), 2, "Skip should advance to step 2")


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
	# Simulate resume: prefs say we were on step 3, and start() was never called
	prefs.set_pref("tutorial_step", 3)
	var late_wizard = HFTutorialWizard.new()
	late_wizard.set_user_prefs(prefs)
	add_child_autofree(late_wizard)
	var mock_root = Node3D.new()
	add_child_autofree(mock_root)
	late_wizard.set_root(mock_root, null)
	assert_eq(late_wizard.get_current_step(), 3, "Should resume at saved step 3")
