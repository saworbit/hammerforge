@tool
extends SceneTree

## Authors `addons/hammerforge/data/reference_map.hflevel`.
##
## The five shipped examples in `example_levels.json` each demonstrate one
## feature, and the format that file speaks carries brush shape, position, size
## and operation plus point entities. It cannot express a material, a UV, a tie,
## a wire, a visgroup, a navmesh or an occluder, so none of the examples is a
## level with those things in it at once (#710).
##
## This builds one and saves it as a `.hflevel`, the format that can hold all of
## it. The saved file is the deliverable and it is committed. This script exists
## so the map can be rebuilt and reviewed as a diff rather than landing as an
## opaque blob nobody can regenerate.
##
##     godot --headless -s res://tools/build_reference_map.gd --path .
##
## The `reference-map` scenario then loads the committed file and checks it still
## validates, bakes and exports. That check is the reason the file is worth
## committing rather than generating on the fly: every other save and load check
## in the repo reads a file the same build just wrote, so nothing anywhere
## notices when a format change stops last release's file from loading.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

const OUT_PATH := "res://addons/hammerforge/data/reference_map.hflevel"

## The scale the project settled on in #625: the player is 1.6 units high, the
## grid snaps at 0.5 and a drawn brush is 2 units. A 4-high hall is a hall you
## can see the ceiling of.
const HALL := Vector3(14, 4, 14)
const WALL := 0.25
const WEST := Vector3(-11, 2, 0)
const EAST := Vector3(11, 2, 0)
const DOOR := Vector2(2.0, 2.5)

## One texture scale for the whole map, so an offset taken from world space lines
## two surfaces up wherever they meet.
const UV_SCALE := Vector2(0.5, 0.5)

## What each kind of brush is made of, as `[floor, wall, ceiling]` prototype
## material names. A mapper picks these per surface, not per brush, which is why
## the walls of the corridor read as a different place to the walls of a hall.
const SURFACES := {
	"shell": ["checker_grey", "brick_brown", "solid_grey"],
	"corridor": ["checker_orange", "brick_grey", "solid_blue"],
	"pillar": ["stripes_horizontal_grey", "stripes_horizontal_grey", "stripes_horizontal_grey"],
	"beam": ["solid_brown", "solid_brown", "solid_brown"],
	"trim": ["solid_orange", "solid_orange", "solid_orange"],
	"stair": ["checker_brown", "checker_brown", "checker_brown"],
	"crate": ["diamond_yellow", "diamond_yellow", "diamond_yellow"],
	"door": ["solid_red", "solid_red", "solid_red"],
	"frame": ["solid_yellow", "solid_yellow", "solid_yellow"],
	"button": ["solid_green", "solid_green", "solid_green"],
	"trigger": ["hex_cyan", "hex_cyan", "hex_cyan"],
}

var level: Node3D
var _made: Array[String] = []

## Brush id to the entry in `SURFACES` it is textured from.
var _kind: Dictionary = {}

## Prototype material name to its palette slot, resolved once after the palette
## is loaded. Looked up by name rather than by index so a reordered palette moves
## the map's materials with it instead of silently retexturing the level.
var _slots: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	level = Node3D.new()
	level.name = "ReferenceMap"
	level.set_script(LevelRootScript)
	# Before add_child, or `_ready()` has already queued a playtest.
	level.auto_spawn_player = false
	get_root().add_child(level)
	await process_frame

	_palette()
	_wing(WEST, "west_wing")
	_wing(EAST, "east_wing")
	_corridor()
	await process_frame
	_doorways()
	await process_frame
	_colonnade(WEST)
	_colonnade(EAST)
	_beams(WEST)
	_beams(EAST)
	_skirting(WEST)
	_skirting(EAST)
	_stairs()
	_crates()
	_door_frame()
	await process_frame
	_entities()
	_texture()
	_bake_options()
	await process_frame

	_report()
	var written: int = level.save_hflevel(OUT_PATH, true)
	print("save_hflevel returned %s" % written)
	print("save settled: %s" % [await _settle_save()])
	print("file bytes: %d" % _file_size(OUT_PATH))
	quit()


func _report() -> void:
	print("brushes: %d" % _brush_nodes().size())
	print("entities: %d" % level.get_entity_count())
	var report: Dictionary = level.validate_level()
	var issues = report.get("issues", [])
	print("validate issues: %d %s" % [issues.size(), issues])
	var tied := 0
	var wires := 0
	var mats: Dictionary = {}
	for b in _brush_nodes():
		if str(b.get_meta("brush_entity_class", "")) != "":
			tied += 1
		wires += (b.get_meta("entity_io_outputs", []) as Array).size()
		for f in b.faces:
			mats[int(f.material_idx)] = true
	if level.entities_node:
		for e in level.entities_node.get_children():
			wires += (e.get_meta("entity_io_outputs", []) as Array).size()
	print("tied brushes: %d" % tied)
	print("io connections: %d" % wires)
	print("distinct material slots in use: %d" % mats.keys().size())


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


