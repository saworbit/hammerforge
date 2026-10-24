@tool
class_name HFCommandRegistry
extends RefCounted
## Every command a HammerForge surface can run, described in one place.
##
## The palette, the rebind dialog, the context toolbar, the viewport and radial
## menus and the keys all name a command by id. What each one is called, where it
## is grouped, whether it needs a level and what it needs selected lived in four
## lists in three files, and a command added to one could be missed in another.
## `HFKeymap.get_action_label()` and `get_category()`,
## `HFPluginCommands.requires_existing_root()` and
## `HFPluginSelectionState.managed_surface_action_requirement()` read this table
## now. What a command does stays in `HFPluginCommands.execute()`, one arm per id,
## and an id this table does not know runs nothing there.
##
## Each entry:
##
## - `id`: what every surface sends. Never renamed: a user's keymap file is keyed
##   by it, and `HFKeymap` drops a key it does not know.
## - `label`: what the palette and the rebind dialog call it.
## - `help`: one sentence on what the command does. The palette's tooltip and
##   `docs/commands.md` both read it, so it is written once (#1658).
## - `category`: the group they list it under.
## - `aliases`: other words for the command, lower case, which the palette finds
##   it by: "shell" for Hollow (#1695). A word names one command, and never
##   another command's label. A project adds its own in `HFCommandAliases`' file.
## - `needs_level`: the palette refuses it when there is no level, rather than
##   make one as a side effect.
## - `selection`: `{}`, or what the surface guard asks of the selection
##   (`HFPluginSelectionState.managed_action_surface_allowed()`): `brushes_only`,
##   `minimum`, `label` for its toasts, `allow_faces`, `mixed_only`. The keyboard
##   router takes `brushes_only`, `minimum` and `label` from here too, so a
##   refusal reads the same from a key as from the palette (#1298).
## - `palette`: true lists a command that has no key in the hotkey palette, which
##   otherwise lists the keymap's actions. Wrap Texture has no default key (#1428),
##   and nor do the UV edits and Apply Rotation and Scale the dock's buttons run,
##   so the palette is how they are found by name (#1620). Apply to Brush and
##   Justify Fit are listed so "texture" and "fit texture" find them (#1695).
## - `repeat`: true for a command Repeat Last Command may run again: one that
##   changes the level or the selection (#1694). Toggles, views, panels and Repeat
##   itself are left out, so Repeat never means toggle back, and so are Select All
##   and Deselect All, which would push the edit before them out of reach.
## - `guard_only`: an id the guard knows that `execute()` never runs. The material
##   quick apply asks the guard about `apply_context_material` and then applies the
##   material itself.
## - `bridge`: present when an agent may run the command over the MCP bridge
##   (`hf_run_command`). `form` names the parameter form in
##   `mcp/hf_mcp_commands.gd`, which takes explicit brush ids and parameters and
##   never reads the selection or opens a dialog. `description` is what the agent
##   reads. `targets` is how many of `brush_ids` and `entities` together it takes
##   (`max` -1 for no cap) and whether entities count. `params` are fields in
##   `HFGeneratorSchema`'s shape (`key`, `type`, `min`, `max`, `step`, `default`,
##   `description`, `required`), with the types in `PARAM_TYPES`. `undo` is
##   `scope` for a command that only moves the brushes it names, so its step
##   records those, and `level` for anything else.
##
## No comments go between the entries: gdformat moves a comment that sits between
## wrapped dictionary entries into one of them.

## The parameter types a bridge entry may use. `axis` is "x", "y" or "z"; `face`
## is a face selector as `hf_extrude_face` takes one; `cell` is a floor paint
## cell, `[x, z]`; `layer` is a paint layer's index from 0 or its name, resolved
## by the form against the level; `object` is checked by the form itself.
const PARAM_TYPES := [
	"float", "int", "bool", "enum", "axis", "vec3", "face", "string", "object", "cell", "layer"
]

