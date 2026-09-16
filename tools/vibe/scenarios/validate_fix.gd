@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the Validate + Fix button tells the mapper against what it did.
##
## `validate_level(true)` repairs what it can and returns both halves of the
## answer -- the issues found and the number repaired. The dock's handler is
## what turns those into a status line and a log, and that is the surface a
## mapper reads after pressing the button, so what it says has to match the
## level they are left with.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const ManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")


func id() -> String:
	return "validate-fix"


func summary() -> String:
	return "what Validate + Fix reports against what it repaired and what is left"


func run() -> void:
	await _what_the_button_says()


func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	await frame()
	return dock


func _what_the_button_says() -> void:
	var root: Node3D = await fresh_root("ValidateLevel")
	var dock = await _dock(root)

	# Three brushes the validator has a repair for: two zero-size and one with
	# a size that is not a number. All three are fixed in one pass.
	for i in range(3):
		var brush = box(root, Vector3(32, 32, 32), Vector3(float(i) * 64.0, 0, 0))
		if brush:
			brush.size = Vector3(0, 0, 0) if i < 2 else Vector3(NAN, 32, 32)
	await frame()

	var before: Dictionary = root.validate_level(false)
	note("issues before the fix", before.get("issues", []).size())
	for issue in before.get("issues", []):
		note("  before", str(issue))

	# What the validator itself reports when asked to fix.
	var direct: Dictionary = root.validate_level(true)
	note("validate_level(true) reported fixed", direct.get("fixed", "<no key>"))
	note("validate_level(true) reported issues", direct.get("issues", []).size())

	# Now the same situation through the dock's button, which is the path a
	# mapper takes.
	for i in range(3):
		var brush2 = box(root, Vector3(32, 32, 32), Vector3(float(i) * 64.0, 128.0, 0))
		if brush2:
			brush2.size = Vector3(0, 0, 0)
	await frame()
	var before_button: Dictionary = root.validate_level(false)
	note("issues before pressing Validate + Fix", before_button.get("issues", []).size())
	ManageHandler.run_validation(dock, true)
	await frame()
	var after_button: Dictionary = root.validate_level(false)
	note("issues left after Validate + Fix", after_button.get("issues", []).size())
	note(
		"what the status line says",
		str(dock.get("status_label").text) if dock.get("status_label") else "<no status label>"
	)

	var reported_count: int = before_button.get("issues", []).size()
	var remaining: int = after_button.get("issues", []).size()
	note(
		"the handler reports the issue list it read before the repair",
		"%d reported, %d actually remain" % [reported_count, remaining]
	)
	if reported_count > remaining:
		known(
			569,
			"Validate + Fix reports the issues it has just repaired",
			(
				(
					"`run_validation()` keeps the issue list from its first pass and logs that"
					+ " one after the fix, so the mapper is shown %d problems when %d remain."
					+ " It also discards the `fixed` count `validate_level(true)` returns and"
					+ " re-derives it by differencing two further validation passes, which is"
					+ " three full walks of every brush and face per press"
				)
				% [reported_count, remaining]
			)
		)
	dock.queue_free()
	await frame()
