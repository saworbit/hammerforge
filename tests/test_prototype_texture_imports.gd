extends GutTest

## The prototype textures ship with the import settings the editor gives them for
## 3D use (#1043).
##
## 131 of the 150 asked the editor to watch for 3D use (`detect_3d/compress_to=1`).
## Every one is used on a brush, so the first windowed open of any project with
## the addon rewrote all 131, reimported them, logged about 95 "Task 'reimport'
## already exists" errors while those overlapped, and in this repository left up
## to 131 tracked files modified. Shipped as the editor leaves them, there is
## nothing for it to change.

const PROTOTYPES := "res://addons/hammerforge/textures/prototypes"


func _imports() -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(PROTOTYPES):
		if file.ends_with(".svg.import"):
			found.append(PROTOTYPES.path_join(file))
	return found


func test_every_prototype_texture_has_an_import_file():
	assert_gt(_imports().size(), 100, "fixture: the prototype set is there")


func test_no_prototype_texture_waits_to_be_detected_as_3d():
	var waiting: Array = []
	for path in _imports():
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("\ndetect_3d/compress_to=0"):
			waiting.append(path.get_file())
	assert_eq(waiting, [], "%d would be reimported on first use" % waiting.size())


func test_each_is_already_set_up_for_3d():
	var flat: Array = []
	for path in _imports():
		var text := FileAccess.get_file_as_string(path)
		if not (text.contains("\ncompress/mode=2") and text.contains("\nmipmaps/generate=true")):
			flat.append(path.get_file())
	assert_eq(flat, [], "VRAM compressed with mipmaps, as the editor sets them for 3D")
