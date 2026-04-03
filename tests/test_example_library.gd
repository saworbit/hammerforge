extends GutTest

const HFExampleLibrary = preload("res://addons/hammerforge/ui/hf_example_library.gd")

var library: HFExampleLibrary


func before_each():
	library = HFExampleLibrary.new()
	add_child(library)


func after_each():
	library.free()
	library = null


# ===========================================================================
# Data loading
# ===========================================================================


func test_examples_loaded():
	assert_gt(library.get_example_count(), 0)


func test_at_least_five_examples():
	assert_gte(library.get_example_count(), 5)


func test_get_example_by_id():
	var data := library.get_example_data("simple_room")
	assert_false(data.is_empty())
	assert_eq(data["title"], "Simple Room")


func test_get_unknown_example():
	var data := library.get_example_data("nonexistent_level")
	assert_true(data.is_empty())


func test_all_examples_have_required_fields():
	for example in library._examples:
		assert_true(example.has("id"), "Missing id")
		assert_true(example.has("title"), "Missing title")
		assert_true(example.has("description"), "Missing description")
		assert_true(example.has("difficulty"), "Missing difficulty")
		assert_true(example.has("brushes"), "Missing brushes")


func test_simple_room_has_brushes():
	var data := library.get_example_data("simple_room")
	var brushes: Array = data.get("brushes", [])
	assert_gt(brushes.size(), 0)


func test_corridor_has_subtract():
	var data := library.get_example_data("corridor")
	var brushes: Array = data.get("brushes", [])
	var has_subtract := false
	for brush in brushes:
		if brush.get("operation", 0) == 1:
			has_subtract = true
			break
	assert_true(has_subtract)


func test_jump_puzzle_has_entities():
	var data := library.get_example_data("jump_puzzle")
	var entities: Array = data.get("entities", [])
	assert_gt(entities.size(), 0)


func test_all_brushes_have_position_and_size():
	for example in library._examples:
		for brush in example.get("brushes", []):
			assert_true(brush.has("position"), "Brush missing position in %s" % example["id"])
			assert_true(brush.has("size"), "Brush missing size in %s" % example["id"])
			assert_eq(brush["position"].size(), 3, "Position should be [x,y,z]")
			assert_eq(brush["size"].size(), 3, "Size should be [x,y,z]")


func test_all_entities_have_type_and_position():
	for example in library._examples:
		for entity in example.get("entities", []):
			assert_true(entity.has("type"), "Entity missing type in %s" % example["id"])
			assert_true(entity.has("position"), "Entity missing position in %s" % example["id"])


# ===========================================================================
# Annotations
# ===========================================================================


func test_examples_have_annotations():
	for example in library._examples:
		assert_true(example.has("annotations"), "Missing annotations in %s" % example["id"])
		assert_gt(example["annotations"].size(), 0, "No annotations in %s" % example["id"])


func test_annotations_have_text():
	for example in library._examples:
		for ann in example.get("annotations", []):
			assert_true(ann.has("text"), "Annotation missing text in %s" % example["id"])
			assert_gt(ann["text"].length(), 0, "Empty annotation text in %s" % example["id"])


# ===========================================================================
# Search filtering
# ===========================================================================


func test_search_filters_cards():
	library._on_search_changed("corridor")
	var visible_count := 0
	for i in range(library._cards_container.get_child_count()):
		if library._cards_container.get_child(i).visible:
			visible_count += 1
	assert_eq(visible_count, 1)


func test_empty_search_shows_all():
	library._on_search_changed("corridor")
	library._on_search_changed("")
	var visible_count := 0
	for i in range(library._cards_container.get_child_count()):
		if library._cards_container.get_child(i).visible:
			visible_count += 1
	assert_eq(visible_count, library.get_example_count())


func test_search_by_tag():
	library._on_search_changed("subtract")
	var visible_count := 0
	for i in range(library._cards_container.get_child_count()):
		if library._cards_container.get_child(i).visible:
			visible_count += 1
	assert_gt(visible_count, 0)


func test_search_by_difficulty():
	library._on_search_changed("advanced")
	var visible_count := 0
	for i in range(library._cards_container.get_child_count()):
		if library._cards_container.get_child(i).visible:
			visible_count += 1
	assert_gt(visible_count, 0)


# ===========================================================================
# Load signal
# ===========================================================================


func test_load_signal():
	var received := []
	library.load_requested.connect(func(id): received.append(id))
	library._on_load_pressed("simple_room")
	assert_eq(received, ["simple_room"])


# ===========================================================================
# UI cards
# ===========================================================================


func test_cards_created():
	assert_eq(library._cards_container.get_child_count(), library.get_example_count())


# ===========================================================================
# Brush info key mapping (integration check)
# ===========================================================================


func test_brush_data_uses_position_array():
	# The JSON stores brush positions as "position" arrays, which the dock
	# must map to "center" when building the info dict for hf_brush_system.
	# This test verifies the JSON data structure is consistent.
	var data := library.get_example_data("corridor")
	for brush in data.get("brushes", []):
		var pos: Array = brush.get("position", [])
		assert_eq(pos.size(), 3, "Position must be [x,y,z]")
		# Verify values are numbers, not null
		for v in pos:
			assert_true(v is float or v is int, "Position component must be numeric")


func test_difficulty_colors_defined():
	assert_true(HFExampleLibrary.DIFFICULTY_COLORS.has("Beginner"))
	assert_true(HFExampleLibrary.DIFFICULTY_COLORS.has("Intermediate"))
	assert_true(HFExampleLibrary.DIFFICULTY_COLORS.has("Advanced"))
