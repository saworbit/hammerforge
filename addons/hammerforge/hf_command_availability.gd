@tool
extends RefCounted
## Why a command cannot run now, in one short sentence, or "" when it can (#1868).
##
## The palette greys out a command it cannot run, and a disabled button cannot
## be pressed, so the toast a press would have shown never came. Someone new saw
## Hollow greyed out and had no way to learn that it wants a brush selected. The
## reasons were already written, in the selection guard's refusal toasts, in the
## registry's `needs_level`, in a tool's `get_poll_fail_reason()` and in the
## palette's own rules for paint and vertex mode. They are written here once:
## the palette's tooltip and the guard's toast both read them, so the two say
## the same thing.
##
## `state` is `HFPluginCommands.build_command_state()`: the tool and mode, what
## is selected, whether there is a level, and why each tool cannot start.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
@warning_ignore_restore("shadowed_global_identifier")

const NO_LEVEL := "Needs a HammerForge level in the scene"
const MIXED := "Edit HammerForge and Godot nodes separately"
const NOTHING := "Select a HammerForge object first"
const NO_BRUSH := "Select a brush first"
const NO_FACE := "Pick a face first"
const NO_FACE_OR_BRUSH := "Pick a face or select a brush first"
const NOT_PAINTING := "Turn Paint mode on first"
const NOT_VERTEX := "Turn on vertex editing first"
const IN_VERTEX := "Not while editing vertices: the key snaps the vertices instead"
const IN_SELECT := "Not with the Select tool"
const BUSY := "Finish what the viewport is doing first"
const NOTHING_TO_REPEAT := "Run a command first"
const NO_FACES_PICKED := "Pick the faces to sweep in Face Select first"
const NOTHING_IN_RUN := "Run commands on a selection first"
const NO_GROUP_SELECTED := "Select a group first"
const NO_GROUP_OPEN := "Open a group first"
const NO_TARGET_GROUP := "Pick a group in the Groups list, or open one"
const NOTHING_DRAWN := "Draw a brush first"
const BAKING := "Wait for the bake to finish"


## Why `action` cannot run in `state`, or "" when it can.
static func reason(action: String, state: Dictionary) -> String:
	var refusals: Dictionary = state.get("tool_refusals", {})
	if refusals.has(action):
		return str(refusals[action])
	if HFCommandRegistry.needs_level(action) and not bool(state.get("has_root", true)):
		return NO_LEVEL
	var mode: Variant = _mode_rule(action, state)
	if mode != null:
		return mode
	return selection_reason(HFCommandRegistry.selection(action), counts_of(state))


## What `selection_reason()` reads of `state`.
static func counts_of(state: Dictionary) -> Dictionary:
	return {
		"mixed": bool(state.get("mixed_selection", false)),
		"brushes": int(state.get("brush_count", 0)),
		"entities": int(state.get("entity_count", 0)),
		"faces": int(state.get("face_count", 0)),
	}


## The refusal for a selection that does not meet `requirement`, a registry
## `selection` rule, or "". `counts` is `{mixed, brushes, entities, faces}`: the
## HammerForge brushes and entities selected, whether Godot nodes are selected
## with them, and the faces picked. The guard's toasts are these sentences.
static func selection_reason(requirement: Dictionary, counts: Dictionary) -> String:
	if requirement.is_empty():
		return ""
	if bool(counts.get("mixed", false)):
		return MIXED
	if bool(requirement.get("mixed_only", false)):
		return ""
	var minimum := int(requirement.get("minimum", 1))
	if minimum == 0:
		return ""
	if bool(requirement.get("allow_faces", false)) and int(counts.get("faces", 0)) > 0:
		return ""
	var brushes := int(counts.get("brushes", 0))
	var picked := brushes + int(counts.get("entities", 0))
	var brushes_only := bool(requirement.get("brushes_only", false))
	if picked == 0:
		return NO_BRUSH if brushes_only else NOTHING
	var label := str(requirement.get("label", "Action"))
	if brushes_only and brushes < picked:
		return "%s works on brushes only" % label
	if picked < minimum:
		return "%s needs at least %d selected" % [label, minimum]
	return ""


## The rules about the mode the editor is in rather than the selection, which
## the palette kept to itself: a reason, "" for a command these rules let run
## whatever is selected, or null to leave it to the selection rule.
static func _mode_rule(action: String, state: Dictionary) -> Variant:
	var mixed := bool(state.get("mixed_selection", false))
	var faces := int(state.get("face_count", 0))
	var brushes := int(state.get("brush_count", 0))
	var vertex := bool(state.get("vertex_mode", false))
	# Repeat waits for something to repeat (#1694).
	if action == "repeat_last_command":
		return "" if str(state.get("repeat_command", "")) != "" else NOTHING_TO_REPEAT
	# Sweep takes picked faces (#1714).
	if action == "sweep_faces":
		return "" if faces > 0 else NO_FACES_PICKED
	# Repeat Run and Clear Run wait for a run (#1735).
	if action == "repeat_run" or action == "clear_run":
		return "" if str(state.get("run_text", "")) != "" else NOTHING_IN_RUN
	# Opening takes a group, and the rest an open one (#1723).
	var open := str(state.get("open_group", "")) != ""
	match action:
		"open_group":
			return "" if str(state.get("selected_group", "")) != "" else NO_GROUP_SELECTED
		"close_group":
			if not open:
				return NO_GROUP_OPEN
		"add_to_group", "remove_from_group":
			if str(state.get("target_group", "")) == "":
				return NO_TARGET_GROUP
		"rename_group":
			if not open and str(state.get("selected_group", "")) == "":
				return NO_GROUP_SELECTED
	# A favourite goes on the picked faces, or else the selected brushes.
	if action.begins_with("apply_favorite_"):
		if mixed:
			return MIXED
		return "" if brushes > 0 or faces > 0 else NO_FACE_OR_BRUSH
	match action:
		# In vertex mode the chord snaps the selected vertices instead.
		"snap_to_grid":
			if vertex:
				return IN_VERTEX
		# In vertex mode Offset moves the picked vertices.
		"offset_selection":
			if vertex:
				return MIXED if mixed else ""
		"paint_bucket", "paint_erase", "paint_ramp", "paint_line", "paint_fill", "paint_blend":
			return "" if bool(state.get("paint_mode", false)) else NOT_PAINTING
		"vertex_edge_mode", "vertex_merge", "vertex_split_edge", "vertex_snap_to_grid":
			if not vertex:
				return NOT_VERTEX
			return MIXED if mixed else ""
		"axis_x", "axis_y", "axis_z":
			return IN_SELECT if int(state.get("tool", 0)) == 1 else ""
		# Apply Picked Look, Wrap, a Trim Run (#1414) and Hidden faces (#1719)
		# work on the picked faces alone.
		"apply_picked_look", "uv_wrap", "run_trim_along_faces", "make_faces_hidden", "make_faces_normal":
			if mixed:
				return MIXED
			return "" if faces > 0 else NO_FACE
		"hide_faces_against_solids":
			if mixed:
				return MIXED
			return "" if brushes > 0 or faces > 0 else NO_FACE_OR_BRUSH
		"context_menu", "radial_menu":
			var idle: bool = (
				int(state.get("input_mode", 0)) == 0
				and not bool(state.get("has_active_external_tool", false))
			)
			return "" if idle else BUSY
	return null
