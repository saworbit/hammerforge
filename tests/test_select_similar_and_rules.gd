extends GutTest

## Select Similar by what is ticked, and select by a typed rule (#1698). Select
## Similar matched brushes by size alone, so "every brush with this material"
## took a click on each one, and nothing could pick "every light brighter than 2".

const HFSimilar = preload("res://addons/hammerforge/hf_similar.gd")
const HFQuickSelect = preload("res://addons/hammerforge/hf_quick_select.gd")
const HFSelectionFilter = preload("res://addons/hammerforge/ui/hf_selection_filter.gd")
const HFPluginSelectionCommands = preload("res://addons/hammerforge/plugin_selection_commands.gd")
const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

const PREFS := "user://test_select_similar_prefs.json"

var root: LevelRoot
var _saved_prefs_path := ""


class Capture:
	extends RefCounted

	var nodes: Array = []
	var emitted := false
	var message := ""

	func take(p_nodes: Array, _faces: Dictionary) -> void:
		nodes = p_nodes
		emitted = true

	func hear(p_message: String) -> void:
		message = p_message


## Stands in for the plugin while Select Similar runs as a command.
class Host:
	extends RefCounted

	var _user_prefs: Object = null
	var hf_selection: Array = []
	var dock := Toasts.new()
	var applied: Array = []

	func _apply_selection_list(nodes: Array, _additive: bool) -> void:
		applied = nodes


class Toasts:
	extends RefCounted

	var toasts: Array = []

	func show_toast(message: String, _level: int = 0) -> void:
		toasts.append(message)


func before_each() -> void:
	_saved_prefs_path = HFUserPrefs.prefs_path
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	for material_name in ["stone", "brick_red", "wood"]:
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		root.add_material_to_palette(material)


func after_each() -> void:
	HFUserPrefs.prefs_path = _saved_prefs_path
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	root = null


func _box(center: Vector3, slot: int, extra: Dictionary = {}) -> DraftBrush:
	var info := {"shape": 0, "size": Vector3.ONE, "center": center}
	info.merge(extra, true)
	var brush: DraftBrush = root.create_brush_from_info(info)
	for face in brush.faces:
		face.material_idx = slot
	return brush


func _light(energy: float, at: Vector3) -> Node:
	var entity: Node = root._create_entity_from_map({"classname": "light_point", "origin": at})
	entity.entity_data["energy"] = energy
	return entity


func _popup(prefs: Object, selection: Array) -> HFSelectionFilter:
	var popup := HFSelectionFilter.new()
	add_child_autofree(popup)
	popup.set_user_prefs(prefs)
	popup.show_for(root, selection)
	return popup


func _prefs() -> HFUserPrefs:
	var prefs := HFUserPrefs.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefs._defaults()
	return prefs


func test_material_picks_every_brush_wearing_the_first_ones_material():
	var first := _box(Vector3.ZERO, 1)
	var trimmed := _box(Vector3(3, 0, 0), 2)
	trimmed.faces[0].material_idx = 1
	var other := _box(Vector3(6, 0, 0), 2)
	var picked := HFSimilar.brushes(root, [first], ["material"])
	assert_eq(picked, [first, trimmed], "brick on any face is enough")
	assert_false(picked.has(other))
	assert_eq(HFSimilar.brushes(root, [first], ["size"]).size(), 3, "size alone took them all")


func test_each_brush_key_asks_for_its_own_likeness():
	var plain := _box(Vector3.ZERO, 0)
	var round := _box(Vector3(3, 0, 0), 0, {"shape": LevelRoot.BrushShape.CYLINDER})
	var cut := _box(Vector3(6, 0, 0), 0, {"operation": CSGShape3D.OPERATION_SUBTRACTION})
	var upper := _box(Vector3(9, 0, 0), 0)
	root.create_visgroup("upper")
	root.add_selection_to_visgroup("upper", [upper])
	var grouped := _box(Vector3(12, 0, 0), 0)
	root.group_selection("crates", [grouped])
	var stair := _box(Vector3(15, 0, 0), 0)
	stair.set_meta(HFGeneratorSystem.GENERATOR_META, "stairs_1")
	var trigger := _box(Vector3(18, 0, 0), 0)
	trigger.set_meta("brush_entity_class", "trigger_once")
	assert_false(HFSimilar.brushes(root, [plain], ["shape"]).has(round), "shape")
	assert_eq(HFSimilar.brushes(root, [cut], ["operation"]), [cut], "add or cut")
	assert_eq(HFSimilar.brushes(root, [upper], ["visgroup"]), [upper], "visgroup")
	assert_eq(HFSimilar.brushes(root, [grouped], ["group"]), [grouped], "group")
	assert_eq(HFSimilar.brushes(root, [stair], ["structure"]), [stair], "structure")
	assert_eq(HFSimilar.brushes(root, [trigger], ["brush_entity"]), [trigger], "entity class")
	assert_eq(
		HFSimilar.brushes(root, [plain], ["shape", "operation", "brush_entity"]).size(),
		4,
		"every key must agree: plain, upper, grouped and the stair"
	)


func test_faces_can_ask_for_the_same_uv_scale():
	var a := _box(Vector3.ZERO, 1)
	var b := _box(Vector3(3, 0, 0), 1)
	b.faces[2].uv_scale = Vector2(2, 2)
	root.face_selection = {str(a.brush_id): [2]}
	var by_material := HFSimilar.faces(root, ["material"])
	assert_eq((by_material[str(b.brush_id)] as Array).size(), 6, "every face of b is brick")
	var by_scale := HFSimilar.faces(root, ["material", "uv_scale"])
	assert_false((by_scale[str(b.brush_id)] as Array).has(2), "but one is scaled")


