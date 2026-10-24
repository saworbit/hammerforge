extends RefCounted
## The recorded outcome of each chaos seed, in `tests/goldens/chaos.json` (#1643).
##
## One line per seed and scenario: what the run ended with, from
## `HFVibe.outcome()`. A new run is compared with it, and any change fails,
## better or worse. Accepting a change takes a reason, which goes into the
## file's `notes` with the date and the seeds it moved, so the file says why
## each number changed.

const PATH := "res://tests/goldens/chaos.json"
const SCENARIOS := ["chaos", "chaos-io", "chaos-systems"]
## How close two volumes must be, as a share of the larger. The engine stores
## points as 32 bit floats, and a rotated brush's volume moves in its eighth
## digit from one platform to another.
const VOLUME_TOLERANCE := 0.0001
const BOUNDS_TOLERANCE := 0.01

var path := PATH
var data: Dictionary = {}


func _init(file: String = PATH) -> void:
	path = file
	data = {}
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
		data = _tidy(json.data)


func recorded(scenario: String, seed_value: int) -> Dictionary:
	var seeds: Variant = data.get(scenario, {})
	if not (seeds is Dictionary):
		return {}
	var line: Variant = (seeds as Dictionary).get(str(seed_value), {})
	return line if line is Dictionary else {}


## Record `line` for a seed when it differs from what is recorded, and name the
## seed in the note for `reason`. A blank reason records nothing. Returns
## whether the file changed.
func bless(
	scenario: String,
	seed_value: int,
	line: Dictionary,
	reason: String,
	date: String = Time.get_date_string_from_system()
) -> bool:
	reason = reason.strip_edges()
	if reason == "":
		return false
	var before := recorded(scenario, seed_value)
	if not before.is_empty() and differences(before, line).is_empty():
		return false
	var seeds: Dictionary = data.get(scenario, {})
	seeds[str(seed_value)] = line
	data[scenario] = seeds
	var notes: Array = data.get("notes", [])
	var note: Dictionary = notes[-1] if not notes.is_empty() else {}
	if str(note.get("reason", "")) != reason or str(note.get("date", "")) != date:
		note = {"date": date, "reason": reason, "seeds": {}}
		notes.append(note)
	var named: Dictionary = note["seeds"]
	var listed: Array = named.get(scenario, [])
	if not listed.has(seed_value):
		listed.append(seed_value)
	named[scenario] = listed
	data["notes"] = notes
	save()
	return true


## One line per seed, in seed order, so a change reads as a change to its own
## line in a diff.
func save() -> void:
	data = _tidy(data)
	var out := PackedStringArray(["{"])
	out.append('\t"steps": %s,' % JSON.stringify(data.get("steps", 60)))
	for scenario in SCENARIOS:
		var seeds: Dictionary = data.get(scenario, {})
		var keys: Array = seeds.keys()
		keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
		out.append('\t"%s": {' % scenario)
		for i in keys.size():
			var comma := "," if i < keys.size() - 1 else ""
			out.append('\t\t"%s": %s%s' % [keys[i], JSON.stringify(seeds[keys[i]]), comma])
		out.append("\t},")
	var notes: Array = data.get("notes", [])
	out.append('\t"notes": [')
	for i in notes.size():
		out.append("\t\t%s%s" % [JSON.stringify(notes[i]), "," if i < notes.size() - 1 else ""])
	out.append("\t]")
	out.append("}")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(out) + "\n")
		file.close()


## JSON reads every number back as a float, so a count read from the file would
## be written again as `135.0`. A whole number goes back as an int.
static func _tidy(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == roundf(value) and absf(value) < 1e15:
		return int(value)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _tidy(value[key])
		return out
	if value is Array:
		return (value as Array).map(func(item): return _tidy(item))
	return value


## The outcome as it is recorded: volume and bounds to 1e-4.
static func rounded(outcome: Dictionary) -> Dictionary:
	var line := outcome.duplicate(true)
	if line.has("volume"):
		line["volume"] = snappedf(float(line["volume"]), 0.0001)
	if line.get("bounds") is Array:
		line["bounds"] = (line["bounds"] as Array).map(func(v): return snappedf(float(v), 0.0001))
	return line


## What moved between a recorded line and a new one, one entry a key. Counts
## must match exactly; the volume and the bounds to a tolerance.
static func differences(recorded_line: Dictionary, line: Dictionary) -> Array[String]:
	var moved: Array[String] = []
	var keys: Array = recorded_line.keys()
	for key in line.keys():
		if not keys.has(key):
			keys.append(key)
	keys.sort()
	for key in keys:
		var was: Variant = recorded_line.get(key)
		var now: Variant = line.get(key)
		if not _same(str(key), was, now):
			moved.append(
				"%s %s -> %s" % [key, JSON.stringify(_tidy(was)), JSON.stringify(_tidy(now))]
			)
	return moved


static func _same(key: String, was: Variant, now: Variant) -> bool:
	if was == null or now == null:
		return was == now
	if key == "volume":
		var scale := maxf(1.0, maxf(absf(float(was)), absf(float(now))))
		return absf(float(was) - float(now)) <= VOLUME_TOLERANCE * scale
	if key == "bounds":
		if not (was is Array and now is Array) or was.size() != now.size():
			return false
		for i in was.size():
			if absf(float(was[i]) - float(now[i])) > BOUNDS_TOLERANCE:
				return false
		return true
	if (was is int or was is float) and (now is int or now is float):
		return int(was) == int(now)
	return JSON.stringify(was) == JSON.stringify(now)
