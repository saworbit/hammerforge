extends GutTest

## No file Godot reads as text starts with a byte order mark.
##
## The two sample scenes and their spawner script were committed with one. A
## scene still loaded, but every import scan of the project printed a parse
## error for each, "Expected '['", which reads as a broken project to anyone
## opening it, and hides a real error printed beside them.

const KINDS := ["gd", "tscn", "tres", "cfg", "godot", "gdshader", "import"]
const BOM := [0xEF, 0xBB, 0xBF]


func test_no_text_file_godot_reads_starts_with_a_byte_order_mark():
	var marked: Array = []
	var seen := _walk("res://", marked)
	assert_gt(seen, 100, "the walk reached the project's files")
	assert_eq(marked, [], "files that start with a byte order mark")


## How many files of `KINDS` under `dir`, with each that starts with a mark added
## to `marked`. Hidden folders, `.godot` and `.git` among them, are left out.
func _walk(dir: String, marked: Array) -> int:
	var seen := 0
	var access := DirAccess.open(dir)
	if access == null:
		return 0
	access.include_hidden = false
	for sub in access.get_directories():
		if not sub.begins_with("."):
			seen += _walk(dir.path_join(sub), marked)
	for file_name in access.get_files():
		if not KINDS.has(file_name.get_extension()):
			continue
		seen += 1
		var path := dir.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() >= 3 and Array(file.get_buffer(3)) == BOM:
			marked.append(path)
	return seen
