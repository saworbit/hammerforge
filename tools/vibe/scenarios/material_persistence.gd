@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What happens to a material the mapper made, when the level is saved.
##
## The palette can hold two kinds of material: one loaded from a `.tres` on
## disk, and one built in the session. The `.hflevel` writer serializes a
## Resource by its `resource_path`, and the second kind has none.

const LevelIO = preload("res://addons/hammerforge/hflevel_io.gd")


func id() -> String:
	return "material-persistence"


func summary() -> String:
	return "whether a material made in the editor survives a .hflevel save, and what the faces do if it does not"


func run() -> void:
	await _a_runtime_material_through_the_level_file()
	await _mixed_palette()
	await _the_state_round_trip()


func _make(name: String, colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = colour
	return m


func _palette(root: Node3D) -> Array:
	var out: Array = []
	for m in root.get_materials():
		out.append(
			(
				"null"
				if m == null
				else str(m.resource_name if m.resource_name != "" else m.resource_path)
			)
		)
	return out


## Four materials made in the session, applied to faces, saved and loaded.
func _a_runtime_material_through_the_level_file() -> void:
	var root: Node3D = await fresh_root()
	(
		root
		. set_materials(
			[
				_make("brick_red", Color(0.8, 0.2, 0.2)),
				_make("metal_grey", Color(0.5, 0.5, 0.55)),
				_make("wood", Color(0.5, 0.35, 0.15)),
				_make("glass", Color(0.4, 0.7, 0.9, 0.5)),
			]
		)
	)
	var b = box(root, Vector3(128, 128, 128))
	await frame()
	for i in b.faces.size():
		b.faces[i].material_idx = i % 4
	var face_mats: Array = []
	for f in b.faces:
		face_mats.append(f.material_idx)
	note("palette before the save", _palette(root))
	note("face material slots before the save", face_mats)

	var path := "user://vibe_material_persist.hflevel"
	root.save_hflevel(path)
	await HFVibe.settle_save(_tree, root)
	note("saved bytes", HFVibe.file_size(path))

	var loaded: Node3D = await fresh_root("Loaded")
	var ok: bool = loaded.load_hflevel(path)
	await frame()
	note("load_hflevel returned", ok)
	note("palette after the load", _palette(loaded))
	var live := 0
	for m in loaded.get_materials():
		if m != null:
			live += 1
	var back_faces: Array = []
	for lb in loaded.draft_brushes_node.get_children():
		for f in lb.faces:
			back_faces.append(f.material_idx)
	note("face material slots after the load", back_faces)
	# The slots load empty, as the format points at a file and these have none.
	# Since #617 the save warns and records what each one was, by class and name,
	# where it wrote a bare null. Keeping the material itself would be more than
	# that fix did.
	note("live materials after the load", live)
	var marker: Variant = LevelIO.encode_variant(_make("brick_red", Color(0.8, 0.2, 0.2)))
	note("what the save records for a material made in the editor", marker)
	if not (marker is Dictionary and str((marker as Dictionary).get("name", "")) == "brick_red"):
		flag(
			"a material made in the editor is saved with nothing to say what it was",
			"encode_variant() gave %s" % str(marker)
		)


## A palette with both kinds in it, so the slot indices matter.
func _mixed_palette() -> void:
	var root: Node3D = await fresh_root()
	var shipped = load(
		"res://addons/hammerforge/textures/prototypes/materials/proto_checker_red.tres"
	)
	note("a shipped prototype loaded", shipped != null)
	root.set_materials(
		[shipped, _make("runtime_a", Color.RED), shipped, _make("runtime_b", Color.BLUE)]
	)
	var b = box(root, Vector3(64, 64, 64))
	await frame()
	for i in b.faces.size():
		b.faces[i].material_idx = i % 4
	note("mixed palette before", _palette(root))
	var path := "user://vibe_material_mixed.hflevel"
	root.save_hflevel(path)
	await HFVibe.settle_save(_tree, root)
	var loaded: Node3D = await fresh_root("MixedLoaded")
	loaded.load_hflevel(path)
	await frame()
	note("mixed palette after", _palette(loaded))
	note(
		"slot positions are kept",
		"the shipped ones survive in place, so the faces that pointed at 1 and 3 now point at null"
	)


## The undo path uses the same capture, but keeps the objects rather than
## serializing them, so it should not lose anything.
func _the_state_round_trip() -> void:
	var root: Node3D = await fresh_root()
	root.set_materials([_make("a", Color.RED), _make("b", Color.GREEN)])
	await frame()
	note("palette before capture", _palette(root))
	var state: Dictionary = root.capture_state()
	root.set_materials([])
	note("palette after clearing", _palette(root))
	root.restore_state(state)
	await frame()
	note("palette after restore_state", _palette(root))
	var live := 0
	for m in root.get_materials():
		if m != null:
			live += 1
	if live == 2:
		note(
			"undo keeps them",
			(
				"capture_state() holds the Material objects themselves, so the loss is "
				+ "specific to the serialized `.hflevel`, not to the snapshot"
			)
		)
	else:
		flag("capture_state also loses a runtime material", _palette(root))
