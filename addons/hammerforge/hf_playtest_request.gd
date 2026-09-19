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
## Returns false if it could not be written, so the caller can say so rather than
## launching a playtest that will come up without a player.
static func write() -> bool:
	var abs_dir := ProjectSettings.globalize_path(PATH.get_base_dir())
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(str(Time.get_unix_time_from_system()))
	file.close()
	return true


## Take the request, if there is a live one.
##
## Always removes the file. A request nobody collected -- a bake that was
## refused, an editor that went away -- is spent rather than lying in wait to
## turn the mapper's next ordinary run into a playtest.
static func consume() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var stamp := 0.0
	var file = FileAccess.open(PATH, FileAccess.READ)
	if file:
		stamp = file.get_as_text().strip_edges().to_float()
		# Closed before the remove: an open handle refuses the delete on Windows.
		file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if stamp <= 0.0:
		return false
	return Time.get_unix_time_from_system() - stamp <= WINDOW_SECONDS
