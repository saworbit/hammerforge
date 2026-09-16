@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the `.hflevel` encoder can carry.
##
## The file is JSON. `HFLevelIO.encode_variant()` names the handful of Godot
## types it knows how to write and passes everything else straight to
## `JSON.stringify`, which turns an unrecognised Variant into its `str()` form
## and leaves it a String on the way back. Nothing warns.
##
## That is fine as long as nothing in the level state is one of those types --
## which is a property of code nobody is checking, in a format that is
## version-stamped and meant to be read by later builds.

const HFLevelIOType = preload("res://addons/hammerforge/hflevel_io.gd")


func id() -> String:
	return "level-io-types"


func summary() -> String:
	return "which Variant types survive the .hflevel encoder, and what happens to the ones that do not"


func run() -> void:
	_round_trip_every_type()
	_dictionary_keys()
	await _a_missing_resource_path()


func _trip(value: Variant) -> Variant:
	var encoded = HFLevelIOType.encode_variant({"v": value})
	var json := JSON.stringify(encoded)
	var parsed = JSON.parse_string(json)
	if not (parsed is Dictionary):
		return null
	var decoded = HFLevelIOType.decode_variant(parsed)
	return (decoded as Dictionary).get("v", null)


func _round_trip_every_type() -> void:
	var cases: Array = [
		["bool", true],
		["int", 42],
		["float", 1.5],
		["String", "hello"],
		["StringName", &"hello"],
		["Vector2", Vector2(1, 2)],
		["Vector2i", Vector2i(1, 2)],
		["Vector3", Vector3(1, 2, 3)],
		["Vector3i", Vector3i(1, 2, 3)],
		["Vector4", Vector4(1, 2, 3, 4)],
		["Rect2", Rect2(1, 2, 3, 4)],
		["Rect2i", Rect2i(1, 2, 3, 4)],
		["AABB", AABB(Vector3.ZERO, Vector3.ONE)],
		["Plane", Plane(Vector3.UP, 5.0)],
		["Quaternion", Quaternion(0, 0, 0, 1)],
		["Basis", Basis.IDENTITY],
		["Transform2D", Transform2D.IDENTITY],
		["Transform3D", Transform3D.IDENTITY],
		["Color", Color(0.25, 0.5, 0.75, 0.5)],
		["PackedInt32Array", PackedInt32Array([1, 2, 3])],
		["PackedFloat32Array", PackedFloat32Array([1.5, 2.5])],
		["PackedStringArray", PackedStringArray(["a", "b"])],
		["PackedVector3Array", PackedVector3Array([Vector3.ONE])],
		["PackedByteArray", PackedByteArray([1, 2, 3])],
		["Array", [1, "two", Vector3.ONE]],
		["Dictionary", {"a": 1, "b": Vector3.ONE}],
	]
	var lost: Array = []
	for pair in cases:
		var label: String = pair[0]
		var original: Variant = pair[1]
		var back: Variant = _trip(original)
		var same := HFVibe.canonical(original) == HFVibe.canonical(back)
		var type_kept := typeof(original) == typeof(back)
		note(
			"%-20s" % label,
			(
				"%s -> %s (%s)"
				% [
					HFVibe.canonical(original).substr(0, 40),
					HFVibe.canonical(back).substr(0, 40),
					(
						"same"
						if same and type_kept
						else (
							"value kept, type now %s" % type_string(typeof(back))
							if same
							else "LOST, came back as %s" % type_string(typeof(back))
						)
					)
				]
			)
		)
		if not (same and type_kept):
			lost.append("%s -> %s" % [label, type_string(typeof(back))])
	note("types the encoder does not round trip", lost)
	if not lost.is_empty():
		known(
			619,
			"%d Variant types silently change type through the .hflevel encoder" % lost.size(),
			(
				("%s. " % str(lost))
				+ "encode_variant()'s match has a `_: return value` arm, so anything it "
				+ "does not name is handed to JSON.stringify and comes back as whatever "
				+ "JSON made of it -- usually a String of Godot's own notation, which no "
				+ "later read can turn back into the value. Nothing warns, and the file "
				+ "still carries the current format version"
			)
		)


## Dictionary *keys* do not go through the encoder at all.
func _dictionary_keys() -> void:
	var original := {Vector2i(3, 4): "cell", 7: "int key", "s": "string key"}
	var back = _trip(original)
	note("a Dictionary with a Vector2i key, an int key and a String key", original)
	note("  after the round trip", back)
	if back is Dictionary:
		var keys: Array = (back as Dictionary).keys()
		var kinds: Array = []
		for k in keys:
			kinds.append(type_string(typeof(k)))
		note("  key types after", kinds)
		if not kinds.has("Vector2i"):
			known(
				619,
				"a Dictionary key is never encoded, so a non-String key comes back a String",
				(
					(
						"encode_variant() encodes the values of a Dictionary and copies the "
						+ "keys: `dict_out[key] = encode_variant(value[key], _depth + 1)`. A "
						+ "Vector2i key -- the shape a paint grid cell is -- becomes the String "
						+ "'%s' and stays one. Key types after the trip: %s"
					)
					% [str(keys[0]) if not keys.is_empty() else "?", kinds]
				)
			)


## A ResourcePath that no longer resolves.
func _a_missing_resource_path() -> void:
	var encoded := {"__hf_type": "ResourcePath", "path": "res://not_here_any_more.tres"}
	var decoded = HFLevelIOType.decode_variant({"v": encoded})
	note("a .hflevel pointing at a material that has moved", (decoded as Dictionary).get("v", "?"))
	note(
		"  decode_variant returns null for a path ResourceLoader cannot find",
		(
			"no warning, no record of what the path was, and the slot the material was in "
			+ "keeps its position -- so every face pointing at it is untextured with "
			+ "nothing on screen to say why"
		)
	)
	var root: Node3D = await fresh_root()
	note("(a live root, so the scenario leaves one behind like the others)", root.name)
