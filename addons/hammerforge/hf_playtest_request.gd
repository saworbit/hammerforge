@tool
extends RefCounted
## How the editor asks a run for a playtest player.
##
## A level cannot tell Test Level apart from the mapper pressing F5 on their own
## game, because it is the same scene either way. So the launcher leaves a
## request behind and the run that comes up collects it (#771).
##
## Written to a file rather than set on the node because `play_current_scene()`
## plays the scene *file*: a property set on the live node would have to be saved
## into the mapper's own scene to reach the running instance, and would then be
## on for their shipped game too, which is the second character controller #719
## removed.
##
## Both halves live here so that what is written and what is read cannot drift
## apart, and so neither side has to name the other's class.

## Under a dot directory, which an export does not ship.
const PATH := "res://.hammerforge/playtest.request"

## Long enough for a bake and a process launch, short enough that a request left
## behind by an editor that went away is not still live later on.
const WINDOW_SECONDS := 600.0


## Leave a request for the next run that comes up.
##
## `overrides` is what this one run should do differently from the scene:
## `spawn_position` (Vector3) and `spawn_yaw_degrees` for Test from Camera,
## `cordon` (AABB) for Test Selected Area. They travel here, and not on the
## level, because Godot saves the edited scene on the way into a run, and a
## spawn moved to the camera for the launch was written into the mapper's scene
## file (#822).
##
## Returns false if it could not be written, so the caller can say so rather than
## launching a playtest that will come up without a player.
static func write(overrides: Dictionary = {}) -> bool:
	var abs_dir := ProjectSettings.globalize_path(PATH.get_base_dir())
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	if not file:
		return false
	var out := {"stamp": Time.get_unix_time_from_system()}
	if overrides.get("spawn_position") is Vector3:
		var p: Vector3 = overrides["spawn_position"]
		out["spawn_position"] = [p.x, p.y, p.z]
		out["spawn_yaw_degrees"] = float(overrides.get("spawn_yaw_degrees", 0.0))
	if overrides.get("cordon") is AABB:
		var box: AABB = overrides["cordon"]
		var lo := box.position
		out["cordon"] = [lo.x, lo.y, lo.z, box.size.x, box.size.y, box.size.z]
	file.store_string(JSON.stringify(out))
	file.close()
	return true


## Take the request, if there is a live one.
##
## Empty when there is none. Otherwise the overrides `write()` was given, in the
## types it was given them, beside the `stamp`.
##
## Always removes the file. A request nobody collected -- a bake that was
## refused, an editor that went away -- is spent rather than lying in wait to
## turn the mapper's next ordinary run into a playtest.
static func consume() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var text := ""
	var file = FileAccess.open(PATH, FileAccess.READ)
	if file:
		text = file.get_as_text().strip_edges()
		# Closed before the remove: an open handle refuses the delete on Windows.
		file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	# A bare number is the stamp on its own, which is how this file used to look.
	var raw: Dictionary = parsed if parsed is Dictionary else {"stamp": parsed}
	var stamp_value: Variant = raw.get("stamp")
	var stamp: float = stamp_value if stamp_value is float else 0.0
	if stamp <= 0.0 or Time.get_unix_time_from_system() - stamp > WINDOW_SECONDS:
		return {}
	var request := {"stamp": stamp}
	var p: Variant = raw.get("spawn_position")
	if p is Array and (p as Array).size() == 3:
		request["spawn_position"] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		request["spawn_yaw_degrees"] = float(raw.get("spawn_yaw_degrees", 0.0))
	var c: Variant = raw.get("cordon")
	if c is Array and (c as Array).size() == 6:
		request["cordon"] = AABB(
			Vector3(float(c[0]), float(c[1]), float(c[2])),
			Vector3(float(c[3]), float(c[4]), float(c[5]))
		)
	return request