const COMMANDS := [
	{
		"id": "toggle_operation",
		"label": "Toggle Add / Cut",
		"help": "Switch the next brush you draw between Add and Cut.",
		"aliases": ["subtract", "negative brush", "cut brush"],
		"category": "Workflow",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "toggle_paint_mode",
		"label": "Toggle Paint Mode",
		"help": "Turn floor Paint mode on or off.",
		"category": "Workflow",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "quick_play",
		"label": "Quick Play",
		"help": "Bake the level and run it to test.",
		"aliases": ["playtest", "run level", "test map"],
		"category": "Workflow",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "validate_level",
		"label": "Validate Level",
		"help": "Check the level for problems and list them.",
		"aliases": ["check level", "lint", "problems"],
		"category": "Workflow",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "tool_draw",
		"label": "Draw",
		"help": "Switch to Draw, which makes brushes with two clicks.",
		"aliases": ["new brush", "create brush", "block out"],
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_select",
		"label": "Select",
		"help": "Switch to Select, which picks brushes and entities.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "extrude_up",
		"label": "Extrude Up",
		"help": "Switch to Extrude Up: drag a face to grow a brush out of it.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude_up",
		"label": "Extrude Up",
		"help": "Switch to Extrude Up: drag a face to grow a brush out of it.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude",
		"label": "Extrude Up (alt)",
		"help": "Switch to Extrude Up, outside Paint and Vertex modes.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "extrude_down",
		"label": "Extrude Down",
		"help": "Switch to Extrude Down: drag a face to push a cut into it.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude_down",
		"label": "Extrude Down",
		"help": "Switch to Extrude Down: drag a face to push a cut into it.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude_down_alt",
		"label": "Extrude Down (alt)",
		"help": "Switch to Extrude Down, outside Paint and Vertex modes.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_clip",
		"label": "Clip Tool",
		"help": "Start the Clip tool, which cuts the selected brushes along a plane you place.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_polygon",
		"label": "Polygon Tool",
		"help": "Start the Polygon tool: click an outline on the ground, then drag its height.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_path",
		"label": "Path Tool",
		"help":
		"Start the Path tool, which builds a corridor of brushes along the points you click.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_decal",
		"label": "Decal Tool",
		"help": "Start the Decal tool, which places a decal on the surface you click.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "repeat_brush",
		"label": "Repeat Last Brush",
		"help": "Arm a stamp of the brush the last Draw made; each click places one.",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "repeat_last_command",
		"label": "Repeat Last Command",
		"help": "Run the last command again on the current selection, with the same settings.",
		"aliases": ["again", "do again"],
		"category": "Workflow",
		"needs_level": true,
		"selection": {},
		"palette": true
	},
	{
		"id": "hollow",
		"label": "Hollow",
		"help": "Shell the selected brush into walls of the set thickness, after a preview.",
		"aliases": ["shell", "make hollow", "ho"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Hollow"},
		"bridge":
		{
			"form": "hollow",
			"description":
			"Shell one brush into walls: each face becomes a wall of the given thickness, inward from the face, so a box gives six walls and a cylinder a pipe. The brush is replaced by the walls (made), and the shell stays editable as a hollow. Brushes with more than 128 distinct faces (spheres, capsules, tori) are refused.",
			"targets": {"min": 1, "max": 1, "entities": false},
			"params":
			[
				{
					"key": "thickness",
					"type": "float",
					"min": 0.05,
					"max": 128.0,
					"step": 0.05,
					"default": 0.25,
					"description": "Wall thickness in metres"
				}
			],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "clip",
		"label": "Clip",
		"help": "Split the selected brush in two across its middle, after a preview.",
		"aliases": ["split", "slice", "bisect"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Clip"},
		"bridge":
		{
			"form": "clip",
			"description":
			"Split one brush in two along a plane across an axis. position is where the plane crosses that axis in world space, snapped to the grid, and must fall inside the brush; without it the brush is cut through its middle. The brush is replaced by the two pieces (made); split_position says where the cut went.",
			"targets": {"min": 1, "max": 1, "entities": false},
			"params":
			[
				{
					"key": "axis",
					"type": "axis",
					"default": "y",
					"description": "The axis the cut crosses: x, y or z"
				},
				{
					"key": "position",
					"type": "float",
					"description": "World coordinate along the axis; the brush's middle if absent"
				}
			],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "clip_to_face",
		"label": "Clip to Face Plane",
		"help": "Cut the selected brushes along the plane of the face picked in Face Select.",
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "clip_to_face",
			"description":
			"Cut brushes along the plane of one face of another brush, the way Clip to Face Plane does: an angled cut taken from an existing surface. Each brush the plane passes through is replaced by its pieces; those it misses are listed in skipped. Refused when it passes through none of them.",
			"targets": {"min": 1, "max": -1, "entities": false},
			"params":
			[
				{
					"key": "plane_brush_id",
					"type": "string",
					"required": true,
					"description": "The brush whose face gives the plane"
				},
				{
					"key": "plane_face",
					"type": "face",
					"required": true,
					"description":
					"That face: an index, a world side such as '+y', or {normal: [x, y, z]}"
				}
			],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "create_arch",
		"label": "Create Structure",
		"help": "Open the structure builder: stairs, arches, domes and the rest.",
		"aliases": ["arch", "stairs", "dome", "generator"],
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "create_structure",
			"description":
			"Build a structure from a generator: an arch, a straight flight of stairs, a spiral stair, a dome, a ring or a door frame, one brush per piece, kept as a live structure. A door frame with cut_opening on also holds the cut for its opening, a pending cut until applied. type picks the generator; settings sets its fields by key (see settings_by_type for each type's keys, ranges and defaults; anything not given keeps its default). position is where it stands and rotation_degrees turns it, Euler XYZ. The pieces come back in made, and generator_id names the structure.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "type",
					"type": "enum",
					"options_from": "generator_types",
					"required": true,
					"description": "arch, stairs, spiral_stairs, dome, ring or door_frame"
				},
				{
					"key": "settings",
					"type": "object",
					"description": "The type's settings by key; see settings_by_type"
				},
				{
					"key": "position",
					"type": "vec3",
					"required": true,
					"description": "Where the structure stands, [x, y, z]"
				},
				{
					"key": "rotation_degrees",
					"type": "vec3",
					"description": "Euler XYZ degrees; none if absent"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "update_structure",
		"label": "Update Structure",
		"help": "Rebuild the selected structure from the settings in its section.",
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "update_structure",
			"description":
			"Rebuild a structure in place from new settings. generator_id names it, as create_arch answers it and hf_get_brushes gives it on each piece. settings sets fields by key, as create_arch takes them for the structure's type (see settings_by_type, which has a Trim Run's keys as well); anything not given keeps the structure's current value. A structure moved or turned as a whole rebuilds where it stands. Each piece keeps its paint, name, brush entity and visgroups where the new pieces line up with the old. Every piece gets a new brush_id: made lists them and removed the old ones. Settings the structure already has, with no piece edited, moved on its own or deleted, rebuild nothing: every piece keeps its brush_id and no_change is true. appearance_dropped lists the old pieces whose paint these settings could not keep, and edits_replaced the pieces edited or deleted by hand that the rebuild put back to the settings' shape.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "generator_id",
					"type": "string",
					"required": true,
					"description": "The structure, as create_arch or hf_get_brushes gives it"
				},
				{
					"key": "settings",
					"type": "object",
					"description": "The fields to change, by key; see settings_by_type"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "detach_structure",
		"label": "Detach Structure",
		"help":
		"Make the selected structure's pieces plain brushes, so an Update no longer rebuilds them.",
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "detach_structure",
			"description":
			"Make a structure's pieces ordinary brushes, left where they are with everything on them. update_structure can no longer rebuild them, so hand edits are safe from it. generator_id names the structure. detached lists the pieces.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "generator_id",
					"type": "string",
					"required": true,
					"description": "The structure, as create_arch or hf_get_brushes gives it"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "run_trim_along_faces",
		"label": "Run Trim Along Faces",
		"help": "Run a skirting or cornice along the wall faces picked in Face Select.",
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"repeat": true
	},
	{
		"id": "repick_trim_run",
		"label": "Re-pick Trim Run",
		"help": "Move the selected trim run onto the wall faces picked in Face Select.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "carve",
		"label": "Carve",
		"help": "Cut the selected brush out of every brush it overlaps, after a preview.",
		"aliases": ["csg", "boolean", "punch"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Carve"},
		"bridge":
		{
			"form": "carve",
			"description":
			"Cut each carver's shape out of every brush it overlaps. The brushes cut are replaced by their pieces, and the carver is used up: it is removed too. A carver that overlaps nothing is listed in skipped; if none overlaps anything, it is refused.",
			"targets": {"min": 1, "max": -1, "entities": false},
			"params": [],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "merge",
		"label": "Merge Brushes",
		"help": "Join the selected brushes into one brush.",
		"aliases": ["join", "combine", "union"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 2, "label": "Merge"},
		"bridge":
		{
			"form": "merge",
			"description":
			"Merge two or more brushes into one: the convex solid they make together. Refused when that solid would not be convex (an L shape, two separate blocks), or when it mixes solid brushes and cuts. The sources are replaced by one brush, given as brush.",
			"targets": {"min": 2, "max": -1, "entities": false},
			"params": [],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "intersect",
		"label": "Intersect",
		"help": "Keep only the volume the selected brushes share.",
		"aliases": ["overlap", "common part"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 2, "label": "Intersect"},
		"bridge":
		{
			"form": "intersect",
			"description":
			"Keep only the volume two or more brushes share. The first brush in brush_ids is cut down by the planes of each of the others, and what is left, one convex brush given as brush, replaces them all. It keeps the first brush's operation, visgroups, group and brush entity; each face keeps the look of the brush whose plane it lies on. Refused when the brushes share no volume, mix solid brushes and cuts, or are not all one entity.",
			"targets": {"min": 2, "max": -1, "entities": false},
			"params": [],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "rotate_ccw",
		"label": "Rotate CCW",
		"help": "Turn the selection a step counterclockwise.",
		"aliases": ["turn left"],
		"category": "Transform",
		"needs_level": true,
		"selection": {},
		"repeat": true
	},
	{
		"id": "rotate_cw",
		"label": "Rotate CW",
		"help": "Turn the selection a step clockwise.",
		"aliases": ["turn right"],
		"category": "Transform",
		"needs_level": true,
		"selection": {},
		"repeat": true
	},
	{
		"id": "flip_selection",
		"label": "Flip Selection",
		"help": "Mirror the selection in place across an axis.",
		"category": "Transform",
		"needs_level": true,
		"selection": {},
		"repeat": true
	},
	{
		"id": "mirror_copy",
		"label": "Mirror Copy",
		"help": "Keep the selection and add copies mirrored across the ticked axes.",
		"category": "Transform",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Mirror Copy"},
		"repeat": true
	},
	{
		"id": "offset_selection",
		"label": "Offset",
		"help": "Move the selection, its vertices or its faces by a typed X, Y and Z.",
		"category": "Transform",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Offset", "allow_faces": true}
	},
	{
		"id": "pick_pivot",
		"label": "Pick Pivot",
		"help": "Click a brush vertex, edge or face to turn and flip about.",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "clear_pivot",
		"label": "Clear Pivot",
		"help": "Go back to turning about the selection's centre.",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "reset_rotation",
		"label": "Reset Rotation",
		"help": "Turn the selection back to no rotation.",
		"category": "Transform",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "reset_rotation",
			"description":
			"Turn each brush back to no rotation about its own centre, keeping its position and size.",
			"targets": {"min": 1, "max": -1, "entities": false},
			"params": [],
			"undo": "scope"
		},
		"repeat": true
	},
	{
		"id": "convert_to_brushes",
		"label": "Convert to Brushes",
		"help": "Make the selected convex mesh or CSG node a brush where it stands.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"mixed_only": true, "label": "Convert to Brushes"},
		"repeat": true
	},
	{
		"id": "apply_rotation_scale",
		"label": "Apply Rotation and Scale",
		"help": "Fold the selected brushes' rotation and scale into their shape, so nothing moves.",
		"category": "Transform",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Apply Rotation and Scale"},
		"palette": true,
		"repeat": true
	},
	{
		"id": "duplicate",
		"label": "Duplicate",
		"help": "Copy the selected brushes and entities in place.",
		"aliases": ["clone", "dupe"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Duplicate"},
		"repeat": true
	},
	{
		"id": "copy",
		"label": "Copy",
		"help": "Put the selection on the clipboard.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Copy"}
	},
	{
		"id": "paste",
		"label": "Paste",
		"help": "Place what is on the clipboard where it was copied from.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 0, "label": "Paste"},
		"repeat": true
	},
	{
		"id": "delete",
		"label": "Delete",
		"help": "Delete the selected brushes and entities.",
		"aliases": ["remove", "del"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Delete"},
		"repeat": true
	},
	{
		"id": "group",
		"label": "Group",
		"help": "Group the selected brushes, so a click picks them all.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 2, "label": "Group"},
		"repeat": true
	},
	{
		"id": "ungroup",
		"label": "Ungroup",
		"help": "Take the selected brushes out of their group.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Ungroup"},
		"repeat": true
	},
	{
		"id": "make_brush_entity",
		"label": "Make Brush Entity",
		"help": "Tie the selected brushes to a brush entity class, such as a trigger or a door.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Make Brush Entity"}
	},
	{
		"id": "back_to_world",
		"label": "Back to World",
		"help":
		"Untie the selected brushes from their brush entity, so they are plain world brushes.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Back to World"}
	},
	{
		"id": "add_to_visgroup",
		"label": "Add to Visgroup",
		"help": "Add the selected brushes and entities to a visgroup.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"minimum": 1, "label": "Add to Visgroup"}
	},
	{
		"id": "new_visgroup",
		"label": "New Visgroup",
		"help": "Make a new visgroup holding the selected brushes and entities.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"minimum": 1, "label": "New Visgroup"}
	},
	{
		"id": "place_entity_here",
		"label": "Place Entity Here",
		"help": "Place an entity on the surface under the cursor, standing on it.",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "show_material_in_browser",
		"label": "Show Material in Browser",
		"help": "Select the picked face's material in the material browser.",
		"category": "Paint",
		"needs_level": true,
		"selection":
		{
			"brushes_only": true,
			"minimum": 1,
			"label": "Show Material in Browser",
			"allow_faces": true
		}
	},
	{
		"id": "move_to_floor",
		"label": "Move to Floor",
		"help": "Drop the selection onto the nearest surface below it.",
		"aliases": ["drop", "drop to floor", "ground"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Move to Floor"},
		"bridge":
		{
			"form": "move_to_floor",
			"description":
			"Move each brush straight down until its bottom rests on the first surface below it: the floor, a brush, or baked collision. Its x and z stay; the new height snaps to the grid.",
			"targets": {"min": 1, "max": -1, "entities": false},
			"params": [],
			"undo": "scope"
		},
		"repeat": true
	},
	{
		"id": "move_to_ceiling",
		"label": "Move to Ceiling",
		"help": "Lift the selection to the nearest surface above it.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Move to Ceiling"},
		"bridge":
		{
			"form": "move_to_ceiling",
			"description":
			"Move each brush straight up until its top meets the first surface above it. Its x and z stay; the new height snaps to the grid.",
			"targets": {"min": 1, "max": -1, "entities": false},
			"params": [],
			"undo": "scope"
		},
		"repeat": true
	},
	{
		"id": "snap_to_grid",
		"label": "Snap to Grid",
		"help": "Put each selected brush's corner, or entity's origin, on the grid.",
		"aliases": ["quantize", "round to grid"],
		"category": "Transform",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Snap to Grid"},
		"bridge":
		{
			"form": "snap_to_grid",
			"description":
			"Move each brush the least distance that puts the lowest corner of its world bounds on a point of the level's grid: a whole number of grid_snap steps from the origin on each axis. Size and rotation stay, so a brush sized in whole steps ends with every corner on the grid. A brush already there is left alone. Refused when grid_snap is 0.",
			"targets": {"min": 1, "max": -1, "entities": false},
			"params": [],
			"undo": "scope"
		},
		"repeat": true
	},
	{
		"id": "shape_box",
		"label": "Shape Box",
		"help": "Draw boxes from now on.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "shape_cylinder",
		"label": "Shape Cylinder",
		"help": "Draw cylinders from now on.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "shape_sphere",
		"label": "Shape Sphere",
		"help": "Draw spheres from now on.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "shape_cone",
		"label": "Shape Cone",
		"help": "Draw cones from now on.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "justify_fit",
		"label": "Justify Fit",
		"help": "Stretch the texture to fit the selected faces.",
		"aliases": ["fit texture", "stretch texture"],
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "justify_center",
		"label": "Justify Center",
		"help": "Centre the texture on the selected faces.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "justify_left",
		"label": "Justify Left",
		"help": "Line the texture's left edge up with the faces' left edge.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "justify_right",
		"label": "Justify Right",
		"help": "Line the texture's right edge up with the faces' right edge.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "justify_top",
		"label": "Justify Top",
		"help": "Line the texture's top edge up with the faces' top edge.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "justify_bottom",
		"label": "Justify Bottom",
		"help": "Line the texture's bottom edge up with the faces' bottom edge.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "justify_fit_u",
		"label": "Justify Fit U",
		"help": "Stretch the texture across the selected faces' width only.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "justify_fit_v",
		"label": "Justify Fit V",
		"help": "Stretch the texture across the selected faces' height only.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_flip_u",
		"label": "UV Flip U",
		"help": "Flip the texture left to right on the selected faces.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "UV Flip", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_flip_v",
		"label": "UV Flip V",
		"help": "Flip the texture top to bottom on the selected faces.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "UV Flip", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_rotate_90",
		"label": "UV Rotate 90",
		"help": "Turn the texture a quarter turn on the selected faces.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Rotate 90", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_align_face",
		"label": "Align to Face",
		"help": "Lay the texture along each selected face's own plane.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Align to Face", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_align_world",
		"label": "Align to World",
		"help": "Lay the texture on the world's axes, so neighbouring faces line up.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Align to World", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_link",
		"label": "Link Faces",
		"help": "Make the selected faces one surface that shares one texture mapping.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Link Faces", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_unlink",
		"label": "Unlink Faces",
		"help": "Give the selected faces their own texture mapping again.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Unlink Faces", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "uv_select_group",
		"label": "Select Linked Faces",
		"help": "Select every face linked with the selected face.",
		"category": "Selection",
		"needs_level": false,
		"selection": {},
		"palette": true
	},
	{
		"id": "uv_wrap",
		"label": "Wrap Texture",
		"help": "Carry the selected face's texture over an edge onto the next face you click.",
		"aliases": ["unwrap"],
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"palette": true
	},
	{
		"id": "apply_to_brush",
		"label": "Apply to Brush",
		"help": "Give every face of the selected brushes the material selected in the browser.",
		"aliases": ["texture", "skin", "apply material", "assign material"],
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply to Brush", "allow_faces": true},
		"palette": true,
		"repeat": true
	},
	{
		"id": "apply_last_texture",
		"label": "Apply Last Texture",
		"help": "Give the selection the material the Texture Picker last sampled.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Last Texture", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_picked_look",
		"label": "Apply Picked Look",
		"help": "Give the selected faces the picked face's material and alignment.",
		"category": "Tools",
		"needs_level": true,
		"selection": {},
		"repeat": true
	},
	{
		"id": "replace_material",
		"label": "Replace Material...",
		"help": "Swap one material for another on every face that wears it.",
		"category": "Tools",
		"needs_level": true,
		"selection": {},
		"palette": true,
		"bridge":
		{
			"form": "replace_material",
			"description":
			"Give every face that wears the material from the material to, what Replace Material does, as one step: across the level, on the brushes brush_ids names when it names any, and on shown brushes alone with scope shown. Each face keeps its UV scale, offset and rotation unless reset_uv is true. from and to are ids or names that hf_get_materials lists. The answer gives faces, how many changed, and brushes, each changed brush's brush_id with its face indices; those faces become the face selection.",
			"targets": {"min": 0, "max": -1, "entities": false},
			"params":
			[
				{
					"key": "from",
					"type": "string",
					"required": true,
					"description": "The material to replace, by id or name"
				},
				{
					"key": "to",
					"type": "string",
					"required": true,
					"description": "The material to put in its place, by id or name"
				},
				{
					"key": "scope",
					"type": "enum",
					"options": ["level", "shown"],
					"default": "level",
					"description": "level, or shown for brushes that are not hidden"
				},
				{
					"key": "reset_uv",
					"type": "bool",
					"default": false,
					"description": "Put each face's UV scale, offset and rotation back to none"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "apply_favorite_1",
		"label": "Apply Favorite 1",
		"help": "Give the selected faces or brushes favorite 1 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_2",
		"label": "Apply Favorite 2",
		"help": "Give the selected faces or brushes favorite 2 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_3",
		"label": "Apply Favorite 3",
		"help": "Give the selected faces or brushes favorite 3 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_4",
		"label": "Apply Favorite 4",
		"help": "Give the selected faces or brushes favorite 4 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_5",
		"label": "Apply Favorite 5",
		"help": "Give the selected faces or brushes favorite 5 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_6",
		"label": "Apply Favorite 6",
		"help": "Give the selected faces or brushes favorite 6 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_7",
		"label": "Apply Favorite 7",
		"help": "Give the selected faces or brushes favorite 7 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_8",
		"label": "Apply Favorite 8",
		"help": "Give the selected faces or brushes favorite 8 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "apply_favorite_9",
		"label": "Apply Favorite 9",
		"help": "Give the selected faces or brushes favorite 9 from the context toolbar.",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "entity_io",
		"label": "Entity I/O",
		"help": "Open the Entities tab, where outputs and their targets are wired.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Entity I/O"}
	},
	{
		"id": "entity_props",
		"label": "Entity Props",
		"help": "Open the Entities tab, where the selected entity's properties are edited.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Entity Props"}
	},
	{
		"id": "texture_gizmo",
		"label": "Texture Gizmo",
		"help":
		"Show or hide the texture gizmo, which slides, stretches and turns a face's texture by dragging.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "cycle_io_wires",
		"label": "Cycle I/O Wires",
		"help": "Step the I/O wires through none, all, the selection's chain and its own.",
		"aliases": ["wire mode", "show wires"],
		"category": "Workflow",
		"needs_level": false,
		"selection": {},
		"palette": true
	},
	{
		"id": "highlight_connected",
		"label": "Highlight Connected",
		"help": "Pulse every entity wired to the selected one.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Highlight Connected"}
	},
	{
		"id": "axis_x",
		"label": "Lock X",
		"help": "Hold the next drag to the X axis.",
		"category": "Axis Lock",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "axis_y",
		"label": "Lock Y",
		"help": "Hold the next drag to the Y axis.",
		"category": "Axis Lock",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "axis_z",
		"label": "Lock Z",
		"help": "Hold the next drag to the Z axis.",
		"category": "Axis Lock",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "toggle_draw_on_face",
		"label": "Draw on Face",
		"help": "Build a draw on the plane of the face it starts on.",
		"category": "Axis Lock",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "vertex_edit",
		"label": "Vertex Edit",
		"help": "Turn Vertex mode on or off, to move the selected brushes' corners and edges.",
		"aliases": ["edit vertices", "vertices", "points"],
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Edit"}
	},
	{
		"id": "vertex_submode",
		"label": "Vertex Submode",
		"help": "In Vertex mode, pick corners.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Submode"}
	},
	{
		"id": "edge_submode",
		"label": "Edge Submode",
		"help": "In Vertex mode, pick edges.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Edge Submode"}
	},
	{
		"id": "vertex_edge_mode",
		"label": "Edge Mode",
		"help": "In Vertex mode, switch between picking corners and edges.",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "vertex_merge",
		"label": "Merge Vertices",
		"help": "Merge the selected vertices into one at their middle.",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Merge"},
		"repeat": true
	},
	{
		"id": "vertex_split",
		"label": "Vertex Split",
		"help": "Split the selected edge at its middle.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Split"},
		"repeat": true
	},
	{
		"id": "vertex_split_edge",
		"label": "Split Edge",
		"help": "Split the selected edge at its middle.",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Split Edge"},
		"repeat": true
	},
	{
		"id": "vertex_clip_convex",
		"label": "Vertex Clip Convex",
		"help":
		"Rebuild each brush with vertices selected from its convex hull, when it is no longer convex.",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Clip Convex"},
		"repeat": true
	},
	{
		"id": "vertex_snap_to_grid",
		"label": "Snap Vertices to Grid",
		"help": "Move the selected vertices to their nearest grid points.",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Snap Vertices to Grid"},
		"repeat": true
	},
	{
		"id": "vertex_exit",
		"label": "Vertex Exit",
		"help": "Leave Vertex mode.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "select_all",
		"label": "Select All",
		"help": "Select every brush and entity.",
		"category": "Selection",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "invert_selection",
		"label": "Invert Selection",
		"help": "Select what is not selected, and drop what is.",
		"aliases": ["everything else", "select inverse"],
		"category": "Selection",
		"needs_level": true,
		"selection": {},
		"palette": true
	},
	{
		"id": "select_inside",
		"label": "Select Inside",
		"help": "Select every brush wholly inside the selected brush, and every entity in it.",
		"aliases": ["select room", "select in brush"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Select Inside"},
		"palette": true
	},
	{
		"id": "select_partly_inside",
		"label": "Select Partly Inside",
		"help": "Select every brush at least partly inside the selected brush.",
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Select Partly Inside"},
		"palette": true
	},
	{
		"id": "select_touching",
		"label": "Select Touching",
		"help": "Select every brush that touches or overlaps the selected brush.",
		"aliases": ["select overlapping"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Select Touching"},
		"palette": true
	},
	{
		"id": "select_column",
		"label": "Select Column",
		"help":
		"Select Inside, with the selected brush's footprint running from the bottom of the level to the top.",
		"aliases": ["select every floor"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Select Column"},
		"palette": true
	},
	{
		"id": "hide_selection",
		"label": "Hide Selection",
		"help": "Hide the selection until Show Hidden, without a visgroup.",
		"aliases": ["hide selected", "hide these"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Hide Selection"}
	},
	{
		"id": "show_hidden",
		"label": "Show Hidden",
		"help": "Show what Hide Selection and an isolate hid.",
		"aliases": ["unhide", "unhide all"],
		"category": "Selection",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "isolate_selection",
		"label": "Isolate Selection",
		"help": "Show only the selection, whatever visgroups it is in.",
		"aliases": ["hide everything else", "solo"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Isolate Selection"},
		"palette": true
	},
	{
		"id": "isolate_visgroups",
		"label": "Isolate Visgroups",
		"help": "Show only the visgroups the selection is in.",
		"aliases": ["isolate visgroup", "show only visgroup"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Isolate Visgroups"},
		"palette": true
	},
	{
		"id": "end_isolate",
		"label": "End Isolate",
		"help": "Show what an isolate hid.",
		"aliases": ["stop isolating"],
		"category": "Selection",
		"needs_level": true,
		"selection": {},
		"palette": true
	},
	{
		"id": "previous_visibility",
		"label": "Previous Visibility",
		"help": "Go back to what was shown before the last hide or isolate.",
		"aliases": ["undo visibility", "last visibility"],
		"category": "Selection",
		"needs_level": true,
		"selection": {},
		"palette": true
	},
	{
		"id": "deselect_all",
		"label": "Deselect All",
		"help": "Select nothing: brushes, entities and faces.",
		"aliases": ["select none", "clear selection"],
		"category": "Selection",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "select_similar",
		"label": "Select Similar",
		"help":
		"Select the faces, brushes or entities like the ones selected, on what Selection Filters ticks.",
		"aliases": ["select same", "same material"],
		"category": "Selection",
		"needs_level": true,
		"selection":
		{"brushes_only": false, "minimum": 1, "label": "Select Similar", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "selection_filter",
		"label": "Selection Filters",
		"help": "Open the selection filters, which pick by kind, material and more.",
		"category": "Selection",
		"needs_level": false,
		"selection": {"mixed_only": true, "label": "Selection Filters"}
	},
	{
		"id": "quick_select",
		"label": "Quick Select",
		"help":
		"Select brushes or entities by a typed rule, such as class is light_point and energy > 2.",
		"aliases": ["select by rule", "select where"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"mixed_only": true, "label": "Quick Select"},
		"palette": true
	},
	{
		"id": "grow_selection",
		"label": "Grow Selection",
		"help":
		"Add the faces next to the selected faces, or the brushes touching the selected brushes.",
		"category": "Selection",
		"needs_level": true,
		"selection": {"minimum": 1, "label": "Grow Selection", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "shrink_selection",
		"label": "Shrink Selection",
		"help": "Drop the selected faces or brushes on the edge of the selection.",
		"category": "Selection",
		"needs_level": true,
		"selection": {"minimum": 1, "label": "Shrink Selection", "allow_faces": true},
		"repeat": true
	},
	{
		"id": "toggle_face_xray",
		"label": "Toggle Face X-ray",
		"help": "Let the face marquee take covered and back faces.",
		"category": "Selection",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "toggle_selection_size",
		"label": "Show Selection Size",
		"help": "Label the selection's width, depth and height in the viewport.",
		"category": "Selection",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "quick_save_prefab",
		"label": "Save Selection as Prefab",
		"help": "Save the selected brushes and entities as a prefab.",
		"aliases": ["make prefab"],
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Quick Save Prefab"}
	},
	{
		"id": "quick_save_linked_prefab",
		"label": "Quick Save Linked Prefab",
		"help": "Save the selection as a prefab and make it a linked copy of the file.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Quick Save Linked Prefab"}
	},
	{
		"id": "cycle_variant",
		"label": "Cycle Prefab Variant",
		"help": "Switch the selected prefab copy to its next variant.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Cycle Variant"},
		"bridge":
		{
			"form": "cycle_variant",
			"description":
			"Switch a placed prefab to its next variant, rebuilding its pieces. Name any one piece of it, a brush or an entity; hf_get_brushes and hf_get_entities give each piece's prefab. Refused for a prefab with one variant.",
			"targets": {"min": 1, "max": 1, "entities": true},
			"params": [],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "push_to_source",
		"label": "Push to Source",
		"help": "Write the selected linked copy's changes back to its prefab file.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Push to Source"}
	},
	{
		"id": "unlink_prefab_copy",
		"label": "Unlink Prefab Copy",
		"help": "Cut the selected copy's link to its prefab, keeping what it is.",
		"aliases": ["unlink copy", "break link"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Unlink Prefab Copy"},
		"palette": true,
		"repeat": true
	},
	{
		"id": "discard_prefab_changes",
		"label": "Discard Prefab Changes",
		"help": "Rebuild the selected linked copy from its prefab, dropping its changes.",
		"aliases": ["revert copy", "throw away changes"],
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Discard Prefab Changes"},
		"palette": true,
		"repeat": true
	},
	{
		"id": "select_linked_copies",
		"label": "Select Linked Copies",
		"help": "Select every copy linked to the selected copy's prefab.",
		"aliases": ["select copies", "select siblings"],
		"category": "Selection",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Select Linked Copies"},
		"palette": true
	},
	{
		"id": "propagate_prefab",
		"label": "Propagate Prefab",
		"help": "Bring every linked copy of the selected prefab up to date with its file.",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Propagate Prefab"},
		"bridge":
		{
			"form": "propagate_prefab",
			"description":
			"Rebuild every linked copy of a prefab from its saved file, as Propagate Prefab does. Name any one piece of a copy of it, a brush or an entity. Refused when no copy of that prefab is linked.",
			"targets": {"min": 1, "max": 1, "entities": true},
			"params": [],
			"undo": "level"
		}
	},
	{
		"id": "place_prefab",
		"label": "Place Prefab",
		"help": "Place the prefab chosen in the library at the cursor.",
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "place_prefab",
			"description":
			"Place a prefab from the project's prefab library. Its pieces come in as new brushes and entities with fresh names and ties, as a drop from the library makes them, recorded as a copy that cycle_variant and propagate_prefab can change. prefab names it: prefabs lists the library, each one's name, variants, tags and how many brushes and entities it holds. position is where its centre goes, exactly; rotation_degrees turns it about that centre, Euler XYZ. variant picks one of its variants. linked makes the copy follow its file when the file changes and is propagated. The answer gives instance_id, the brushes made and entities_made.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "prefab",
					"type": "string",
					"required": true,
					"description": "The library prefab's name; see prefabs"
				},
				{
					"key": "position",
					"type": "vec3",
					"required": true,
					"description": "Where its centre goes, [x, y, z]"
				},
				{
					"key": "rotation_degrees",
					"type": "vec3",
					"description": "Euler XYZ degrees about its centre; none if absent"
				},
				{
					"key": "variant",
					"type": "string",
					"description": "One of its variants; its base if absent"
				},
				{
					"key": "linked",
					"type": "bool",
					"default": false,
					"description": "Whether the copy follows its file when propagated"
				}
			],
			"undo": "level"
		},
		"repeat": true
	},
	{
		"id": "texture_picker",
		"label": "Texture Picker",
		"help":
		"Sample a face's material and its whole look, for Apply Last Texture and Apply Picked Look.",
		"aliases": ["eyedropper", "sample texture"],
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "surface_paint",
		"label": "Surface Paint",
		"help": "Turn floor Paint mode on.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_bucket",
		"label": "Paint Brush",
		"help": "Paint floor cells.",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_erase",
		"label": "Erase",
		"help": "Erase floor cells.",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_ramp",
		"label": "Ramp / Rect",
		"help": "Paint a rectangle of floor cells.",
		"category": "Paint",
		"needs_level": false,
		"selection": {},
		"bridge":
		{
			"form": "paint_rect",
			"description":
			"Paint or erase a rectangle of floor cells on a paint layer, what the Rect tool does with a drag. A cell is [x, z] on the layer's grid, one grid step square, the grid's second axis along world Z. from and to are two corners, both included, in any order; to alone is from, so one cell is a rectangle of one. Filled cells get a floor and walls round the edge of the painted area, rebuilt before the answer, and the walls stand at the default height until paint_raise sets one. filled false erases the cells. material writes a cell material id on the filled cells, as the Blend tool does. layer is a layer's index or name from paint_layers; the layer the Paint tab has active if absent. The answer gives the layer used, cells, cells_changed (how many filled bits flipped), materials_changed (how many cell material ids changed), and bounds, the rectangle in world metres on the floor's top.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "layer",
					"type": "layer",
					"description":
					"The paint layer, by index from 0 or by name; the active one if absent"
				},
				{
					"key": "from",
					"type": "cell",
					"required": true,
					"description": "One corner of the rectangle, [x, z] in cells"
				},
				{
					"key": "to",
					"type": "cell",
					"description": "The opposite corner, [x, z] in cells; from if absent"
				},
				{
					"key": "filled",
					"type": "bool",
					"default": true,
					"description": "true paints the cells, false erases them"
				},
				{
					"key": "material",
					"type": "int",
					"min": 0,
					"max": 255,
					"description":
					"A cell material id for the filled cells, as the Blend tool writes one"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "paint_line",
		"label": "Line",
		"help": "Paint a line of floor cells.",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_fill",
		"label": "Bucket Fill",
		"help": "Fill a connected area of floor cells.",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_blend",
		"label": "Blend",
		"help": "Paint the blend between ground materials.",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_raise",
		"label": "Raise Painted Walls",
		"help": "Raise walls round the last painted footprint.",
		"category": "Paint",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "raise_rect",
			"description":
			"Set the wall height of the painted cells in a rectangle on a paint layer, what the Y gesture does for the last stroke: the walls round that floor are rebuilt at height metres, before the answer. Cells in the rectangle that are not painted are left alone, and a rectangle with none painted is refused; paint_ramp paints them. from and to are two corners, [x, z] in cells, both included; to alone is from. layer is an index or a name from paint_layers; the active layer if absent. The answer gives raised, the painted cells, and heights_changed, how many overrides were added or changed, including pinning cells to the default height.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "layer",
					"type": "layer",
					"description":
					"The paint layer, by index from 0 or by name; the active one if absent"
				},
				{
					"key": "from",
					"type": "cell",
					"required": true,
					"description": "One corner of the rectangle, [x, z] in cells"
				},
				{
					"key": "to",
					"type": "cell",
					"description": "The opposite corner, [x, z] in cells; from if absent"
				},
				{
					"key": "height",
					"type": "float",
					"min": 0.25,
					"max": 256.0,
					"step": 0.25,
					"required": true,
					"description": "The wall height in metres"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "paint_mirror_x",
		"label": "Toggle Paint Mirror X",
		"help": "Mirror painting across the grid's X origin.",
		"category": "Paint",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "paint_mirror_z",
		"label": "Toggle Paint Mirror Z",
		"help": "Mirror painting across the grid's Z origin.",
		"category": "Paint",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "paint_room",
		"label": "Stamp Painted Room",
		"help": "Repeat the last rectangle as a floor with walls round it.",
		"category": "Paint",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "stamp_room",
			"description":
			"Paint a room on a paint layer: a width by depth rectangle of floor cells whose lowest corner is at, [x, z] in cells, and, when height is given, its walls raised to that many metres, in one step. What the H key does with the last rectangle's size at the hovered cell, with the size and the corner named; width and depth default to 4, the size the tool starts with. Without height the walls stand at the default height. layer is an index or a name from paint_layers; the active layer if absent. The answer gives from and to, the corners painted, cells, cells_changed, raised, and bounds, the room in world metres on the floor's top.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "layer",
					"type": "layer",
					"description":
					"The paint layer, by index from 0 or by name; the active one if absent"
				},
				{
					"key": "at",
					"type": "cell",
					"required": true,
					"description": "The room's lowest corner, [x, z] in cells"
				},
				{
					"key": "width",
					"type": "int",
					"min": 1,
					"max": 256,
					"default": 4,
					"description": "Cells along x"
				},
				{
					"key": "depth",
					"type": "int",
					"min": 1,
					"max": 256,
					"default": 4,
					"description": "Cells along z"
				},
				{
					"key": "height",
					"type": "float",
					"min": 0.25,
					"max": 256.0,
					"step": 0.25,
					"description": "The wall height in metres; the default height if absent"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "paint_confirm_connector",
		"label": "Confirm Paint Connector",
		"help": "Keep the ramp or stair ghost shown between painted layers.",
		"category": "Paint",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "confirm_connector",
			"description":
			"Keep a ramp or stairs between two paint layers at different heights, what Enter does for the ghost a stroke proposes: where a painted cell in the rectangle on layer sits beside a painted cell of another layer, a connector is confirmed across that edge and built by the next bake, with the level's connector mode, stair height and width. from and to are two corners, [x, z] in cells, both included; to alone is from. to_layer keeps only connectors that join that layer. One already confirmed is counted in already, not added again; a rectangle that meets no other layer, or only boundaries already confirmed, is refused. The answer lists connectors, each one's from_layer, to_layer, from_cell, to_cell, type and width_cells.",
			"targets": {"min": 0, "max": 0, "entities": false},
			"params":
			[
				{
					"key": "layer",
					"type": "layer",
					"description":
					"The paint layer the cells are on, by index from 0 or by name; the active one if absent"
				},
				{
					"key": "from",
					"type": "cell",
					"required": true,
					"description": "One corner of the rectangle, [x, z] in cells"
				},
				{
					"key": "to",
					"type": "cell",
					"description": "The opposite corner, [x, z] in cells; from if absent"
				},
				{
					"key": "to_layer",
					"type": "layer",
					"description":
					"Only connectors to this layer, by index or name; any other layer if absent"
				}
			],
			"undo": "level"
		}
	},
	{
		"id": "grid_decrease",
		"label": "Grid Decrease",
		"help": "Halve the grid step.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_increase",
		"label": "Grid Increase",
		"help": "Double the grid step.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_up",
		"label": "Grid Up",
		"help": "Raise the drawing plane one grid step.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_down",
		"label": "Grid Down",
		"help": "Lower the drawing plane one grid step.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_reset",
		"label": "Reset Grid",
		"help": "Put the drawing plane back at the level's origin, flat.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_align",
		"label": "Align Grid to Selection",
		"help": "Move the drawing plane to the selected face, vertices or brush top.",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "toggle_grid",
		"label": "Toggle Grid",
		"help": "Show or hide the grid.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "quick_bake",
		"label": "Quick Bake",
		"help": "Bake the level.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "undo",
		"label": "Undo",
		"help": "Take back the last change.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "redo",
		"label": "Redo",
		"help": "Put back the last change undone.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "set_grid_snap",
		"label": "Set Grid Snap",
		"help": "Set the grid step to a value.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "measure",
		"label": "Measure",
		"help": "Start the Measure tool, which draws rulers between points.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "snap_next_vertex",
		"label": "Next Pick: Vertex Only",
		"help":
		"The next click snaps only to a vertex, whatever snaps are on, then they all return.",
		"aliases": ["vertex only"],
		"category": "Editing",
		"needs_level": true,
		"palette": true,
		"selection": {}
	},
	{
		"id": "snap_next_midpoint",
		"label": "Next Pick: Midpoint Only",
		"help":
		"The next click snaps only to the middle of an edge, then every snap that was on returns.",
		"aliases": ["midpoint only", "edge middle"],
		"category": "Editing",
		"needs_level": true,
		"palette": true,
		"selection": {}
	},
	{
		"id": "snap_next_centre",
		"label": "Next Pick: Centre Only",
		"help":
		"The next click snaps only to a brush's centre, then every snap that was on returns.",
		"aliases": ["centre only", "center only"],
		"category": "Editing",
		"needs_level": true,
		"palette": true,
		"selection": {}
	},
	{
		"id": "snap_next_perpendicular",
		"label": "Next Pick: Perpendicular Only",
		"help":
		"The next click snaps only to the foot of a perpendicular on an edge, then every snap returns.",
		"aliases": ["perpendicular only"],
		"category": "Editing",
		"needs_level": true,
		"palette": true,
		"selection": {}
	},
	{
		"id": "snap_next_grid",
		"label": "Next Pick: Grid Only",
		"help":
		"The next click snaps only to the grid, even with Grid off, then every snap that was on returns.",
		"aliases": ["grid only"],
		"category": "Editing",
		"needs_level": true,
		"palette": true,
		"selection": {}
	},
	{
		"id": "cancel_drag",
		"label": "Cancel Drag",
		"help": "Stop the drag in progress and clear any typed number.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "apply_pending_cuts",
		"label": "Apply Pending Cuts",
		"help": "Apply the cuts waiting in Pending Cuts to the brushes they overlap.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "commit_cuts",
		"label": "Commit Cuts",
		"help": "Apply the pending cuts and bake.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "clear_pending_cuts",
		"label": "Clear Pending Cuts",
		"help": "Delete the cuts waiting in Pending Cuts.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "bake_preview_toggle",
		"label": "Bake Preview Toggle",
		"help": "Show the bake as a wireframe over the brushes, or stop showing it.",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "context_menu",
		"label": "Context Menu",
		"help": "Open the context menu at the cursor.",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "radial_menu",
		"label": "Radial Menu",
		"help": "Open the radial menu, when Power-user overlays are on.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "toggle_operation_replay",
		"label": "Operation Replay Timeline",
		"help": "Show or hide the operation replay timeline, when Power-user overlays are on.",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "apply_context_material",
		"label": "Apply Context Material",
		"help": "Give the selection the material clicked on the context toolbar.",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{
			"brushes_only": true,
			"minimum": 1,
			"label": "Apply Context Material",
			"allow_faces": true
		},
		"guard_only": true
	},
]

## id -> entry, built from `COMMANDS` on first use.
static var _by_id: Dictionary = {}


static func _index() -> Dictionary:
	if _by_id.is_empty():
		for entry in COMMANDS:
			_by_id[str(entry["id"])] = entry
	return _by_id


## Every id, the guard-only one included, in table order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in COMMANDS:
		out.append(str(entry["id"]))
	return out


## The ids `HFPluginCommands.execute()` runs, in table order.
static func dispatched_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in COMMANDS:
		if not bool(entry.get("guard_only", false)):
			out.append(str(entry["id"]))
	return out


## Whether the table lists `id`, as a dispatched command or a guard-only one.
static func has(id: String) -> bool:
	return _index().has(id)


## Whether `HFPluginCommands.execute()` runs this id.
static func dispatches(id: String) -> bool:
	var entry: Dictionary = _index().get(id, {})
	return not entry.is_empty() and not bool(entry.get("guard_only", false))


## The entry for `id`, or `{}`. Read-only: it is the table itself.
static func find(id: String) -> Dictionary:
	return _index().get(id, {})


## What the palette calls `id`, or "" for an id the table does not know.
static func label(id: String) -> String:
	return str(find(id).get("label", ""))


## The group `id` is listed under, or "" for an id the table does not know.
## One sentence on what the command does, or "".
static func help(id: String) -> String:
	return str(find(id).get("help", ""))


static func category(id: String) -> String:
	return str(find(id).get("category", ""))


## The other words the palette finds `id` by. A copy.
static func aliases(id: String) -> PackedStringArray:
	return PackedStringArray(find(id).get("aliases", []))


## Whether Repeat Last Command may run `id` again.
static func repeatable(id: String) -> bool:
	return bool(find(id).get("repeat", false))


## Whether the palette refuses `id` when there is no level, rather than make one.
static func needs_level(id: String) -> bool:
	return bool(find(id).get("needs_level", false))


## What the surface guard asks of the selection for `id`, or `{}`. A copy, so a
## caller can change it without changing the table.
static func selection(id: String) -> Dictionary:
	var asked: Dictionary = find(id).get("selection", {})
	return asked.duplicate(true)


## The ids the hotkey palette lists although no key is bound to them, in table
## order.
static func palette_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in COMMANDS:
		if bool(entry.get("palette", false)):
			out.append(str(entry["id"]))
	return out


## The ids an agent may run over the bridge, in table order.
static func bridge_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in COMMANDS:
		if entry.has("bridge"):
			out.append(str(entry["id"]))
	return out


## How the bridge runs `id`, or `{}` for a command it does not run. Read-only.
static func bridge(id: String) -> Dictionary:
	return find(id).get("bridge", {})


## One bridge parameter of `id`, or `{}`. The dock reads Hollow's thickness range
## here, so the dock and the bridge offer the same one.
static func field(id: String, key: String) -> Dictionary:
	for entry in bridge(id).get("params", []):
		if str(entry.get("key", "")) == key:
			return entry
	return {}
