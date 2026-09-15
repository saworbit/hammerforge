extends GutTest

## A brush preset is told apart from another only by its button label, so two
## buttons reading the same thing leave the mapper clicking one to find out which
## it is.
##
## `_suggest_preset_name()` counted the buttons on screen, which matches the
## highest name in use only while none has ever been deleted. `_unique_preset_path()`
## made the *file* unique and left `resource_name` alone, and
## `_preset_display_name()` returns `resource_name` when it is set, so the label
## was the one thing that collided.

const DockType = preload("res://addons/hammerforge/dock.gd")


## A stand-in for the button row: `_suggest_preset_name()` reads `text` off each.
class FakePresetButton:
	extends Button


func _dock_with_presets(names: Array) -> Node:
	# Not added to the tree: `_ready()` builds the whole dock and the naming does
	# not need any of it, only the button row.
	var dock := DockType.new()
	autofree(dock)
	for preset_name in names:
		var button := FakePresetButton.new()
		button.text = str(preset_name)
		autoqfree(button)
		dock.preset_buttons.append(button)
	return dock


func test_the_first_preset_is_preset_1():
	assert_eq(_dock_with_presets([])._suggest_preset_name(), "Preset 1")


func test_the_next_preset_follows_the_ones_on_screen():
	var dock := _dock_with_presets(["Preset 1", "Preset 2"])
	assert_eq(dock._suggest_preset_name(), "Preset 3")


## Three saves, delete the middle one, save again. The count says 3 and 3 is
## taken.
func test_deleting_from_the_middle_does_not_produce_a_second_preset_3():
	var dock := _dock_with_presets(["Preset 1", "Preset 3"])

	assert_ne(dock._suggest_preset_name(), "Preset 3", "that name is on screen already")


func test_a_longer_run_of_deletes_still_names_something_free():
	var dock := _dock_with_presets(["Preset 3", "Preset 4", "Preset 5"])

	var suggested: String = dock._suggest_preset_name()

	for existing in ["Preset 3", "Preset 4", "Preset 5"]:
		assert_ne(suggested, existing, "%s is taken" % existing)


func test_a_renamed_preset_still_counts_as_taken():
	var dock := _dock_with_presets(["Doorway", "Preset 2"])

	assert_ne(dock._suggest_preset_name(), "Preset 2")


## A preset renamed to something else entirely leaves the numbered names free.
func test_names_that_are_not_numbered_do_not_push_the_suggestion_up():
	var dock := _dock_with_presets(["Doorway"])

	assert_eq(dock._suggest_preset_name(), "Preset 2", "one button on screen, so the count is 2")
