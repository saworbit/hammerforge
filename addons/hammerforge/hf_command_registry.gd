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
## - `category`: the group they list it under.
## - `needs_level`: the palette refuses it when there is no level, rather than
##   make one as a side effect.
## - `selection`: `{}`, or what the surface guard asks of the selection
##   (`HFPluginSelectionState.managed_action_surface_allowed()`): `brushes_only`,
##   `minimum`, `label` for its toasts, `allow_faces`, `mixed_only`. The keyboard
##   router takes `brushes_only`, `minimum` and `label` from here too, so a
##   refusal reads the same from a key as from the palette (#1298).
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
		"category": "Workflow",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "toggle_paint_mode",
		"label": "Toggle Paint Mode",
		"category": "Workflow",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "quick_play",
		"label": "Quick Play",
		"category": "Workflow",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "validate_level",
		"label": "Validate Level",
		"category": "Workflow",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "tool_draw",
		"label": "Draw",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_select",
		"label": "Select",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "extrude_up",
		"label": "Extrude Up",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude_up",
		"label": "Extrude Up",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude",
		"label": "Extrude Up (alt)",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "extrude_down",
		"label": "Extrude Down",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude_down",
		"label": "Extrude Down",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "tool_extrude_down_alt",
		"label": "Extrude Down (alt)",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "hollow",
		"label": "Hollow",
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
		}
	},
	{
		"id": "clip",
		"label": "Clip",
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
		}
	},
	{
		"id": "clip_to_face",
		"label": "Clip to Face Plane",
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
		}
	},
	{
		"id": "create_arch",
		"label": "Create Structure",
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
		"category": "Editing",
		"needs_level": true,
		"selection": {},
		"bridge":
		{
			"form": "update_structure",
			"description":
			"Rebuild a structure in place from new settings. generator_id names it, as create_arch answers it and hf_get_brushes gives it on each piece. settings sets fields by key, as create_arch takes them for the structure's type (see settings_by_type); anything not given keeps the structure's current value. A structure moved or turned as a whole rebuilds where it stands. Each piece keeps its paint, name, brush entity and visgroups where the new pieces line up with the old. Every piece gets a new brush_id: made lists them and removed the old ones. Settings the structure already has, with no piece edited, moved on its own or deleted, rebuild nothing: every piece keeps its brush_id and no_change is true. appearance_dropped lists the old pieces whose paint these settings could not keep, and edits_replaced the pieces edited or deleted by hand that the rebuild put back to the settings' shape.",
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
		"id": "carve",
		"label": "Carve",
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
		}
	},
	{
		"id": "merge",
		"label": "Merge Brushes",
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
		}
	},
	{
		"id": "intersect",
		"label": "Intersect",
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
		}
	},
	{
		"id": "rotate_ccw",
		"label": "Rotate CCW",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "rotate_cw",
		"label": "Rotate CW",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "flip_selection",
		"label": "Flip Selection",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "mirror_copy",
		"label": "Mirror Copy",
		"category": "Transform",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Mirror Copy"}
	},
	{
		"id": "offset_selection",
		"label": "Offset",
		"category": "Transform",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Offset", "allow_faces": true}
	},
	{
		"id": "pick_pivot",
		"label": "Pick Pivot",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "clear_pivot",
		"label": "Clear Pivot",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "reset_rotation",
		"label": "Reset Rotation",
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
		}
	},
	{
		"id": "duplicate",
		"label": "Duplicate",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Duplicate"}
	},
	{
		"id": "copy",
		"label": "Copy",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Copy"}
	},
	{
		"id": "paste",
		"label": "Paste",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 0, "label": "Paste"}
	},
	{
		"id": "delete",
		"label": "Delete",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Delete"}
	},
	{
		"id": "group",
		"label": "Group",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 2, "label": "Group"}
	},
	{
		"id": "ungroup",
		"label": "Ungroup",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Ungroup"}
	},
	{
		"id": "move_to_floor",
		"label": "Move to Floor",
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
		}
	},
	{
		"id": "move_to_ceiling",
		"label": "Move to Ceiling",
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
		}
	},
	{
		"id": "snap_to_grid",
		"label": "Snap to Grid",
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
		}
	},
	{
		"id": "shape_box",
		"label": "Shape Box",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "shape_cylinder",
		"label": "Shape Cylinder",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "shape_sphere",
		"label": "Shape Sphere",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "shape_cone",
		"label": "Shape Cone",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "justify_fit",
		"label": "Justify Fit",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_center",
		"label": "Justify Center",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_left",
		"label": "Justify Left",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_right",
		"label": "Justify Right",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_top",
		"label": "Justify Top",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_bottom",
		"label": "Justify Bottom",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_fit_u",
		"label": "Justify Fit U",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "justify_fit_v",
		"label": "Justify Fit V",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Justify", "allow_faces": true}
	},
	{
		"id": "uv_flip_u",
		"label": "UV Flip U",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "UV Flip", "allow_faces": true}
	},
	{
		"id": "uv_flip_v",
		"label": "UV Flip V",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "UV Flip", "allow_faces": true}
	},
	{
		"id": "uv_rotate_90",
		"label": "UV Rotate 90",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "UV Rotate 90", "allow_faces": true}
	},
	{
		"id": "apply_to_brush",
		"label": "Apply to Brush",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply to Brush", "allow_faces": true}
	},
	{
		"id": "apply_last_texture",
		"label": "Apply Last Texture",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Last Texture", "allow_faces": true}
	},
	{
		"id": "apply_picked_look",
		"label": "Apply Picked Look",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "apply_favorite_1",
		"label": "Apply Favorite 1",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_2",
		"label": "Apply Favorite 2",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_3",
		"label": "Apply Favorite 3",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_4",
		"label": "Apply Favorite 4",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_5",
		"label": "Apply Favorite 5",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_6",
		"label": "Apply Favorite 6",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_7",
		"label": "Apply Favorite 7",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_8",
		"label": "Apply Favorite 8",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "apply_favorite_9",
		"label": "Apply Favorite 9",
		"category": "Tools",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply Favorite", "allow_faces": true}
	},
	{
		"id": "entity_io",
		"label": "Entity I/O",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Entity I/O"}
	},
	{
		"id": "entity_props",
		"label": "Entity Props",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Entity Props"}
	},
	{
		"id": "highlight_connected",
		"label": "Highlight Connected",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Highlight Connected"}
	},
	{
		"id": "axis_x",
		"label": "Lock X",
		"category": "Axis Lock",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "axis_y",
		"label": "Lock Y",
		"category": "Axis Lock",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "axis_z",
		"label": "Lock Z",
		"category": "Axis Lock",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "vertex_edit",
		"label": "Vertex Edit",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Edit"}
	},
	{
		"id": "vertex_submode",
		"label": "Vertex Submode",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Submode"}
	},
	{
		"id": "edge_submode",
		"label": "Edge Submode",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Edge Submode"}
	},
	{
		"id": "vertex_edge_mode",
		"label": "Edge Mode",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "vertex_merge",
		"label": "Merge Vertices",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Merge"}
	},
	{
		"id": "vertex_split",
		"label": "Vertex Split",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Split"}
	},
	{
		"id": "vertex_split_edge",
		"label": "Split Edge",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Split Edge"}
	},
	{
		"id": "vertex_clip_convex",
		"label": "Vertex Clip Convex",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Vertex Clip Convex"}
	},
	{
		"id": "vertex_snap_to_grid",
		"label": "Snap Vertices to Grid",
		"category": "Tools",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Snap Vertices to Grid"}
	},
	{
		"id": "vertex_exit",
		"label": "Vertex Exit",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "select_all",
		"label": "Select All",
		"category": "Selection",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "deselect_all",
		"label": "Deselect All",
		"category": "Selection",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "select_similar",
		"label": "Select Similar",
		"category": "Selection",
		"needs_level": true,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Select Similar", "allow_faces": true}
	},
	{
		"id": "selection_filter",
		"label": "Selection Filters",
		"category": "Selection",
		"needs_level": false,
		"selection": {"mixed_only": true, "label": "Selection Filters"}
	},
	{
		"id": "toggle_selection_size",
		"label": "Show Selection Size",
		"category": "Selection",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "quick_save_prefab",
		"label": "Save Selection as Prefab",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Quick Save Prefab"}
	},
	{
		"id": "quick_save_linked_prefab",
		"label": "Quick Save Linked Prefab",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Quick Save Linked Prefab"}
	},
	{
		"id": "cycle_variant",
		"label": "Cycle Prefab Variant",
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
		}
	},
	{
		"id": "push_to_source",
		"label": "Push to Source",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Push to Source"}
	},
	{
		"id": "propagate_prefab",
		"label": "Propagate Prefab",
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
		}
	},
	{
		"id": "texture_picker",
		"label": "Texture Picker",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "surface_paint",
		"label": "Surface Paint",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_bucket",
		"label": "Paint Brush",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_erase",
		"label": "Erase",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_ramp",
		"label": "Ramp / Rect",
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
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_fill",
		"label": "Bucket Fill",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_blend",
		"label": "Blend",
		"category": "Paint",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "paint_raise",
		"label": "Raise Painted Walls",
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
		"category": "Paint",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "paint_mirror_z",
		"label": "Toggle Paint Mirror Z",
		"category": "Paint",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "paint_room",
		"label": "Stamp Painted Room",
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
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_increase",
		"label": "Grid Increase",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_up",
		"label": "Grid Up",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_down",
		"label": "Grid Down",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_reset",
		"label": "Reset Grid",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "grid_align",
		"label": "Align Grid to Selection",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "toggle_grid",
		"label": "Toggle Grid",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "quick_bake",
		"label": "Quick Bake",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{"id": "undo", "label": "Undo", "category": "Editing", "needs_level": false, "selection": {}},
	{"id": "redo", "label": "Redo", "category": "Editing", "needs_level": false, "selection": {}},
	{
		"id": "set_grid_snap",
		"label": "Set Grid Snap",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "measure",
		"label": "Measure",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "cancel_drag",
		"label": "Cancel Drag",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "apply_pending_cuts",
		"label": "Apply Pending Cuts",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "commit_cuts",
		"label": "Commit Cuts",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "clear_pending_cuts",
		"label": "Clear Pending Cuts",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "bake_preview_toggle",
		"label": "Bake Preview Toggle",
		"category": "Editing",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "context_menu",
		"label": "Context Menu",
		"category": "Tools",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "radial_menu",
		"label": "Radial Menu",
		"category": "Tools",
		"needs_level": false,
		"selection": {}
	},
	{
		"id": "apply_context_material",
		"label": "Apply Context Material",
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
static func category(id: String) -> String:
	return str(find(id).get("category", ""))


## Whether the palette refuses `id` when there is no level, rather than make one.
static func needs_level(id: String) -> bool:
	return bool(find(id).get("needs_level", false))


## What the surface guard asks of the selection for `id`, or `{}`. A copy, so a
## caller can change it without changing the table.
static func selection(id: String) -> Dictionary:
	var asked: Dictionary = find(id).get("selection", {})
	return asked.duplicate(true)


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