func _box(size: Vector3, centre: Vector3, kind: String) -> Node:
	var made = level.create_brush_from_info({"shape": 0, "size": size, "center": centre})
	if made:
		var bid := str(made.brush_id)
		_made.append(bid)
		_kind[bid] = kind
	return made


func _brush_nodes() -> Array:
	var out: Array = []
	if not level.draft_brushes_node:
		return out
	for child in level.draft_brushes_node.get_children():
		if child.get("brush_id") != null:
			out.append(child)
	return out


## A hall: a solid box shelled into six walls, then put in a visgroup of its own.
##
## A visgroup per wing is what a mapper reaches for when the far end of the level
## is in the way, and it is one of the records `example_levels.json` has no room
## for.
func _wing(centre: Vector3, visgroup: String) -> void:
	var mark := _made.size()
	var solid = _box(HALL, centre, "shell")
	var result = level.hollow_brush_by_id(str(solid.brush_id), WALL)
	if not result.ok:
		push_error("reference map: hollowing %s failed: %s" % [visgroup, result.user_text()])
	# The hollow replaces the solid with six walls, so the ids that matter are
	# whatever is in the level now rather than the one id `_box` recorded.
	var ids := _shell_ids_since(mark)
	level.create_visgroup(visgroup)
	level.add_selection_to_visgroup(visgroup, _nodes_for(ids))


## Floor, ceiling and two walls of the run between the halls.
func _corridor() -> void:
	var mark := _made.size()
	var length := EAST.x - WEST.x - HALL.x
	var w := DOOR.x + WALL * 2.0
	var h := DOOR.y
	_box(Vector3(length, WALL, w), Vector3(0, 0, 0), "corridor")
	_box(Vector3(length, WALL, w), Vector3(0, h, 0), "corridor")
	_box(Vector3(length, h, WALL), Vector3(0, h * 0.5, -DOOR.x * 0.5 - WALL * 0.5), "corridor")
	_box(Vector3(length, h, WALL), Vector3(0, h * 0.5, DOOR.x * 0.5 + WALL * 0.5), "corridor")
	level.create_visgroup("corridor")
	level.add_selection_to_visgroup("corridor", _nodes_for(_shell_ids_since(mark)))


## Cut the corridor's mouth through the inner wall of each hall.
##
## A doorway cut into a shell, rather than a gap left between four wall brushes,
## is the thing the examples cannot show. It needs a subtract that survives the
## save, and it leaves the join between the cut wall and the floor that the UV
## alignment has to run through.
func _doorways() -> void:
	for x in [WEST.x + HALL.x * 0.5, EAST.x - HALL.x * 0.5]:
		var cutter = _box(Vector3(WALL * 4.0, DOOR.y, DOOR.x), Vector3(x, DOOR.y * 0.5, 0), "shell")
		var carve = level.carve_with_brush(str(cutter.brush_id))
		if not carve.ok:
			push_error("reference map: carving a doorway failed: %s" % carve.user_text())


## Six pillars down each hall, three brushes apiece.
##
## Real levels are mostly repeated small brushes like these, which is the part a
## grid of boxes gets right and a five brush example does not.
func _colonnade(centre: Vector3) -> void:
	var inset := HALL.x * 0.5 - 2.0
	for i in range(3):
		var z := -4.0 + float(i) * 4.0
		for sx in [-1.0, 1.0]:
			var x: float = centre.x + inset * sx
			_box(Vector3(1.0, 0.25, 1.0), Vector3(x, 0.125, z), "pillar")
			_box(Vector3(0.6, 3.0, 0.6), Vector3(x, 1.75, z), "pillar")
			_box(Vector3(1.0, 0.25, 1.0), Vector3(x, 3.375, z), "pillar")


func _beams(centre: Vector3) -> void:
	for i in range(5):
		var z := -5.0 + float(i) * 2.5
		_box(Vector3(HALL.x - WALL * 2.0, 0.3, 0.4), Vector3(centre.x, 3.55, z), "beam")


