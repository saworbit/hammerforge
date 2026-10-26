@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Compare says about each edit a mapper makes between two saves.
##
## `HFLevelCompare.compare()` is what the Console's Compare tab, the viewport
## outlines and `tools/compare_levels.gd` all read, and the CLI exits 0 when it
## says nothing changed, as `diff` does. So the question for every edit is the
## same: does the compare see it, and does it name it right? Each case takes the
## level as it is, makes one edit through the LevelRoot API, and compares the two
## payloads. The first case goes through a real `.hflevel` file, as the tab does.

const HFLevelCompare = preload("res://addons/hammerforge/hf_level_compare.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")

const PATH := "user://vibe_level_compare.hflevel"
## The cases #1982 already reports Compare saying nothing about.
const FILED_SILENT := [
	"brush entity renamed",
	"point entity authored name",
	"point entity node renamed",
	"brush renamed",
	"brush put in a visgroup",
	"second brush put in a visgroup that skips the bake",
	"brushes grouped",
]

var _root: Node3D = null
## What the last case compared to.
var _last: Dictionary = {}


func id() -> String:
	return "level-compare"


func summary() -> String:
	return "what Compare reports for moved, turned, resized, retextured, added, removed and renamed brushes and entities"


func expected_issues() -> Array[int]:
	return [1982, 1989, 1992]


func run() -> void:
	_root = await fresh_root("CompareLevel")
	_root.hflevel_autosave_enabled = false
	var wall = _root.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 3, 0.5), "center": Vector3(0, 1.5, 0), "brush_id": "wall"}
	)
	var crate = _root.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 1, 1), "center": Vector3(4, 0.5, 2), "brush_id": "crate"}
	)
	var door = _root.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 2, 0.2), "center": Vector3(-4, 1, 0), "brush_id": "door"}
	)
	_root.tie_brushes_to_entity(["door"], "func_door", "door_1")
	var lamp: Node3D = (
		_root
		. entity_system
		. restore_entity_from_info(
			{
				"name": "lamp",
				"entity_type": "light_point",
				"properties": {"energy": 1.0},
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 3)),
			}
		)
	)
	var button: Node3D = (
		_root
		. entity_system
		. restore_entity_from_info(
			{
				"name": "button",
				"entity_type": "func_button",
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(2, 1, 3)),
			}
		)
	)
	_root.add_entity_output(button, "OnPressed", "door_1", "Open")
	_root.material_manager.add_material(StandardMaterial3D.new())
	var brick := StandardMaterial3D.new()
	brick.resource_name = "brick"
	_root.material_manager.add_material(brick)
	await frame()

	await _through_the_file()

	# Edits that already have a sentence. Each is checked for the words the guide
	# promises, so a change in wording that loses the edit is noticed.
	await _case(
		"move", func(): _root.nudge_brushes_by_id(["crate"], Vector3(0, 0.5, 0)), ["moved 0.5 m up"]
	)
	_texture_lock_noise("a 0.5 m nudge up", _last)
	await _case(
		"turn",
		func(): _root.rotate_managed_nodes(["crate"], [], 1, 90.0, crate.global_position),
		["turned"]
	)
	_texture_lock_noise("a quarter turn", _last)
	await _case("resize", func(): crate.size = Vector3(2, 1, 1), ["resized to 2 x 1 x 1"])
	await _case(
		"retexture",
		func(): _root.assign_material_to_faces_by_id("wall", [0], 1),
		["material changed from none to brick"]
	)
	await _case(
		"entity setting",
		func(): _root.set_entity_property(lamp, "energy", 3.0),
		["entity 'lamp'", "energy changed"]
	)
	await _case(
		"entity moved",
		func(): lamp.global_position += Vector3(1, 0, 0),
		["entity 'lamp'", "moved 1 m along +x"]
	)
	await _case(
		"wire added",
		func(): _root.add_entity_output(button, "OnPressed", "lamp", "Toggle"),
		["entity 'button'", "wires: 1 added"]
	)
	var spare = null
	await _case(
		"brush added",
		func():
			spare = _root.create_brush_from_info(
				{
					"shape": 0,
					"size": Vector3(1, 1, 1),
					"center": Vector3(8, 0.5, 8),
					"brush_id": "spare"
				}
			),
		["added"]
	)
	await _case("brush removed", func(): _root.delete_brush_by_id("spare"), ["removed"])

	# Edits whose words the guide does not spell out. Each should change the
	# answer from "No changes": the CLI exits 0 on that, and the tab draws the
	# brush faded as unchanged.
	await _case(
		"brush entity renamed",
		func(): _root.tie_brushes_to_entity(["door"], "func_door", "vault_door"),
		[],
		"the door the button's wire names (door_1) is now vault_door, so the wire aims at nothing; Compare's _brush_changes reads the class, the settings and the wires of a brush entity but not its name (entity_name)"
	)
	await _case(
		"point entity authored name",
		func(): lamp.set_meta("entity_name", "hall_lamp"),
		[],
		"the name a wire is aimed by changed; _entity_changes never reads entity_name"
	)
	await _case(
		"point entity node renamed",
		func(): lamp.name = "ceiling_lamp",
		[],
		"matched by class and place as the same entity, and then nothing says its name changed"
	)
	await _case(
		"brush renamed",
		func(): wall.name = "north_wall",
		[],
		"a brush's record carries its name, and nothing compares it"
	)
	_root.create_visgroup("detail")
	await _case(
		"brush put in a visgroup",
		func(): _root.add_selection_to_visgroup("detail", [crate]),
		[],
		"visgroup records hold visible/bake/locked/cast_shadow only, so membership, which decides what Hide and Bake skip, is never compared"
	)
	_root.set_visgroup_bakes("detail", false)
	await frame()
	await _case(
		"second brush put in a visgroup that skips the bake",
		func(): _root.add_selection_to_visgroup("detail", [wall]),
		[],
		"this wall is now left out of every bake, and the compare reads 'No changes'"
	)

	await _case(
		"brushes grouped",
		func(): _root.group_selection("room", [wall, crate]),
		[],
		"a brush record carries group_id and nothing compares it"
	)
	await _case(
		"solid made a cut",
		func(): crate.operation = CSGShape3D.OPERATION_SUBTRACTION,
		["now a cut"]
	)
	# A paint layer by the name the mapper gave it, coming and going.
	await _case(
		"paint layer added and named",
		func():
			_root.add_paint_layer()
			_root.rename_paint_layer(_root.get_paint_layer_names().size() - 1, "Upper Floor"),
		["paint layer 'Upper Floor': added"]
	)
	await _case(
		"paint layer removed",
		func():
			_root.set_active_paint_layer(_root.get_paint_layer_names().size() - 1)
			_root.remove_active_paint_layer(),
		["paint layer 'Upper Floor': removed"]
	)

	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	await drop_root(_root)


