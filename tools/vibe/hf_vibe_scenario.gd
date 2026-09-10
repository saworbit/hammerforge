@tool
extends RefCounted

## Base class for one exploratory scenario.
##
## A scenario drives a real `LevelRoot` through some slice of the editor and
## records what it saw. It does not assert. The two things it can say are
## `note()` -- this is what happened, for the log -- and `flag()` -- this looks
## wrong, a human should judge it. The runner exits non-zero when anything was
## flagged, so a scheduled run is still a signal, but the judgement stays with
## the reader.
##
## Anything already reported upstream is flagged through `known()` instead, with
## the issue number. That keeps a scenario honest about a defect it still
## reproduces without the run going red for something already on the board.

const HFVibe = preload("res://tools/vibe/hf_vibe.gd")

## Freeform observations, in order.
var notes: Array[String] = []

## Things that look wrong and are not yet reported.
var flags: Array[String] = []

## Things that look wrong and already have an issue. `[issue number, text]`.
var knowns: Array = []

var _tree: SceneTree = null


func _init(tree: SceneTree = null) -> void:
	_tree = tree


## Short identifier, used to select the scenario on the command line.
func id() -> String:
	return "unnamed"


## One line saying what this scenario covers.
func summary() -> String:
	return ""


## Do the work. Override this. `await` freely -- the runner awaits the call.
func run() -> void:
	pass


## Record what happened. Shows up in the log, never fails a run.
func note(label: String, value: Variant = null) -> void:
	var line := label if value == null else "%s: %s" % [label, value]
	notes.append(line)
	print("    %s" % line)


## Record something that looks wrong and has no issue yet. Fails the run.
func flag(label: String, detail: Variant = null) -> void:
	var line := label if detail == null else "%s -- %s" % [label, detail]
	flags.append(line)
	print("  FLAG  %s" % line)


## Record a defect that is already reported. Does not fail the run.
##
## Kept deliberately, rather than deleted once filed: a scenario that stops
## exercising a known defect stops noticing when the fix lands, and stops
## noticing when it comes back.
func known(issue: int, label: String, detail: Variant = null) -> void:
	var line := label if detail == null else "%s -- %s" % [label, detail]
	knowns.append([issue, line])
	print("  KNOWN #%d  %s" % [issue, line])


## Compare two `HFVibe.describe_level()` snapshots and flag every key that moved.
##
## `context` names the round trip, so a report says which one lost the data.
## `known_keys` maps a key to the issue already covering it, so a defect that is
## reported but unmerged is still exercised without turning the run red.
func diff_levels(
	before: Dictionary, after: Dictionary, context: String, known_keys: Dictionary = {}
) -> void:
	for k in before.keys():
		if not after.has(k):
			flag("%s dropped '%s' entirely" % [context, k])
			continue
		if HFVibe.canonical(before[k]) != HFVibe.canonical(after[k]):
			if known_keys.has(k):
				known(int(known_keys[k]), "%s changed '%s'" % [context, k])
			else:
				flag("%s changed '%s'" % [context, k])
			print("          before: %s" % HFVibe.canonical(before[k]).substr(0, 600))
			print("          after:  %s" % HFVibe.canonical(after[k]).substr(0, 600))


## A live root plus the frame its `_ready()` needs. Every scenario starts here.
func fresh_root(node_name: String = "Level") -> Node3D:
	var root := HFVibe.make_root(_tree, node_name)
	await _tree.process_frame
	return root


## One frame, for the callers that need to let a deferred call land.
func frame() -> void:
	await _tree.process_frame


## Shorthand for the brush most scenarios start from.
func box(root: Node3D, size: Vector3, centre: Vector3 = Vector3.ZERO) -> Node:
	return root.create_brush_from_info({"shape": 0, "size": size, "center": centre})
