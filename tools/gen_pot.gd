extends SceneTree
## Write `addons/hammerforge/translations/hammerforge.pot` from the addon's
## scripts, scenes and command registry (#1702).
##
## Usage:
##   godot --headless -s res://tools/gen_pot.gd --path .
##
## `tests/test_translation.gd` fails when the committed file is not what this
## writes, so a pull request that changes a label runs this too.

const PotCatalog = preload("res://tools/pot_catalog.gd")


func _init() -> void:
	# First, so a script error further down still ends the run, and ends it as a
	# failure, rather than leaving Godot waiting with no scene.
	quit(1)
	var file := FileAccess.open(PotCatalog.PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % PotCatalog.PATH)
		return
	file.store_string(PotCatalog.build())
	file.close()
	print("Wrote %s" % PotCatalog.PATH)
	quit(0)
