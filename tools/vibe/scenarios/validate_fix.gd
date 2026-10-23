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

	# What the status line says is left, against what a fresh pass finds. #569 had
	# it list what the fix had just repaired; it reads the second pass now, so
	# the two agree, and a status line that disagrees has gone back to that.
	var remaining: int = after_button.get("issues", []).size()
	var status := str(dock.get("status_label").text) if dock.get("status_label") else ""
	var says := -1
	if status.contains("no issues"):
		says = 0
	else:
		var found := RegEx.create_from_string("(\\d+) remaining").search(status)
		if found:
			says = int(found.get_string(1))
	note("the status line says remaining / a fresh pass finds", "%d / %d" % [says, remaining])
	if says != remaining:
		flag(
			"Validate + Fix says a different number is left than a fresh pass finds",
			(
				"the status line says %d remain (%s) and validate_level(false) finds %d"
				% [says, status, remaining]
			)
		)
	dock.queue_free()
	await frame()
