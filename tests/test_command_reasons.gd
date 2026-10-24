extends GutTest

## Why a command is greyed out, said where it is greyed out (#1868).
##
## A disabled button cannot be pressed, so the toast a press would have shown
## never came, and the palette's tooltip said what a command does and never why
## it could not run. `HFCommandAvailability.reason()` says why, and the palette's
## tooltip and the selection guard's toast both read it.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFCommandAvailability = preload("res://addons/hammerforge/hf_command_availability.gd")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const PaletteScript = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


func _palette():
	return rig.plugin._hotkey_palette


## The palette opened, so it is brought up to date with what is selected.
func _open_palette() -> void:
	if not _palette().visible:
		rig.plugin._on_toggle_hotkey_palette()


func _close_palette() -> void:
	if _palette().visible:
		rig.plugin._on_toggle_hotkey_palette()
	await rig.frame()


func _entry(action: String) -> Dictionary:
	for entry in _palette()._entries:
		if entry["action"] == action:
			return entry
	return {}


func _entity(level: Node) -> Node3D:
	var entity := DraftEntityScript.new()
	entity.name = "Lamp"
	level.entities_node.add_child(entity)
	entity.owner = level.owner if level.owner else level
	return entity


func test_hollow_with_nothing_selected_says_a_brush_must_be_selected():
	var level = await rig.make_level()
	rig.box(level, "a", Vector3.ZERO)
	rig.select([])
	_open_palette()
	var entry := _entry("hollow")
	assert_false(entry.is_empty(), "Hollow is in the palette")
	if entry.is_empty():
		return
	var button: Button = entry["button"]
	assert_true(button.disabled, "greyed out")
	assert_true(
		button.tooltip_text.ends_with("\n" + HFCommandAvailability.NO_BRUSH),
		"and its tooltip says why: %s" % button.tooltip_text
	)
	await _close_palette()
	rig.clear_toasts()
	rig.plugin._hotkey_palette.action_invoked.emit("hollow")
	assert_has(rig.toasts(), HFCommandAvailability.NO_BRUSH, "run anyway, it says the same")
	await rig.leave_level(level)


## The palette's reason and the toast from pressing the key are one sentence.
func test_the_tooltip_and_the_key_s_toast_say_the_same_thing():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	var lamp := _entity(level)
	rig.select([box, lamp])
	_open_palette()
	var reason: String = _palette().unavailable_reason("hollow")
	assert_eq(reason, "Hollow works on brushes only")
	await _close_palette()
	rig.clear_toasts()
	rig.forward(PluginRig.key_for("hollow"))
	assert_has(rig.toasts(), reason, "the key's toast")
	rig.clear_toasts()
	rig.plugin._hotkey_palette.action_invoked.emit("hollow")
	assert_has(rig.toasts(), reason, "and the palette's own, run anyway")
	await rig.leave_level(level)


## In a few states, every command the palette greys out says why on its
## tooltip, and every one it leaves on says nothing extra.
func test_every_greyed_out_command_says_why():
	var states := {
		"no level": {"has_root": false, "brush_count": 0, "entity_count": 0, "tool_refusals": {}},
		"nothing selected": {"has_root": true},
		"a mixed selection": {"has_root": true, "mixed_selection": true, "brush_count": 1},
		"paint mode": {"has_root": true, "paint_mode": true},
		"vertex mode": {"has_root": true, "vertex_mode": true, "brush_count": 1},
	}
	var palette = PaletteScript.new()
	add_child_autofree(palette)
	palette.populate(rig.plugin._keymap)
	for name in states:
		palette.update_state(states[name])
		var silent: Array = []
		for entry in palette._entries:
			var button: Button = entry["button"]
			var said := str(button.tooltip_text).trim_prefix(str(entry["tooltip"]))
			if button.disabled and said.strip_edges() == "":
				silent.append(entry["action"])
			if not button.disabled and said != "":
				silent.append("%s (on, with a reason)" % entry["action"])
		assert_eq(silent, [], "%s: greyed out with no reason" % name)
	palette.update_state(states["no level"])
	assert_eq(
		palette.unavailable_reason("hollow"),
		HFCommandAvailability.NO_LEVEL,
		"a command that needs a level says so first"
	)
	palette.update_state(states["paint mode"])
	assert_eq(palette.unavailable_reason("paint_bucket"), "")
	palette.update_state(states["nothing selected"])
	assert_eq(palette.unavailable_reason("paint_bucket"), HFCommandAvailability.NOT_PAINTING)
	palette.update_state(states["a mixed selection"])
	assert_eq(palette.unavailable_reason("delete"), HFCommandAvailability.MIXED)


## A tool that cannot start says the reason its start would give.
func test_a_tool_that_cannot_start_says_why():
	var refusals: Dictionary = rig.plugin._tool_registry.refusals(null)
	assert_true(refusals.has("tool_clip"), "no tool starts without a level: %s" % [refusals])
	var state := {"has_root": false, "tool_refusals": refusals}
	for action in refusals:
		assert_eq(HFCommandAvailability.reason(action, state), refusals[action], action)
	var level = await rig.make_level()
	assert_eq(rig.plugin._tool_registry.refusals(level), {}, "and every one starts with one")
	await rig.leave_level(level)


## The reason line under the list names the greyed out command the mouse is on.
func test_the_reason_line_names_the_command_under_the_mouse():
	var level = await rig.make_level()
	rig.select([])
	_open_palette()
	var entry := _entry("hollow")
	_palette()._on_entry_hovered("hollow", true)
	var line: Label = _palette()._reason_label
	assert_true(line.visible, "shown")
	assert_eq(line.text, "%s: %s" % [entry["label"], HFCommandAvailability.NO_BRUSH])
	_palette()._on_entry_hovered("hollow", false)
	assert_false(line.visible, "and gone when the mouse leaves")
	await _close_palette()
	await rig.leave_level(level)


## Repeat waits for the first brush drawn, and says so.
func test_the_toolbar_s_repeat_button_says_why_it_waits():
	var toolbar = rig.plugin._context_toolbar
	var button := Button.new()
	button.set_meta("hf_tooltip_source", "Repeat the last brush")
	autofree(button)
	toolbar._update_repeat_button(button, {"repeat_label": ""})
	assert_true(button.disabled)
	assert_true(button.tooltip_text.ends_with(HFCommandAvailability.NOTHING_DRAWN))
	toolbar._update_repeat_button(button, {"repeat_label": "Box 2 x 2 x 2"})
	assert_false(button.disabled)
	assert_eq(button.tooltip_text, "Repeat the last brush", "nothing added once it can run")
