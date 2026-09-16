@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The Console's Controls tab against the level and the dock it claims to be a
## view of.
##
## `HFConsoleControls` says it is "every HammerForge switch on one screen", and
## it deliberately writes through the dock's own control where the dock has one
## so the two surfaces cannot disagree. Both halves of that are checkable: every
## row has to name a setting that exists, and every row that writes through a
## dock control has to be able to carry the values the level property allows.

const ControlsType = preload("res://addons/hammerforge/ui/hf_console_controls.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")


func id() -> String:
	return "console-controls"


func summary() -> String:
	return "whether every switch on the Console's Controls tab reaches the setting it names"


func run() -> void:
	await _rows_reach_their_setting()
	await _numbers_carry_the_level_range()


func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	await frame()
	return dock


func _rows_reach_their_setting() -> void:
	var root: Node3D = await fresh_root("ConsoleLevel")
	var dock = await _dock(root)
	var controls = ControlsType.new()
	_tree.get_root().add_child(controls)
	await frame()
	controls.set_dock(dock)
	await frame()

	var missing_property: Array = []
	var missing_dock_control: Array = []
	var disabled_rows: Array = []
	var specs: Array = []
	for group in ControlsType.GROUPS:
		for spec in group["rows"]:
			specs.append(spec)
	for spec in ControlsType.NUMBERS:
		specs.append(spec)
	note("rows on the Controls tab", specs.size())

	for spec in specs:
		var key: String = str(spec.get("key", ""))
		var dock_name: String = str(spec.get("dock", ""))
		var label: String = str(spec["label"])
		if key != "" and root.get(key) == null:
			missing_property.append("%s -> LevelRoot.%s" % [label, key])
		if dock_name != "" and dock.get(dock_name) == null:
			missing_dock_control.append("%s -> dock.%s" % [label, dock_name])

	for entry in controls._rows:
		var control = entry["control"]
		var label: String = str(entry["spec"]["label"])
		var off: bool = false
		if entry["kind"] == "toggle":
			off = bool(control.disabled)
		else:
			off = not bool(control.editable)
		if off:
			disabled_rows.append(label)
	note("rows naming a LevelRoot property that does not exist", missing_property.size())
	note("rows naming a dock control that does not exist", missing_dock_control.size())
	note("rows still disabled with a level open", disabled_rows)

	if not missing_property.is_empty():
		flag(
			"a Controls row is bound to a LevelRoot property that is not there",
			(
				(
					"`_read()` returns null for a key LevelRoot does not have, so the switch is"
					+ " disabled for good and the reader is told the setting does not apply"
					+ " rather than that it does not exist: %s"
				)
				% str(missing_property)
			)
		)
	if not missing_dock_control.is_empty():
		flag(
			"a Controls row writes through a dock control that is not there",
			(
				(
					"`_write()` prefers the dock's own control so the dock's handler runs;"
					+ " where the named control is missing the write silently falls through to"
					+ " the raw property and the dock's side effect never happens: %s"
				)
				% str(missing_dock_control)
			)
		)
	if not disabled_rows.is_empty():
		flag(
			"a switch on the Controls tab stays disabled with a level open",
			(
				(
					"the tab disables a row whose setting has 'nowhere to live'; with a"
					+ " LevelRoot and the dock both present these still read as not"
					+ " applicable: %s"
				)
				% str(disabled_rows)
			)
		)
	controls.queue_free()
	dock.queue_free()
	await frame()


func _numbers_carry_the_level_range() -> void:
	var root: Node3D = await fresh_root("ConsoleNumbers")
	var dock = await _dock(root)
	var controls = ControlsType.new()
	_tree.get_root().add_child(controls)
	await frame()
	controls.set_dock(dock)
	await frame()

	var narrower: Array = []
	for entry in controls._rows:
		if entry["kind"] != "number":
			continue
		var spec: Dictionary = entry["spec"]
		var console_spin: SpinBox = entry["control"] as SpinBox
		var dock_spin = dock.get(str(spec.get("dock", "")))
		note(
			"%s: Console spin range" % str(spec["label"]),
			[console_spin.min_value, console_spin.max_value]
		)
		if dock_spin is SpinBox:
			note(
				"%s: dock spin range" % str(spec["label"]),
				[dock_spin.min_value, dock_spin.max_value]
			)
			if (
				not is_equal_approx(console_spin.min_value, dock_spin.min_value)
				or not is_equal_approx(console_spin.max_value, dock_spin.max_value)
			):
				(
					narrower
					. append(
						(
							"%s: Console %s..%s, dock %s..%s"
							% [
								str(spec["label"]),
								console_spin.min_value,
								console_spin.max_value,
								dock_spin.min_value,
								dock_spin.max_value,
							]
						)
					)
				)
		# Turn the Console spin to each end and read back what the level holds.
		for end in [console_spin.min_value, console_spin.max_value]:
			console_spin.value = end
			console_spin.value_changed.emit(console_spin.value)
			await frame()
			var held = root.get(str(spec.get("key", "")))
			note(
				"%s: Console set to %s" % [str(spec["label"]), end],
				(
					"level holds %s%s"
					% [held, "" if is_equal_approx(float(held), end) else "   <-- different"]
				)
			)
	if not narrower.is_empty():
		flag(
			"the Console and the dock offer different ranges for the same setting",
			(
				(
					"the Console writes through the dock's control, so the narrower of the"
					+ " two silently wins and the wider one goes on showing a number the"
					+ " setting never received: %s"
				)
				% str(narrower)
			)
		)
	controls.queue_free()
	dock.queue_free()
	await frame()
