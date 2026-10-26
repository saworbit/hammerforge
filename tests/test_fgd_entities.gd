extends GutTest

## Entity classes from an FGD (#1721): point and solid classes, base classes
## flattened, the property types, inputs and outputs, several files, what the
## reader skips, a loop of base classes, and Convert to JSON.

const HFFgdReader = preload("res://addons/hammerforge/hf_fgd_reader.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const DIR := "user://test_fgd_entities"

const GAME := """
// A small game, as such files are written.
@BaseClass = Targetname
[
	targetname(target_source) : "Name" : : "The name other entities aim at"
	input Kill(void) : "Removes this entity"
	output OnUser1(void) : "Fired by FireUser1"
]

@BaseClass base(Targetname) color(255 128 0) = Lit
[
	_light(color255) : "Brightness" : "255 255 128 200"
	style(choices) : "Style" : 0 =
	[
		0 : "Normal"
		10 : "Fluorescent flicker"
	]
]

@PointClass base(Lit) size(-8 -8 -8, 8 8 8) = light_bulb : "A small light"
[
	style(choices) : "Style" : 10 =
	[
		0 : "Normal"
		10 : "Fluorescent flicker"
		11 : "Slow strong pulse"
	]
	spawnflags(flags) =
	[
		1 : "Initially dark" : 0
		2 : "Toggle" : 1
	]
	range(integer) : "Range" : 300
	falloff(float) : "Falloff" : "1.5" : "How fast it fades" + " with distance"
	input TurnOn(void) : "Turns it on"
	output OnTurnedOn(void)
]

@SolidClass base(Targetname) color(200 0 200) = trigger_hurt : "Hurts what touches it"
[
	damage(integer) : "Damage" : 10
	output OnHurt(void) : "Fired on each hurt"
]
"""


func before_each():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func after_each():
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))


func _write(file: String, text: String) -> String:
	var path := DIR.path_join(file)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()
	return path


static func _by_id(entries: Array) -> Dictionary:
	var out := {}
	for entry in entries:
		out[entry["id"]] = entry
	return out


static func _prop(entry: Dictionary, name: String) -> Dictionary:
	for prop in entry.get("properties", []):
		if prop["name"] == name:
			return prop
	return {}


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func test_point_and_solid_classes_with_their_bases_folded_in():
	var read := HFFgdReader.read_text(GAME, "game.fgd")
	assert_eq(read["warnings"], [], "a clean file says nothing")
	var classes := _by_id(read["entries"])
	assert_eq(classes.keys(), ["light_bulb", "trigger_hurt"], "base classes are no class")
	var bulb: Dictionary = classes["light_bulb"]
	assert_false(bulb["is_brush_entity"])
	assert_eq(bulb["description"], "A small light")
	assert_eq(bulb["color"], "#ff8000", "the colour its base lends it")
	var preview: Dictionary = bulb["preview"]
	assert_eq(preview["type"], "box")
	assert_eq(preview["size"], [0.5, 0.5, 0.5], "16 map units is half a metre")
	var names: Array = []
	for prop in bulb["properties"]:
		names.append(prop["name"])
	assert_eq(names, ["targetname", "_light", "style", "spawnflags", "range", "falloff"])
	assert_eq(bulb["inputs"], ["Kill", "TurnOn"], "its bases' inputs and its own")
	assert_eq(bulb["outputs"], ["OnUser1", "OnTurnedOn"])
	var hurt: Dictionary = classes["trigger_hurt"]
	assert_true(hurt["is_brush_entity"], "a solid class is a brush entity")
	assert_false(hurt.has("preview"), "a brush entity draws as its brushes")
	assert_eq(hurt["outputs"], ["OnUser1", "OnHurt"])


