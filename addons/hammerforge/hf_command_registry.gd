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
##   router takes `brushes_only` and `minimum` from here too.
## - `guard_only`: an id the guard knows that `execute()` never runs. The material
##   quick apply asks the guard about `apply_context_material` and then applies the
##   material itself.
##
## No comments go between the entries: gdformat moves a comment that sits between
## wrapped dictionary entries into one of them.

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
		"selection": {"brushes_only": true, "minimum": 1, "label": "Hollow"}
	},
	{
		"id": "clip",
		"label": "Clip",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Clip"}
	},
	{
		"id": "clip_to_face",
		"label": "Clip to Face Plane",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "create_arch",
		"label": "Create Structure",
		"category": "Editing",
		"needs_level": true,
		"selection": {}
	},
	{
		"id": "carve",
		"label": "Carve",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Carve"}
	},
	{
		"id": "merge",
		"label": "Merge Brushes",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 2, "label": "Merge"}
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
		"id": "reset_rotation",
		"label": "Reset Rotation",
		"category": "Transform",
		"needs_level": true,
		"selection": {}
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
		"selection": {"brushes_only": true, "minimum": 1, "label": "Move To Floor"}
	},
	{
		"id": "move_to_ceiling",
		"label": "Move to Ceiling",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Move To Ceiling"}
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
		"id": "apply_to_brush",
		"label": "Apply To Brush",
		"category": "Editing",
		"needs_level": false,
		"selection":
		{"brushes_only": true, "minimum": 1, "label": "Apply To Brush", "allow_faces": true}
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
		"id": "entity_io",
		"label": "Entity Io",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Entity Io"}
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
		"selection": {"brushes_only": false, "minimum": 1, "label": "Cycle Variant"}
	},
	{
		"id": "push_to_source",
		"label": "Push To Source",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Push To Source"}
	},
	{
		"id": "propagate_prefab",
		"label": "Propagate Prefab",
		"category": "Editing",
		"needs_level": false,
		"selection": {"brushes_only": false, "minimum": 1, "label": "Propagate Prefab"}
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
		"selection": {}
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
		"selection": {}
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
		"selection": {}
	},
	{
		"id": "paint_confirm_connector",
		"label": "Confirm Paint Connector",
		"category": "Paint",
		"needs_level": true,
		"selection": {}
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


static func needs_level(id: String) -> bool:
	return bool(find(id).get("needs_level", false))


## What the surface guard asks of the selection for `id`, or `{}`. A copy, so a
## caller can change it without changing the table.
static func selection(id: String) -> Dictionary:
	var asked: Dictionary = find(id).get("selection", {})
	return asked.duplicate(true)
