@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Validate complains about what the plugin's own tools just built.
##
## A mapper who hollows a box, carves a doorway or places a staircase from the
## Structure section and then presses Validate should see nothing, because
## nothing they did was wrong. A warning there is a check crying wolf, and the
## README's rule for those is that a check that cries wolf is worse than none:
## the mapper learns to ignore the panel. Each case builds one thing on a floor
## with the plugin's own operation, then reads `validate_level()` and
## `check_bake_issues()` and records every issue.

const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")


func id() -> String:
	return "validate-own-output"


func summary() -> String:
	return "what Validate says about a hollow, a carve, a clip, a merge and each generator at its defaults"


func run() -> void:
	await _case("hollow a box", _hollow_box)
	await _case("hollow a box turned 30 degrees", _hollow_turned)
	await _case("hollow a 16-sided cylinder", _hollow_cylinder)
	await _case("carve a doorway through a wall", _carve_doorway)
	await _case("clip a box on a slant", _clip_slant)
	await _case("merge two boxes into one", _merge_two)
	for type in HFGeneratorSystem.known_types():
		var t := str(type)
		await _case(
			"%s at its defaults" % t,
			func(root: Node3D) -> void:
				root.create_generator(
					t, HFGeneratorSystem.default_settings(t), Transform3D.IDENTITY
				)
		)


func _case(label: String, build: Callable) -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	await build.call(root)
	await frame()
	var report: Dictionary = root.validate_level(false)
	var issues: Array = report.get("issues", [])
	var bake_issues: Array = root.validation_system.check_bake_issues()
	var texts: Array = []
	for i in issues:
		texts.append(str(i))
	var bake_texts: Array = []
	for i in bake_issues:
		bake_texts.append(str(i.get("message", i)) if i is Dictionary else str(i))
	note(label, "%d validate issue(s), %d bake issue(s)" % [issues.size(), bake_issues.size()])
	for t in texts:
		note("    validate", t)
	for t in bake_texts:
		note("    bake", t)
	if not texts.is_empty() or not bake_texts.is_empty():
		var detail := "validate: %s; bake issues: %s" % [texts, bake_texts]
		flag("Validate reports the plugin's own %s" % label, detail)
	await drop_root(root)


func _id(b) -> String:
	return str(b.get_meta("brush_id", ""))


func _hollow_box(root: Node3D) -> void:
	var b = box(root, Vector3(4, 3, 4), Vector3(0, 1.5, 0))
	root.hollow_brush_by_id(_id(b), 0.2)


func _hollow_turned(root: Node3D) -> void:
	var b = box(root, Vector3(4, 3, 4), Vector3(0, 1.5, 0))
	root.rotate_managed_nodes([_id(b)], [], 1, 30.0, Vector3(0, 1.5, 0))
	root.hollow_brush_by_id(_id(b), 0.2)


func _hollow_cylinder(root: Node3D) -> void:
	var b = root.create_brush_from_info(
		{
			"shape": root.BrushShape.CYLINDER,
			"size": Vector3(4, 3, 4),
			"center": Vector3(0, 1.5, 0),
			"sides": 16
		}
	)
	root.hollow_brush_by_id(_id(b), 0.2)


func _carve_doorway(root: Node3D) -> void:
	box(root, Vector3(6, 3, 0.3), Vector3(0, 1.5, 0))
	var cutter = box(root, Vector3(1.0, 2.2, 0.6), Vector3(0, 1.1, 0))
	root.carve_with_brush(_id(cutter))


func _clip_slant(root: Node3D) -> void:
	var b = box(root, Vector3(4, 3, 4), Vector3(0, 1.5, 0))
	root.clip_brush_by_plane(_id(b), Plane(Vector3(1, 1, 0).normalized(), 1.0))


func _merge_two(root: Node3D) -> void:
	var a = box(root, Vector3(2, 2, 2), Vector3(-1, 1, 0))
	var b = box(root, Vector3(2, 2, 2), Vector3(1, 1, 0))
	root.merge_brushes_by_ids([_id(a), _id(b)])