## A nudge or a turn with texture lock on, the default, keeps each face's
## texture where it was on the brush by changing its offset or rotation. The
## compare reads the raw numbers, so each of those faces reads as "texture moved"
## and counts as a changed face.
func _texture_lock_noise(what: String, result: Dictionary) -> void:
	if result.is_empty():
		return
	var faces := int(result["counts"]["faces"])
	note("%s with texture lock %s: faces counted as changed" % [what, _root.texture_lock], faces)
	if _root.texture_lock and faces > 0:
		known(
			1989,
			"%s with texture lock on reads as a texture edit on %d faces" % [what, faces],
			(
				"the texture stayed where it was on the brush, which is what texture lock is for, and Compare says '%s'. _face_changes compares uv_offset/uv_rotation as stored, which texture lock rewrites on every move"
				% result["lines"][0]
			)
		)


## The level against its own saved file, and one edit through it.
func _through_the_file() -> void:
	_root.save_hflevel(PATH, true)
	if not await HFVibe.settle_save(_tree, _root):
		flag("the save never finished", PATH)
		return
	var read: Dictionary = _root.file_system.read_hflevel(PATH)
	if not bool(read.get("ok", false)):
		flag("the saved level does not read", read.get("error", ""))
		return
	var bundle: Dictionary = read["bundle"]
	var same := HFLevelCompare.compare(bundle, _now())
	note("against its own saved file", "; ".join(same["lines"]))
	if same["lines"] != PackedStringArray(["No changes"]):
		flag("a level differs from its own saved file", "; ".join(same["lines"]))
	_root.nudge_brushes_by_id(["wall"], Vector3(0, 0, -2))
	await frame()
	var moved := HFLevelCompare.compare(bundle, _now())
	note("one nudge against the file", "; ".join(moved["lines"]))
	if not "; ".join(moved["lines"]).contains("moved 2 m along -z"):
		flag("a 2 m nudge along -z is not named", "; ".join(moved["lines"]))
	_root.nudge_brushes_by_id(["wall"], Vector3(0, 0, 2))
	await frame()


func _now() -> Dictionary:
	return _root.state_system.capture_hflevel_payload()


## Compare before and after `edit`. `words` must all be in the lines; with no
## words, the case only asks that something was said, and `why` is the reason
## given when nothing was.
func _case(label: String, edit: Callable, words: Array, why: String = "") -> void:
	var before := _now()
	edit.call()
	await frame()
	var after := _now()
	var result := HFLevelCompare.compare(before, after)
	_last = result
	var text := "; ".join(result["lines"])
	note("%s" % label, text)
	if words.is_empty():
		if result["lines"] == PackedStringArray(["No changes"]):
			if FILED_SILENT.has(label):
				known(1982, "Compare says 'No changes' after: %s" % label, why)
			else:
				flag("Compare says 'No changes' after: %s" % label, why)
		return
	for word in words:
		if not text.contains(str(word)):
			if label == "paint layer removed":
				known(1992, "Compare does not say '%s' after: %s" % [word, label], text)
			else:
				flag("Compare does not say '%s' after: %s" % [word, label], text)
			return
	# The summary's counts against the lines it heads.
	var counts: Dictionary = result["counts"]
	var total := 0
	for kind in counts:
		total += int(counts[kind])
	if total == 0:
		flag("the summary counts nothing for: %s" % label, text)
