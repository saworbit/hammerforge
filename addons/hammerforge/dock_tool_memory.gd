@tool
class_name HFDockToolMemory
extends RefCounted
## The Build tab's own settings and the Structure section's, kept in the user
## preferences between sessions (#1406).
##
## A mapper who builds with 0.2 m hollow walls, cylinders of 24 sides or a tuned
## arch set them again every session, because each control started at its
## default. Each one listed here is written as the mapper changes it and put back
## when the dock is handed the preferences, held to the control's own range on
## the way in: a value edited out of range in the file comes back at the nearer
## end, with a warning naming the file and the key. The tools' own settings are
## kept by `HFToolRegistry`, Grid Snap was a preference already, and the brush
## size is the level's.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const LevelRootType = preload("level_root.gd")
const DraftBrush = preload("brush_instance.gd")
const HFDockBrushHandler = preload("dock_brush_handler.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFUserPrefs = preload("hf_user_prefs.gd")
const HFSnapSystem = preload("hf_snap_system.gd")
@warning_ignore_restore("shadowed_global_identifier")

## What each Build tab setting is kept under in the file.
const SHAPE := "shape"
const SIDES_PYRAMID := "sides_pyramid"
const SIDES_ROUND := "sides_round"
const CUTOUT := "cutout"
## A change of the Sides box. It is kept under the count of the kind of shape in
## the Shape list, as the dock keeps one count for a pyramid and one for a round
## shape (#1085).
const SIDES := "sides"
## Snap toggle -> the dock's button for it and the snap mode it switches.
const SNAP_TOGGLES := {
	"snap_grid": ["snap_grid_btn", HFSnapSystem.SnapMode.GRID],
	"snap_vertex": ["snap_vertex_btn", HFSnapSystem.SnapMode.VERTEX],
	"snap_center": ["snap_center_btn", HFSnapSystem.SnapMode.CENTER],
	"snap_edge": ["snap_edge_btn", HFSnapSystem.SnapMode.EDGE],
	"snap_perp": ["snap_perp_btn", HFSnapSystem.SnapMode.PERPENDICULAR],
}
## Number setting -> the dock's box for it. Hollow's wall, and the Bevel and Face
## Inset boxes beside it.
const SPINS := {
	"hollow_thickness": "hollow_thickness",
	"bevel_segments": "_bevel_segments_spin",
	"bevel_radius": "_bevel_radius_spin",
	"inset_distance": "_bevel_inset_dist_spin",
	"inset_height": "_bevel_inset_height_spin",
}


## Note what every control starts at, for Reset Tool Settings, and listen for the
## mapper changing them. Called once the dock has built its controls, before it
## is handed the preferences.
static func watch(dock: Object) -> void:
	var defaults := {
		SHAPE: dock.active_shape,
		SIDES: (dock._kept_sides as Dictionary).duplicate(),
		CUTOUT: dock.mode_subtract.button_pressed if dock.mode_subtract else false,
	}
	var listener := Callable(dock, "_on_build_setting_changed")
	if dock.sides_spin:
		dock.sides_spin.value_changed.connect(listener.bind(SIDES))
	if dock.mode_subtract:
		# Pressing Solid lets go of Cutout, so this one hears both.
		dock.mode_subtract.toggled.connect(listener.bind(CUTOUT))
	for key in SNAP_TOGGLES:
		var button: Button = dock.get(SNAP_TOGGLES[key][0])
		if button:
			defaults[key] = button.button_pressed
			button.toggled.connect(listener.bind(key))
	for key in SPINS:
		var spin: SpinBox = dock.get(SPINS[key])
		if spin:
			defaults[key] = spin.value
			spin.value_changed.connect(listener.bind(key))
	dock._build_defaults = defaults


## Put back what the preferences kept, without any of it reading as the mapper
## changing a control.
static func apply(dock: Object) -> void:
	var prefs: HFUserPrefs = dock._user_prefs
	if prefs == null:
		return
	dock._restoring_tool_memory = true
	_apply_build(dock, prefs.get_build_settings())
	_apply_structure(dock, prefs.get_structure_settings())
	dock._restoring_tool_memory = false
	push_snap_modes(dock)


static func _apply_build(dock: Object, saved: Dictionary) -> void:
	# The shape first: leaving one shape keeps the Sides box's count for its kind,
	# which would overwrite the count put back for that kind below.
	if saved.has(SHAPE):
		var shape_name = HFUserPrefs.held_to(_where(SHAPE), {"type": TYPE_STRING}, saved[SHAPE], "")
		var shape_value := shape_for(str(shape_name))
		if shape_value >= 0:
			dock._set_active_shape(shape_value)
		elif str(shape_name) != "":
			_warn_unknown(_where(SHAPE), str(shape_name), "a brush shape")
	var most := int(dock.sides_spin.max_value) if dock.sides_spin else 64
	for entry in [
		[SIDES_PYRAMID, "pyramid", 3], [SIDES_ROUND, "round", DraftBrush.MIN_ROUND_SIDES]
	]:
		if saved.has(entry[0]):
			var rule := {"type": TYPE_INT, "min": entry[2], "max": most}
			dock._kept_sides[entry[1]] = HFUserPrefs.held_to(
				_where(entry[0]), rule, saved[entry[0]], dock._kept_sides[entry[1]]
			)
	_show_kept_sides(dock)
	if saved.has(CUTOUT):
		var cut = HFUserPrefs.held_to(_where(CUTOUT), {"type": TYPE_BOOL}, saved[CUTOUT], null)
		if cut is bool:
			_set_cutout(dock, cut)
	for key in SNAP_TOGGLES:
		var button: Button = dock.get(SNAP_TOGGLES[key][0])
		if button and saved.has(key):
			var on = HFUserPrefs.held_to(_where(key), {"type": TYPE_BOOL}, saved[key], null)
			if on is bool:
				button.set_pressed_no_signal(on)
	for key in SPINS:
		var spin: SpinBox = dock.get(SPINS[key])
		if spin and saved.has(key):
			var rule := {"type": TYPE_FLOAT, "min": spin.min_value, "max": spin.max_value}
			spin.set_value_no_signal(HFUserPrefs.held_to(_where(key), rule, saved[key], spin.value))


## Each kept type's fields, held to that type's schema, and the type last chosen.
static func _apply_structure(dock: Object, saved: Dictionary) -> void:
	var known := HFGeneratorSystem.structure_types()
	var by_type = saved.get("fields", {})
	if not (by_type is Dictionary):
		_warn_unknown(_structure_where("fields"), str(by_type), "a set of structure settings")
		by_type = {}
	for type in by_type:
		var type_name := str(type)
		if not known.has(type_name):
			_warn_unknown(_structure_where("fields/" + type_name), type_name, "a structure type")
			continue
		var fields = by_type[type]
		if fields is Dictionary:
			dock._structure_kept[type_name] = held_structure_fields(type_name, fields)
	if saved.has("type"):
		var where := _structure_where("type")
		var type_name := str(HFUserPrefs.held_to(where, {"type": TYPE_STRING}, saved["type"], ""))
		if known.has(type_name):
			HFDockBrushHandler._select_type(dock, type_name)
		elif type_name != "":
			_warn_unknown(where, type_name, "a structure type")
	HFDockBrushHandler.rebuild_structure_fields(dock)
	dock.refresh_structure_section()


## The fields one structure type kept, each held to its schema entry. A key the
## type does not have is left out.
static func held_structure_fields(type: String, fields: Dictionary) -> Dictionary:
	var out := {}
	for field_def in HFGeneratorSystem.settings_schema(type):
		if not (field_def is Dictionary):
			continue
		var key := str(field_def.get("key", ""))
		if key == "" or not fields.has(key):
			continue
		var where := _structure_where("fields/%s/%s" % [type, key])
		var value = HFUserPrefs.held_to(where, structure_rule(field_def), fields[key], null)
		if value != null:
			out[key] = value
	return out


## What a structure field has to be, as `HFUserPrefs.held_to()` reads a rule.
static func structure_rule(field_def: Dictionary) -> Dictionary:
	var rule := {}
	match str(field_def.get("type", HFGeneratorSchema.TYPE_FLOAT)):
		HFGeneratorSchema.TYPE_BOOL:
			return {"type": TYPE_BOOL}
		HFGeneratorSchema.TYPE_ENUM:
			var options: Array = Array(field_def.get("options", []))
			return {"type": TYPE_INT, "min": 0, "max": maxi(0, options.size() - 1)}
		HFGeneratorSchema.TYPE_INT:
			rule = {"type": TYPE_INT}
		_:
			rule = {"type": TYPE_FLOAT}
	if field_def.has("min"):
		rule["min"] = field_def["min"]
	if field_def.has("max"):
		rule["max"] = field_def["max"]
	return rule


## Keep the Build tab setting `key` as the dock now shows it.
static func remember(dock: Object, key: String) -> void:
	var prefs: HFUserPrefs = dock._user_prefs
	if prefs == null or dock._restoring_tool_memory:
		return
	if key == SHAPE:
		var shape_name = LevelRootType.BrushShape.find_key(dock.active_shape)
		if shape_name == null:
			return
		# Leaving a shape kept the Sides box's count for its kind on the way.
		(
			prefs
			. set_build_settings(
				{
					SHAPE: str(shape_name),
					SIDES_PYRAMID: int(dock._kept_sides["pyramid"]),
					SIDES_ROUND: int(dock._kept_sides["round"]),
				}
			)
		)
	elif key == SIDES:
		var kind: String = dock._sides_kind(dock.active_shape)
		if kind != "" and dock.sides_spin:
			var kept_as := SIDES_PYRAMID if kind == "pyramid" else SIDES_ROUND
			prefs.set_build_settings({kept_as: int(dock.sides_spin.value)})
	elif key == CUTOUT:
		prefs.set_build_settings({CUTOUT: bool(dock.mode_subtract.button_pressed)})
	elif SNAP_TOGGLES.has(key):
		var button: Button = dock.get(SNAP_TOGGLES[key][0])
		if button:
			prefs.set_build_settings({key: button.button_pressed})
	elif SPINS.has(key):
		var spin: SpinBox = dock.get(SPINS[key])
		if spin:
			prefs.set_build_settings({key: spin.value})


## Keep the type the mapper chose in the Structure section.
static func remember_structure_type(dock: Object) -> void:
	var prefs: HFUserPrefs = dock._user_prefs
	if prefs == null or dock._restoring_tool_memory:
		return
	prefs.set_structure_type(HFDockBrushHandler.structure_type(dock))


## Keep the Structure section's fields for the type they belong to. Held for the
## session even with no preferences, so switching type and back finds them.
static func remember_structure_fields(dock: Object) -> void:
	if dock._restoring_tool_memory:
		return
	var type := HFDockBrushHandler.structure_type(dock)
	var fields := HFDockBrushHandler.collect_structure_settings(dock)
	dock._structure_kept[type] = fields
	var prefs: HFUserPrefs = dock._user_prefs
	if prefs != null:
		prefs.set_structure_fields(type, fields)


## Every setting kept here and every tool's back to its default, and nothing left
## in the preferences to bring back.
static func reset(dock: Object) -> void:
	var defaults: Dictionary = dock._build_defaults
	dock._restoring_tool_memory = true
	dock._set_active_shape(int(defaults.get(SHAPE, LevelRootType.BrushShape.BOX)))
	var sides = defaults.get(SIDES, null)
	if sides is Dictionary:
		dock._kept_sides = (sides as Dictionary).duplicate()
	_show_kept_sides(dock)
	_set_cutout(dock, bool(defaults.get(CUTOUT, false)))
	for key in SNAP_TOGGLES:
		var button: Button = dock.get(SNAP_TOGGLES[key][0])
		if button and defaults.has(key):
			button.set_pressed_no_signal(bool(defaults[key]))
	for key in SPINS:
		var spin: SpinBox = dock.get(SPINS[key])
		if spin and defaults.has(key):
			spin.set_value_no_signal(float(defaults[key]))
	dock._structure_kept.clear()
	if dock.structure_type_option and dock.structure_type_option.item_count > 0:
		dock.structure_type_option.selected = 0
	HFDockBrushHandler.rebuild_structure_fields(dock)
	dock.refresh_structure_section()
	dock._restoring_tool_memory = false
	push_snap_modes(dock)
	# The tools are listening for this, through the registry.
	if dock._user_prefs:
		dock._user_prefs.reset_tool_settings()


## The snap toggles to the level. A level starts each session snapping to the
## grid alone, so the toggles the dock shows are handed to every level it adopts.
static func push_snap_modes(dock: Object) -> void:
	var root = dock.level_root
	if root == null or not is_instance_valid(root) or root.get("snap_system") == null:
		return
	for key in SNAP_TOGGLES:
		var button: Button = dock.get(SNAP_TOGGLES[key][0])
		if button:
			root.snap_system.set_mode(int(SNAP_TOGGLES[key][1]), button.button_pressed)


## The shape a name in the Shape list stands for, or -1. A polygon's or a path's
## brush is CUSTOM, which nothing draws, so it is not one.
static func shape_for(shape_name: String) -> int:
	if shape_name == "CUSTOM" or not LevelRootType.BrushShape.has(shape_name):
		return -1
	return int(LevelRootType.BrushShape[shape_name])


## The Sides box shows the count kept for the kind of shape in the Shape list.
static func _show_kept_sides(dock: Object) -> void:
	var kind: String = dock._sides_kind(dock.active_shape)
	if kind != "" and dock.sides_spin:
		dock._show_sides(kind, int(dock._kept_sides[kind]))


static func _set_cutout(dock: Object, cut: bool) -> void:
	var button: Button = dock.mode_subtract if cut else dock.mode_add
	if button:
		button.button_pressed = true


static func _where(key: String) -> String:
	return "%s/%s" % [HFUserPrefs.BUILD_SETTINGS, key]


static func _structure_where(key: String) -> String:
	return "%s/%s" % [HFUserPrefs.STRUCTURE_SETTINGS, key]


static func _warn_unknown(where: String, value: String, what: String) -> void:
	HFLog.warn(
		(
			"%s: '%s' is %s, which is not %s. The default is used."
			% [HFUserPrefs.PREFS_PATH, where, value, what]
		)
	)
