extends GutTest

## The shipped examples' cuts load as cuts (#1814). They were marked with
## operation 1, which Godot reads as Intersection, so the corridor had no
## doorway and the hollowed building was a solid block.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFExampleLibrary = preload("res://addons/hammerforge/ui/hf_example_library.gd")

var dock: HammerForgeDock
var root: LevelRoot
var library: HFExampleLibrary


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	library = HFExampleLibrary.new()
	add_child_autofree(library)


func after_each() -> void:
	dock = null
	root = null
	library = null


func _load(example_id: String) -> void:
	dock._apply_example_data(library.get_example_data(example_id))


func _cuts() -> Array:
	var out: Array = []
	for node in root.draft_brushes_node.get_children():
		if node is DraftBrush and node.operation == CSGShape3D.OPERATION_SUBTRACTION:
			out.append(node)
	return out


func test_the_corridor_loads_with_its_doorway_cut():
	_load("corridor")
	assert_eq(_cuts().size(), 1, "the doorway is a cut")
	assert_eq(root.validation_system.cuts_that_cut_nothing(), [], "and it cuts the wall")


func test_the_hollowed_building_loads_hollow_with_its_windows():
	_load("hollow_building")
	assert_eq(_cuts().size(), 4, "the interior and three windows are cuts")
	assert_eq(root.validation_system.cuts_that_cut_nothing(), [], "each cuts the shell")


func test_every_shipped_example_validates_clean():
	for example in library._examples:
		var example_id := str(example["id"])
		_load(example_id)
		var issues: Array = root.validate_level(false).get("issues", [])
		assert_eq(issues, [], "%s validates clean" % example_id)