func _skirting(centre: Vector3) -> void:
	var half := HALL.x * 0.5 - WALL
	for sz in [-1.0, 1.0]:
		_box(Vector3(HALL.x - WALL * 2.0, 0.2, 0.1), Vector3(centre.x, 0.1, half * sz), "trim")
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.2, HALL.z - WALL * 2.0), Vector3(centre.x + half * sx, 0.1, 0), "trim")


## A flight up to a ledge in the west hall. Eight steps at 0.25, the rise the
## connector generator is tuned for, so the navmesh bake has something to climb.
func _stairs() -> void:
	for i in range(8):
		var y := 0.125 + float(i) * 0.25
		var z := -5.5 + float(i) * 0.5
		_box(Vector3(3.0, 0.25, 0.5), Vector3(WEST.x - 4.0, y, z), "stair")
	_box(Vector3(3.0, 0.25, 2.5), Vector3(WEST.x - 4.0, 2.125, -0.75), "stair")


func _crates() -> void:
	var spots := [
		Vector3(WEST.x + 3.0, 0.5, 4.0),
		Vector3(WEST.x + 4.0, 0.5, 4.8),
		Vector3(WEST.x + 3.5, 1.5, 4.4),
		Vector3(WEST.x - 5.0, 0.5, 3.0),
		Vector3(EAST.x - 3.0, 0.5, -4.0),
		Vector3(EAST.x - 4.0, 0.5, -4.8),
		Vector3(EAST.x - 3.5, 1.5, -4.4),
		Vector3(EAST.x + 4.5, 0.5, 5.0),
		Vector3(EAST.x + 5.3, 0.5, 5.0),
		Vector3(0.0, 0.5, 0.0),
	]
	for spot in spots:
		_box(Vector3(1.0, 1.0, 1.0), spot, "crate")


## Trim around each doorway, and the pedestal the button stands on.
func _door_frame() -> void:
	for x in [WEST.x + HALL.x * 0.5, EAST.x - HALL.x * 0.5]:
		for sz in [-1.0, 1.0]:
			_box(
				Vector3(0.3, DOOR.y + 0.3, 0.15),
				Vector3(x, DOOR.y * 0.5, (DOOR.x * 0.5 + 0.075) * sz),
				"frame"
			)
		_box(Vector3(0.3, 0.15, DOOR.x + 0.3), Vector3(x, DOOR.y + 0.075, 0), "frame")
	_box(Vector3(0.6, 1.0, 0.6), Vector3(WEST.x + 4.0, 0.5, 2.0), "frame")


# ---------------------------------------------------------------------------
# Surfaces
# ---------------------------------------------------------------------------


func _palette() -> void:
	var added = level.add_prototype_materials()
	var mats: Array = level.get_materials()
	for i in range(mats.size()):
		var mat = mats[i]
		if mat == null or mat.resource_path == "":
			continue
		var file := String(mat.resource_path).get_file()
		if file.begins_with("proto_") and file.ends_with(".tres"):
			_slots[file.substr(6, file.length() - 11)] = i
	print("palette slots added: %s, named: %d" % [added, _slots.keys().size()])
	for family in SURFACES.keys():
		for mat_name in SURFACES[family]:
			if not _slots.has(mat_name):
				push_error("reference map: no prototype material named %s" % mat_name)


## Give every face the material its surface should have, then line the UVs up
## where two surfaces meet.
##
## Both faces of a floor to wall join take the same scale and an offset read off
## the same world origin, so the texture grid runs through the corner instead of
## stepping at it. That is the thing a screenshot of the examples cannot show and
## prose describes badly.
func _texture() -> void:
	var aligned := 0
	for brush in _brush_nodes():
		var bid := str(brush.brush_id)
		var family: String = _kind.get(bid, "shell")
		var names: Array = SURFACES.get(family, SURFACES["shell"])
		var faces = brush.get("faces")
		if faces == null:
			continue
		for fi in range(faces.size()):
			var n: Vector3 = brush.global_transform.basis * faces[fi].normal
			var which := 1
			if n.y > 0.7:
				which = 0
			elif n.y < -0.7:
				which = 2
			var slot: int = _slots.get(names[which], -1)
			if slot < 0 or not level.is_usable_material_slot(slot):
				continue
			level.assign_material_to_faces_by_id(bid, [fi], slot)
			# Only the surfaces that meet at a join are worth anchoring. A crate
			# face aligned to world space would look wrong, not right.
			if family != "shell" and family != "corridor":
				continue
			var origin: Vector3 = brush.global_transform.origin
			var offset := Vector2(origin.x, origin.z) if which == 0 else Vector2(origin.x, origin.y)
			level.set_face_uv_params(bid, fi, UV_SCALE, offset * UV_SCALE, 0.0)
			aligned += 1
	print("faces anchored to world UVs: %d" % aligned)