func test_entities_match_by_class_and_by_a_named_property():
	var dim := _light(1.0, Vector3.ZERO)
	var also_dim := _light(1.0, Vector3(3, 0, 0))
	var bright := _light(3.0, Vector3(6, 0, 0))
	assert_eq(HFSimilar.entities(root, [dim], ["class"], "").size(), 3, "every light")
	assert_eq(
		HFSimilar.entities(root, [dim], ["class", "property"], "energy"),
		[dim, also_dim],
		"the lights as bright as it"
	)
	assert_eq(HFSimilar.entities(root, [dim], ["property"], ""), [], "Property needs a name")
	assert_true(is_instance_valid(bright))


func test_the_ticks_are_kept_across_a_restart_and_shift_s_uses_them():
	HFUserPrefs.prefs_path = PREFS
	var prefs := HFUserPrefs.load_prefs()
	var first := _box(Vector3.ZERO, 1)
	var trimmed := _box(Vector3(3, 0, 0), 2)
	trimmed.faces[0].material_idx = 1
	_box(Vector3(6, 0, 0), 2)
	var popup := _popup(prefs, [first])
	assert_true(popup._similar_checks["brush"]["size"].button_pressed, "size is ticked to start")
	popup._similar_checks["brush"]["size"].button_pressed = false
	popup._similar_checks["brush"]["material"].button_pressed = true
	var again := HFUserPrefs.load_prefs()
	assert_eq(HFSimilar.keys_for(again, "brush"), ["material"], "read back from the file")
	var host := Host.new()
	host._user_prefs = again
	host.hf_selection = [first]
	HFPluginSelectionCommands.select_similar(host, root)
	assert_eq(host.applied, [first, trimmed], "Shift+S matches on material now")
	assert_eq(host.dock.toasts.back(), "Selected 2 similar brushes")


func test_nothing_ticked_asks_for_a_tick():
	var prefs := _prefs()
	prefs.set_pref("similar_brush_keys", [])
	var host := Host.new()
	host._user_prefs = prefs
	host.hf_selection = [_box(Vector3.ZERO, 1)]
	HFPluginSelectionCommands.select_similar(host, root)
	assert_eq(host.applied, [], "nothing is selected")
	assert_eq(host.dock.toasts.back(), "Tick what similar brushes match on in Selection Filters")


func test_quick_select_picks_exactly_the_bright_lights():
	_light(1.0, Vector3.ZERO)
	var bright := _light(2.5, Vector3(3, 0, 0))
	var brighter := _light(4.0, Vector3(6, 0, 0))
	root._create_entity_from_map({"classname": "ambient_generic", "origin": Vector3(9, 0, 0)})
	var popup := _popup(_prefs(), [])
	var cap := Capture.new()
	popup.filter_applied.connect(cap.take)
	popup._quick_kind.select(1)
	popup._on_quick_kind_selected(1)
	popup._quick_rule.text = "class is light_point and energy > 2"
	popup.quick_select(HFQuickSelect.Mode.REPLACE)
	assert_eq(cap.nodes, [bright, brighter])


func test_take_away_add_and_in_selection():
	var solid := _box(Vector3.ZERO, 1)
	var cut := _box(Vector3(3, 0, 0), 1, {"operation": CSGShape3D.OPERATION_SUBTRACTION})
	var wood := _box(Vector3(6, 0, 0), 2)
	var popup := _popup(_prefs(), [solid, cut])
	var cap := Capture.new()
	popup.filter_applied.connect(cap.take)
	popup._quick_rule.text = "operation is cut"
	popup.quick_select(HFQuickSelect.Mode.TAKE_AWAY)
	assert_eq(cap.nodes, [solid], "the cut is taken out")
	popup._quick_rule.text = "material is wood"
	popup.quick_select(HFQuickSelect.Mode.ADD)
	assert_eq(cap.nodes, [solid, cut, wood], "added to what was selected")
	popup._quick_within.button_pressed = true
	popup._quick_rule.text = "material is brick_red and operation is add"
	popup.quick_select(HFQuickSelect.Mode.REPLACE)
	assert_eq(cap.nodes, [solid], "looked for among the selection only")


func test_a_rule_that_cannot_be_read_says_why_and_selects_nothing():
	var popup := _popup(_prefs(), [])
	var cap := Capture.new()
	popup.filter_applied.connect(cap.take)
	popup.filter_reported.connect(cap.hear)
	for case in [
		["energy >", "Give energy a value"],
		[
			"energy > 2",
			"A brush has no energy; it takes %s" % ", ".join(HFQuickSelect.properties("brush"))
		],
		["operation > 2", "operation takes is, is not or matches"],
		["operation is sideways", "operation is add or cut"],
		["material is marble", "No material in the palette is named marble"],
		["", "Type a rule, such as %s" % HFQuickSelect.EXAMPLES["brush"]],
	]:
		popup._quick_rule.text = case[0]
		popup.quick_select(HFQuickSelect.Mode.REPLACE)
		assert_eq(cap.message, case[1], case[0])
	assert_false(cap.emitted, "and nothing was selected")


func test_the_rule_reads_names_with_patterns_and_is_not():
	var door := _box(Vector3.ZERO, 0)
	door.name = "door_main"
	var other := _box(Vector3(3, 0, 0), 0)
	other.name = "wall"
	var read := HFQuickSelect.parse("brush", 'name matches "door_*"')
	assert_true(read["ok"])
	assert_eq(HFQuickSelect.pick(root, "brush", read["conditions"])["nodes"], [door])
	read = HFQuickSelect.parse("brush", "name is not door_*")
	assert_eq(HFQuickSelect.pick(root, "brush", read["conditions"])["nodes"], [other])
