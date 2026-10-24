@tool
class_name HFFileNames
extends RefCounted
## The one set of rules for turning a name the mapper typed into a file name.
##
## Prefab names were hardened in #667 and brush preset names kept a copy that
## replaced a few characters and nothing else, so a preset renamed `CON` or
## `..x` went to a file Godot would not open or a file nobody could see, and a
## second preset of one name was `_1` where a prefab's was `_2` (#1464). Both
## come here now.

## Longest stem a name keeps, before the extension. The usual filesystem limit
## is 255 bytes for the whole name, and a name the panel's list cannot show is
## not a name anybody wanted.
const MAX_STEM_LENGTH := 200

## Names Windows treats as devices whatever extension follows them. Godot's own
## Windows file access refuses the same list, superscript digits included, and
## judges a name by what comes before its first dot, so `con.wall.tres` is
## refused as surely as `CON.tres`.
const RESERVED_NAMES := [
	"CON",
	"PRN",
	"AUX",
	"NUL",
	"COM0",
	"COM1",
	"COM2",
	"COM3",
	"COM4",
	"COM5",
	"COM6",
	"COM7",
	"COM8",
	"COM9",
	"COM¹",
	"COM²",
	"COM³",
	"LPT0",
	"LPT1",
	"LPT2",
	"LPT3",
	"LPT4",
	"LPT5",
	"LPT6",
	"LPT7",
	"LPT8",
	"LPT9",
	"LPT¹",
	"LPT²",
	"LPT³",
]


## `file_name` as a stem that stays in the folder it is saved to, is not hidden,
## and that every platform can open. `fallback` when nothing usable is left, and
## a device name gets `_kind` after it ("CON" becomes "CON_preset").
##
## `validate_filename()` is the engine's own rule for the characters a
## filesystem refuses and replaces every separator, so a name cannot point
## anywhere but here. Leading dots are what a traversal is made of, and a file
## starting with one is hidden on every platform that matters. The caller does
## its own case and spacing first: a prefab name is snake_cased, a preset keeps
## its case.
static func safe_file_stem(file_name: String, fallback: String, kind: String) -> String:
	var cleaned := file_name.validate_filename().strip_edges()
	while cleaned.begins_with("."):
		cleaned = cleaned.substr(1)
	if cleaned == "":
		cleaned = fallback
	# `validate_filename()` does not know about names a filesystem refuses.
	var device := cleaned.get_slice(".", 0)
	if RESERVED_NAMES.has(device.to_upper()):
		cleaned = "%s_%s%s" % [device, kind, cleaned.substr(device.length())]
	return cleaned.left(MAX_STEM_LENGTH)


## `dir_path/stem.ext`, or the first of stem_2, stem_3 and so on that no file
## uses yet. A numbered stem is cut to make room for its number, so it stays
## inside `MAX_STEM_LENGTH` and comes back unchanged through `safe_file_stem()`.
static func unused_path(dir_path: String, stem: String, ext: String) -> String:
	var path := dir_path.path_join("%s.%s" % [stem, ext])
	var n := 2
	while FileAccess.file_exists(path):
		var number := "_%d" % n
		path = dir_path.path_join(
			"%s%s.%s" % [stem.left(MAX_STEM_LENGTH - number.length()), number, ext]
		)
		n += 1
	return path
