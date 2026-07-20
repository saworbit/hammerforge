extends GutTest
## Regression coverage for dock-owned tutorial lifecycle guards.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const UserPrefs = preload("res://addons/hammerforge/hf_user_prefs.gd")

var dock: HammerForgeDock


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)


func after_each() -> void:
	dock = null


func test_show_welcome_panel_is_idempotent_while_tutorial_is_active() -> void:
	dock._show_welcome_panel()
	var first_wizard = dock._tutorial_wizard
	var dock_vbox := dock.get_node("Margin/VBox")
	var child_count := dock_vbox.get_child_count()

	assert_not_null(first_wizard)
	dock._show_welcome_panel()

	assert_eq(dock._tutorial_wizard, first_wizard)
	assert_eq(dock_vbox.get_child_count(), child_count)


func test_user_pref_guard_tracks_tutorial_instead_of_legacy_welcome_panel() -> void:
	var legacy_panel := PanelContainer.new()
	dock.get_node("Margin/VBox").add_child(legacy_panel)
	dock._welcome_panel = legacy_panel

	var prefs := UserPrefs.new()
	prefs.persistence_enabled = false
	prefs.data = UserPrefs._defaults()
	dock.set_user_prefs(prefs)

	assert_not_null(
		dock._tutorial_wizard,
		"A stale legacy welcome panel must not suppress the active tutorial wizard",
	)
