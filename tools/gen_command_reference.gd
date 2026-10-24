extends SceneTree
## Write `docs/commands.md` from the command registry (#1658).
##
## Usage:
##   godot --headless -s res://tools/gen_command_reference.gd --path .
##
## `tests/test_command_reference.gd` fails when the committed page is not what
## this writes, so a pull request that changes the registry runs this too.

const CommandReference = preload("res://tools/command_reference.gd")


func _init() -> void:
	# First, so a script error further down still ends the run, and ends it as a
	# failure, rather than leaving Godot waiting with no scene.
	quit(1)
	var file := FileAccess.open(CommandReference.PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % CommandReference.PATH)
		return
	file.store_string(CommandReference.build())
	file.close()
	print("Wrote %s" % CommandReference.PATH)
	quit(0)