func test_each_property_type_reads_as_one_the_entity_panel_edits():
	var bulb: Dictionary = _by_id(HFFgdReader.read_text(GAME, "game.fgd")["entries"])["light_bulb"]
	var style := _prop(bulb, "style")
	assert_eq(style["type"], "enum")
	assert_eq(style["enum_values"], ["0", "10", "11"], "its own choices over its base's")
	assert_eq(style["enum_labels"], ["Normal", "Fluorescent flicker", "Slow strong pulse"])
	assert_eq(style["default"], "10")
	var flags := _prop(bulb, "spawnflags")
	assert_eq(flags["type"], "flags")
	assert_eq(flags["flag_values"], [1, 2])
	assert_eq(flags["flag_labels"], ["Initially dark", "Toggle"])
	assert_eq(flags["default"], 2, "the bits on by default")
	assert_eq(_prop(bulb, "range")["type"], "int")
	assert_eq(_prop(bulb, "range")["default"], 300)
	var falloff := _prop(bulb, "falloff")
	assert_eq(falloff["type"], "float")
	assert_almost_eq(float(falloff["default"]), 1.5, 0.0001)
	assert_eq(falloff["tooltip"], "How fast it fades with distance", "joined with +")
	assert_eq(_prop(bulb, "_light")["type"], "color")
	assert_eq(_prop(bulb, "_light")["default"], "ffff80")
	var name := _prop(bulb, "targetname")
	assert_eq(name["type"], "string")
	assert_eq(name["label"], "Name")
	assert_eq(name["tooltip"], "The name other entities aim at")


func test_a_level_reads_an_fgd_and_several_files_in_order():
	var game := _write("game.fgd", GAME)
	var extra := _write(
		"extra.fgd",
		'@SolidClass = trigger_hurt : "Hurts harder" [ damage(integer) : "Damage" : 50 ]'
	)
	var root := _fresh_root()
	root.entity_definitions_path = game
	root.entity_system.load_entity_definitions()
	assert_true(root.entity_definitions.has("light_bulb"))
	var bulb: Dictionary = root.entity_definitions["light_bulb"]
	assert_eq(bulb["inputs"], ["Kill", "TurnOn"], "what the I/O wiring panel offers")
	root.entity_definitions_path = "%s;%s" % [game, extra]
	root.entity_system.load_entity_definitions()
	var hurt: Dictionary = root.entity_definitions["trigger_hurt"]
	assert_eq(hurt["description"], "Hurts harder", "a later file's class over an earlier one")
	assert_true(root.entity_definitions.has("light_bulb"), "and the earlier file's others stay")
	var defaults: Variant = HFEntityPropUtils.coerce_default("flags", 2)
	assert_eq(defaults, 2)


func test_what_the_reader_has_no_use_for_is_one_warning_with_its_line():
	var text := """
@mapsize(-16384, 16384)
@PointClass studio("models/x.mdl") iconsprite("x.vmt") size(16 16 16) = thing
[
	model(studio) : "Model"
	sphere_helper unknown
]
@MysteryDirective = nothing [ ]
@PointClass = other [ health(integer) : "Health" : 5 ]
"""
	var read := HFFgdReader.read_text(text, "odd.fgd")
	var classes := _by_id(read["entries"])
	assert_true(classes.has("thing") and classes.has("other"), "the rest loads")
	assert_eq(classes["thing"]["preview"]["size"], [0.5, 0.5, 0.5], "size(16 16 16) is a box")
	assert_eq(_prop(classes["other"], "health")["default"], 5)
	assert_eq(read["warnings"].size(), 1, str(read["warnings"]))
	if read["warnings"].size() == 1:
		var warning: String = read["warnings"][0]
		assert_string_contains(warning, "odd.fgd")
		assert_string_contains(warning, "the first at line 3")
		assert_string_contains(warning, "studio()")
	assert_eq(_prop(classes["thing"], "model")["type"], "string", "a model path is text")


func test_a_loop_of_base_classes_is_refused_and_named():
	var text := """
@BaseClass base(Second) = First [ a(string) ]
@BaseClass base(First) = Second [ b(string) ]
@PointClass base(First) = looped [ ]
@PointClass = fine [ c(string) ]
"""
	var read := HFFgdReader.read_text(text, "loop.fgd")
	assert_eq(_by_id(read["entries"]).keys(), ["fine"], "the looped class is left out")
	var said := " ".join(read["warnings"])
	assert_string_contains(said, "loop back")
	assert_string_contains(said, "First -> Second -> First")


func test_an_open_string_says_where_and_the_rest_loads():
	var text := '@PointClass = broken : "never closed\n[ a(string) ]\n@PointClass = after [ b(string) ]'
	var read := HFFgdReader.read_text(text, "open.fgd")
	assert_true(_by_id(read["entries"]).has("after"))
	var said := " ".join(read["warnings"])
	assert_string_contains(said, "open.fgd, line 1: a string is not closed")