# ---------------------------------------------------------------------------
# Entities
# ---------------------------------------------------------------------------


func _point(entity_class: String, entity_name: String, pos: Vector3) -> Node:
	var e := DraftEntity.new()
	e.entity_class = entity_class
	e.name = entity_name
	e.position = pos
	level.add_entity(e)
	return e


## The spawn, the lights, the tied brush entities and the wiring between them.
##
## The wire is a chain rather than a single hop: the button fires the relay and
## the relay fires the door, and the corridor trigger fires the same relay. Two
## sources into one target is the shape that breaks when a format drops the
## second one, and a single hop would not catch that.
func _entities() -> void:
	if level.spawn_system and not level.spawn_system.get_active_spawn():
		level.spawn_system.create_default_spawn()
	var spawn = level.spawn_system.get_active_spawn() if level.spawn_system else null
	if spawn:
		spawn.global_position = Vector3(WEST.x, 0.5, 4.0)

	_point("light_point", "west_light", Vector3(WEST.x, 3.0, 0))
	_point("light_point", "east_light", Vector3(EAST.x, 3.0, 0))
	_point("light_point", "corridor_light", Vector3(0, DOOR.y - 0.4, 0))
	_point("light_point", "stair_light", Vector3(WEST.x - 4.0, 3.0, -3.0))
	var relay := _point("logic_relay", "door_relay", Vector3(0, 1.0, 2.0))

	# Ties. The door leaf, the button face and the corridor volume stop being
	# world geometry and start being entities, which is the record that has no
	# home in `example_levels.json`.
	var leaf = _box(
		Vector3(0.2, DOOR.y - 0.1, DOOR.x - 0.1),
		Vector3(WEST.x + HALL.x * 0.5, (DOOR.y - 0.1) * 0.5, 0),
		"door"
	)
	level.tie_brushes_to_entity([str(leaf.brush_id)], "func_door", "west_door")
	var button = _box(Vector3(0.3, 0.3, 0.3), Vector3(WEST.x + 4.0, 1.15, 2.0), "button")
	level.tie_brushes_to_entity([str(button.brush_id)], "func_button", "door_button")
	var volume = _box(
		Vector3(2.0, DOOR.y - 0.3, DOOR.x - 0.3), Vector3(-3.0, (DOOR.y - 0.3) * 0.5, 0), "trigger"
	)
	level.tie_brushes_to_entity([str(volume.brush_id)], "trigger_multiple", "corridor_trigger")

	level.add_entity_output(button, "OnPressed", "door_relay", "Trigger", "", 0.0, false)
	level.add_entity_output(volume, "OnStartTouch", "door_relay", "Trigger", "", 0.0, false)
	level.add_entity_output(relay, "OnTrigger", "west_door", "Open", "", 0.25, false)


## The options a shipped level bakes with, saved into the file so loading it back
## reproduces that bake rather than the defaults.
func _bake_options() -> void:
	level.bake_use_face_materials = true
	level.bake_navmesh = true
	level.bake_generate_occluders = true
	level.bake_occluder_min_area = 4.0
	level.bake_collision_layer_index = 1


# ---------------------------------------------------------------------------
# Writing it out
# ---------------------------------------------------------------------------


## The save is threaded and its worker is collected in `_process_hflevel_saves()`,
## which only runs on its own under `Engine.is_editor_hint()`. Headless has to
## pump it, and polling for the file instead races the atomic replace.
func _settle_save(max_frames: int = 600) -> bool:
	if not level.file_system:
		return false
	for _i in range(max_frames):
		level._process_hflevel_saves()
		if not level.file_system._hflevel_thread:
			return true
		await process_frame
	return false


## Every brush now in the level that was not there at `mark`.
##
## A hollow and a carve both replace the brush they were given, so the ids `_box`
## recorded are not the ids that survive. Reading the level back is the only way
## to name what a structural operation produced.
func _shell_ids_since(mark: int) -> Array:
	var before: Dictionary = {}
	for i in range(min(mark, _made.size())):
		before[_made[i]] = true
	var out: Array = []
	for node in _brush_nodes():
		var bid := str(node.brush_id)
		if not before.has(bid):
			out.append(bid)
			if not _kind.has(bid):
				_kind[bid] = "shell"
	return out


func _nodes_for(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var node = level.brush_system.find_brush_by_id(str(id))
		if node:
			out.append(node)
	return out


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return -1
	var size := f.get_length()
	f.close()
	return size
