@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a game's FGD becomes once HammerForge reads it, and what a mapper can do
## with the classes it gives.
##
## `HFFgdReader` turns an FGD into the entries an `entities.json` holds. The
## file here is written the way real ones are: a Targetname base class, choices
## and flags blocks, `+` continuations, quoted strings holding colons and
## brackets, `size()` and `color()`, a TrenchBroom model helper, `@include`, and
## comments. Then the classes are used: the level reads the file as its entity
## definitions, an entity is placed, Convert to JSON is read back, and the name
## the FGD gives an entity is used the way a wire and a `.map` use it.

const HFFgdReader = preload("res://addons/hammerforge/hf_fgd_reader.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

const DIR := "user://vibe_fgd_import"

const BASE := """
// Shared by every class that can be named.
@BaseClass = Targetname
[
	targetname(target_source) : "Name" : : "The name that other entities refer to this entity by."
	input Kill(void) : "Removes this entity from the world."
]
@BaseClass = Angles [ angles(angle) : "Pitch Yaw Roll (Y Z X)" : "0 0 0" ]
"""

const GAME := """
@include "base.fgd"
@mapsize(-16384, 16384)

@PointClass base(Targetname, Angles) size(-16 -16 0, 16 16 72) color(0 255 0)
	studio("models/editor/playerstart.mdl") model({ "path": ":progs/player.mdl" })
	= info_player_start : "This entity indicates the position " +
	"and facing direction at which the player will spawn."
[
	message(string) : "Message: [shown on spawn]" : "Hello: world [1]"
	rendermode(choices) : "Render Mode" : 0 : "Used to set a non-standard rendering mode." =
	[
		0 : "Normal"
		1 : "Color"
		5 : "Additive"
	]
	spawnflags(flags) =
	[
		1 : "Start On" : 1
		2 : "Silent" : 0
		4 : "Only once" : 1
	]
	rendercolor(color255) : "FX Color (R G B)" : "255 128 0"
	health(integer) : "Health" : -1
	speed(float) : "Speed" : "0.25"
	output OnSpawn(void) : "Fired when the player spawns here"
]

@SolidClass base(Targetname) color(0 128 255) = func_door : "A sliding door" [
	speed(integer) : "Speed" : 100
	input Open(void) : "Opens it"
]
"""


func id() -> String:
	return "fgd-import"


func summary() -> String:
	return "a game's FGD through the reader, a placed entity, Convert to JSON, a wire and a .map"


func expected_issues() -> Array[int]:
	return [1985, 1986, 1987]


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var written: Array[String] = []
	written.append(_write("base.fgd", BASE))
	var game := _write("game.fgd", GAME)
	written.append(game)

	var read: Dictionary = HFFgdReader.read_file(game)
	var by_id := {}
	for entry in read["entries"]:
		by_id[entry["id"]] = entry
	note("classes", by_id.keys())
	note("warnings", read["warnings"])
	_check_the_reading(by_id)
	_malformed()

	var root: Node3D = await fresh_root("FgdLevel")
	root.hflevel_autosave_enabled = false
	root.entity_definitions_path = game
	root.entity_system.load_entity_definitions()
	await _defaults_through_json(root, game, written)
	await _the_name_the_fgd_gives(root)

	for path in written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	await drop_root(root)


func _write(file: String, text: String) -> String:
	var path := DIR.path_join(file)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()
	return path


static func _prop(entry: Dictionary, prop_name: String) -> Dictionary:
	for prop in entry.get("properties", []):
		if prop["name"] == prop_name:
			return prop
	return {}


func _check_the_reading(by_id: Dictionary) -> void:
	var start: Dictionary = by_id.get("info_player_start", {})
	if start.is_empty():
		flag("info_player_start was not read")
		return
	var want_description := "This entity indicates the position and facing direction at which the player will spawn."
	if str(start["description"]) != want_description:
		flag("a description joined with + reads wrong", start["description"])
	var message := _prop(start, "message")
	note("message", message)
	if (
		str(message.get("label", "")) != "Message: [shown on spawn]"
		or str(message.get("default", "")) != "Hello: world [1]"
	):
		flag("a string holding a colon and brackets reads wrong", message)
	var mode := _prop(start, "rendermode")
	note("rendermode", mode)
	if mode.get("enum_values", []) != ["0", "1", "5"] or str(mode.get("default", "")) != "0":
		flag("a choices block reads wrong", mode)
	var flags := _prop(start, "spawnflags")
	note("spawnflags", flags)
	if int(flags.get("default", -1)) != 5:
		flag("a flags block's default is not the bits marked 1", flags)
	var colour := _prop(start, "rendercolor")
	note("rendercolor", colour)
	var as_colour: Color = HFEntityPropUtils.coerce_default("color", colour.get("default"))
	if not as_colour.is_equal_approx(Color8(255, 128, 0)):
		flag(
			"a color255 default is not the colour it names",
			"%s -> %s" % [colour.get("default"), as_colour]
		)
	if int(_prop(start, "health").get("default", 0)) != -1:
		flag("a negative integer default reads wrong", _prop(start, "health"))
	if not _prop(start, "targetname").has("name") or not _prop(start, "angles").has("name"):
		flag(
			"base(Targetname, Angles) from an @include did not lend its properties",
			start["properties"]
		)
	var preview: Dictionary = start.get("preview", {})
	note("size() as a preview box, metres", preview.get("size"))
	if start.get("inputs", []) != ["Kill"] or start.get("outputs", []) != ["OnSpawn"]:
		flag("inputs and outputs read wrong", [start.get("inputs"), start.get("outputs")])
	var door: Dictionary = by_id.get("func_door", {})
	if not bool(door.get("is_brush_entity", false)):
		flag("a @SolidClass is not a brush entity", door)


## Text that is wrong in the ways hand edits are. Nothing here should take the
## classes after the mistake with it.
func _malformed() -> void:
	var cases := {
		"a base() missing its )":
		'@PointClass base(Targetname = broken : "x" [ ]\n@PointClass = after_it : "y" [ a(string) ]\n',
		"a choices block missing its ]":
		'@PointClass = broken [ c(choices) : "C" : 0 = [ 0 : "A"\n]\n@PointClass = after_it [ a(string) ]\n',
		"an open string":
		'@PointClass = broken : "never closed [ a(string) ]\n@PointClass = after_it [ a(string) ]\n',
		"cut off mid class": "@PointClass = after_it [ a(string) ]\n@PointClass base(",
	}
	for label in cases:
		var read: Dictionary = HFFgdReader.read_text(cases[label], label)
		var ids: Array = read["entries"].map(func(e): return e["id"])
		note(label, "classes %s, warnings %s" % [ids, read["warnings"]])
		if not ids.has("after_it"):
			known(
				1987,
				"%s takes every class after it out of the file" % label,
				(
					"_closing() looks for the matching bracket to the end of the file and never stops at the next top level @, so one missing bracket swallows the rest; warnings: %s"
					% [read["warnings"]]
				)
			)


## The flags default the FGD gives, on a placed entity, read from the FGD and
## from the entities.json Convert to JSON writes.
func _defaults_through_json(root: Node3D, game: String, written: Array[String]) -> void:
	var placed := _place(root, "info_player_start", "from_fgd")
	await frame()
	var from_fgd: Variant = placed.entity_data.get("spawnflags")
	var json_path := game.get_basename() + ".json"
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	var entries: Array = HFFgdReader.read_file(game)["entries"]
	file.store_string(HFFgdReader.to_json_text(entries))
	file.close()
	written.append(json_path)
	root.entity_definitions_path = json_path
	root.entity_system.load_entity_definitions()
	var again := _place(root, "info_player_start", "from_json")
	await frame()
	var from_json: Variant = again.entity_data.get("spawnflags")
	note(
		"spawnflags on a placed entity, from the FGD / from its JSON",
		"%s / %s" % [from_fgd, from_json]
	)
	if str(from_fgd) != str(from_json):
		known(
			1986,
			"Convert to JSON changes a flags default from %s to %s" % [from_fgd, from_json],
			"JSON reads the 5 back as the float 5.0, and coerce_default('flags') takes a value only when str(value).is_valid_int(), which '5.0' is not (hf_entity_prop_utils.gd)"
		)
	root.entity_definitions_path = game
	root.entity_system.load_entity_definitions()


func _place(root: Node3D, entity_class: String, node_name: String) -> Node3D:
	return (
		root
		. entity_system
		. restore_entity_from_info(
			{
				"name": node_name,
				"entity_type": entity_class,
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(randf() * 10, 0, 0)),
			}
		)
	)