func test_ten_thousand_classes_load():
	var lines := PackedStringArray()
	for i in 10000:
		lines.append(
			'@PointClass base(B) = c%d : "class %d" [ n%d(integer) : "N" : %d ]' % [i, i, i, i]
		)
	var text := "@BaseClass = B [ shared(string) ]\n" + "\n".join(lines)
	var started := Time.get_ticks_msec()
	var read := HFFgdReader.read_text(text, "big.fgd")
	var took := Time.get_ticks_msec() - started
	assert_eq(read["entries"].size(), 10000)
	assert_eq(read["entries"][9999]["properties"].size(), 2)
	gut.p("10,000 classes in %d ms" % took)


func test_include_reads_a_file_beside_it():
	_write("base.fgd", "@BaseClass = Named [ targetname(target_source) ]")
	var game := _write("main.fgd", '@include "base.fgd"\n@PointClass base(Named) = marker [ ]')
	var read := HFFgdReader.read_file(game)
	var marker: Dictionary = _by_id(read["entries"]).get("marker", {})
	assert_false(_prop(marker, "targetname").is_empty(), "the included base lends its property")


func test_convert_to_json_writes_a_file_that_reads_back_to_the_same_classes():
	var game := _write("game.fgd", GAME)
	var root := _fresh_root()
	root.entity_definitions_path = game
	var out := HFPluginCommands.convert_entity_definitions(RefCounted.new(), root)
	assert_eq(out, DIR.path_join("game.json"))
	var back := HFEntityDef.load_definitions_from_file(out)
	var fgd := HFEntityDef.load_definitions_from_file(game)
	assert_eq(back.size(), fgd.size())
	# Through JSON on both sides, which reads every number back as a float.
	for i in back.size():
		assert_eq(
			_plain(back[i].to_dict()),
			_plain(fgd[i].to_dict()),
			"%s reads back the same" % fgd[i].classname
		)


static func _plain(value: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true))


## JSON reads every number back a float, and a flags default of 2 came back 2.0,
## which a placed entity read as 0 (#1986).
func test_a_flags_default_keeps_its_value_through_convert_to_json():
	var game := _write("game.fgd", GAME)
	var root := _fresh_root()
	root.entity_definitions_path = game
	var out := HFPluginCommands.convert_entity_definitions(RefCounted.new(), root)
	var defaults := {}
	for path in [game, out]:
		for definition in HFEntityDef.load_definitions_from_file(path):
			if definition.classname != "light_bulb":
				continue
			for prop in definition.to_dict().get("properties", []):
				if prop["name"] == "spawnflags":
					defaults[path] = HFEntityPropUtils.coerce_default("flags", prop["default"])
	assert_eq(defaults.get(game), 2, "Toggle is ticked by default in the FGD")
	assert_eq(defaults.get(out), 2, "and in the JSON it converts to")


## One unclosed bracket took every class after it out of the file (#1987).
func test_an_unclosed_bracket_leaves_the_classes_after_it():
	var read := HFFgdReader.read_text(
		(
			'@PointClass base(Targetname = broken : "x" [ ]\n'
			+ '@PointClass = after_it : "y" [ a(string) ]\n'
		),
		"broken.fgd"
	)
	assert_true(_by_id(read["entries"]).has("after_it"), "the class after it loads")
	var said := " ".join(read["warnings"])
	assert_string_contains(said, "is not closed", "and the warning says which bracket")


## The Name field a game's FGD gives its classes is the name a wire aims at, as a
## `.map` import has always made it (#1985).
func test_a_targetname_typed_in_its_field_is_the_name_wires_aim_at():
	var root := _fresh_root()
	var lamp: Node3D = root.entity_system.restore_entity_from_info(
		{"name": "LightBulb1", "entity_class": "light_bulb"}
	)
	root.set_entity_property(lamp, "targetname", "hall_lamp")
	assert_eq(root.find_entities_by_name("hall_lamp"), [lamp], "the typed name is its name")
	root.set_entity_property(lamp, "targetname", "")
	assert_eq(root.find_entities_by_name("hall_lamp"), [], "and clearing it takes the name away")
	assert_eq(root.find_entities_by_name("LightBulb1"), [lamp], "leaving the node's own")
