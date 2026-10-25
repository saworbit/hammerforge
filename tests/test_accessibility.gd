extends GutTest

## The system's motion, contrast and transparency settings, and a name and a place
## in the Tab order for every control (#1703).

const HFAccessibility = preload("res://addons/hammerforge/hf_accessibility.gd")
const HFOverlayColors = preload("res://addons/hammerforge/hf_overlay_colors.gd")
const HFToast = preload("res://addons/hammerforge/ui/hf_toast.gd")
const HFRadialMenu = preload("res://addons/hammerforge/ui/hf_radial_menu.gd")
const HFStatusLamp = preload("res://addons/hammerforge/ui/hf_status_lamp.gd")
const HFStatusBoard = preload("res://addons/hammerforge/hf_status_board.gd")
const HFConsolePanel = preload("res://addons/hammerforge/ui/hf_console_panel.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")


func after_each() -> void:
	HFAccessibility.motion = HFAccessibility.Motion.SYSTEM
	HFAccessibility.system_stand_in = {}
	HFOverlayColors.follow_system_contrast = false
	HFOverlayColors.less_transparency = false
	HFOverlayColors.reset()


## A toast's tween, stepped to half a second before it would be gone.
func _toast_near_its_end(level: int) -> PanelContainer:
	var toasts := HFToast.new()
	add_child_autofree(toasts)
	toasts.show_toast("Hollow works on brushes only", level)
	var panel: PanelContainer = toasts.get_child(toasts.get_child_count() - 1)
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.custom_step(HFToast.DURATION_WARNING - 0.5)
	return panel


func test_reduced_motion_shows_a_toast_without_a_fade():
	HFAccessibility.motion = HFAccessibility.Motion.ANIMATE
	var faded := _toast_near_its_end(1)
	assert_lt(faded.modulate.a, 0.9, "animated, it is fading half a second before the end")
	HFAccessibility.motion = HFAccessibility.Motion.REDUCE
	var held := _toast_near_its_end(1)
	assert_eq(held.modulate.a, 1.0, "with less motion it is there at full strength, then gone")


func test_follow_system_takes_the_system_s_answer():
	HFAccessibility.motion = HFAccessibility.Motion.SYSTEM
	HFAccessibility.system_stand_in = {"motion": true}
	assert_true(HFAccessibility.reduce_motion(), "the system asks for less motion")
	HFAccessibility.system_stand_in = {"motion": false}
	assert_false(HFAccessibility.reduce_motion())
	HFAccessibility.motion = HFAccessibility.Motion.REDUCE
	assert_true(HFAccessibility.reduce_motion(), "and the setting overrides it")


func test_more_contrast_starts_in_high_contrast_unless_colours_were_picked():
	var prefs := HFUserPrefs.new()
	prefs.persistence_enabled = false
	HFOverlayColors.follow_system_contrast = true
	HFOverlayColors.apply_prefs(prefs)
	var key := HFOverlayColors.SELECTED_BRUSH
	assert_eq(HFOverlayColors.get_color(key), HFOverlayColors.HIGH_CONTRAST[key], "High Contrast")
	prefs.set_pref(HFOverlayColors.HOVER, Color.MAGENTA)
	HFOverlayColors.apply_prefs(prefs)
	assert_eq(HFOverlayColors.get_color(key), HFOverlayColors.DEFAULTS[key], "picked colours win")


func test_less_transparency_draws_fills_more_opaque():
	var key := HFOverlayColors.ADDITIVE_BRUSH
	var usual := HFOverlayColors.get_color(key).a
	HFOverlayColors.less_transparency = true
	assert_gt(HFOverlayColors.get_color(key).a, usual, "a see-through fill is more opaque")
	assert_eq(HFOverlayColors.get_color(HFOverlayColors.VERTEX_HANDLE).a, 1.0, "opaque stays")


func test_a_refusal_is_read_out_at_once_and_information_when_free():
	var toasts := HFToast.new()
	add_child_autofree(toasts)
	toasts.show_toast("Select a brush first", 1)
	toasts.show_toast("Created 3 copies", 0)
	var refusal: Label = toasts.get_child(0).get_child(0)
	var info: Label = toasts.get_child(1).get_child(0)
	assert_eq(refusal.accessibility_live, DisplayServer.LIVE_ASSERTIVE)
	assert_eq(info.accessibility_live, DisplayServer.LIVE_POLITE)


func test_what_draws_itself_has_a_name():
	var radial := HFRadialMenu.new()
	autofree(radial)
	assert_eq(radial.accessibility_name, "Radial menu")
	for segment in HFRadialMenu.SEGMENTS:
		assert_string_contains(radial.accessibility_description, segment["label"])
	var lamp := HFStatusLamp.new()
	autofree(lamp)
	lamp.severity = HFStatusBoard.Severity.PROBLEM
	assert_eq(lamp.accessibility_name, "Status: Problem")


## Every interactive control the dock and the Console build has a name, so the
## list stays complete as controls are added.
func test_every_control_in_the_dock_and_the_console_has_a_name():
	var dock = DockScene.instantiate()
	add_child_autofree(dock)
	await get_tree().process_frame
	await get_tree().process_frame
	var nameless: Array = HFAccessibility.unnamed(dock).map(
		func(c): return str(dock.get_path_to(c))
	)
	assert_eq(nameless, [], "dock controls with no name")
	var console := HFConsolePanel.new()
	add_child_autofree(console)
	await get_tree().process_frame
	await get_tree().process_frame
	nameless = HFAccessibility.unnamed(console).map(func(c): return str(console.get_path_to(c)))
	assert_eq(nameless, [], "Console controls with no name")


## Every dock button can be reached with Tab, and a click hands the keys back.
func test_every_dock_button_is_in_reach_of_tab_and_a_click_gives_the_keys_back():
	var dock = DockScene.instantiate()
	add_child_autofree(dock)
	await get_tree().process_frame
	await get_tree().process_frame
	var out_of_reach: Array = []
	for control in HFAccessibility._interactive(dock):
		if control is BaseButton and control.focus_mode == Control.FOCUS_NONE:
			out_of_reach.append(str(dock.get_path_to(control)))
	assert_eq(out_of_reach, [], "dock buttons Tab cannot reach")
	var button: BaseButton = dock._command_palette_btn
	button.grab_focus()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	button.gui_input.emit(release)
	await get_tree().process_frame
	assert_false(button.has_focus(), "a click leaves the keys for the viewport")