## Every Quake and Source FGD names entities with a targetname property, which
## the reader keeps as a plain property. A wire and a .map export go by the
## level's own name for an entity (the entity_name meta). Name a door through
## the property the panel shows, aim a button at it, and see what answers.
func _the_name_the_fgd_gives(root: Node3D) -> void:
	var door := _place(root, "info_player_start", "spawn_a")
	await frame()
	var label := str(
		_prop(root.get_entity_definition("info_player_start"), "targetname").get("label", "")
	)
	root.set_entity_property(door, "targetname", "spawn_east")
	var button := _place(root, "info_player_start", "spawn_b")
	await frame()
	root.add_entity_output(button, "OnSpawn", "spawn_east", "Kill")
	var found: Array = root.find_entities_by_name("spawn_east")
	note(
		"the panel's '%s' field set to spawn_east; entities that answer to it" % label, found.size()
	)
	var issues: Array = root.validate_level(false).get("issues", [])
	var dangling: Array = issues.filter(func(issue): return str(issue).contains("spawn_east"))
	note("Validate on the wire aimed at spawn_east", dangling)
	var path := DIR.path_join("named.map")
	root.export_map(path, "valve220")
	var text := FileAccess.get_file_as_string(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	note("the .map holds targetname spawn_east", text.contains('"targetname" "spawn_east"'))
	if found.is_empty():
		known(
			1985,
			(
				"a name typed in the FGD's own %s (targetname) field is not a name a wire can aim at"
				% label
			),
			(
				"find_entities_by_name('spawn_east') answers nothing and Validate calls the wire dangling (%d issue): it resolves by node name and the entity_name meta, and the reader keeps targetname as a plain string property in entity_data. A .map import reads targetname into entity_name, so the same name works after a .map round trip and not before. Every Quake and Source FGD's Targetname base class gives this field"
				% dangling.size()
			)
		)
