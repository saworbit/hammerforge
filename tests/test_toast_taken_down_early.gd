extends GutTest
## A toast panel taken down before it fades (#1326).
##
## Each toast fades out on a tween and is then freed by the tween's callback.
## The sixth toast evicts the first, and the docs capture clears every toast
## before a shot, so a panel can be freed early. The tween used to belong to the
## container and ran on, and its callback then ran with the freed panel as a
## lambda capture, which the engine reports as "Lambda capture at index 0 was
## freed", with no script line, on every such toast. A bake raises several
## toasts in a row, which is why it came up after Bake Now. The tween is now the
## panel's, and goes with it.

const HFToastType = preload("res://addons/hammerforge/ui/hf_toast.gd")

var toasts: VBoxContainer


func before_each():
	toasts = HFToastType.new()
	add_child_autofree(toasts)


## Run every tween to its end: a toast's fade is seconds long.
func _run_tweens_out() -> void:
	for tween in get_tree().get_processed_tweens():
		tween.set_speed_scale(1000.0)
	for _i in 600:
		if get_tree().get_processed_tweens().is_empty():
			break
		await get_tree().process_frame


## The panel freed the way the docs capture clears toasts, out of the tree first.
func test_a_toast_cleared_early_raises_nothing_when_its_fade_ends():
	var errors_before := get_errors().size()
	toasts.show_toast("Bake complete", 0)
	var panel: Node = toasts.get_child(0)
	toasts.remove_child(panel)
	panel.free()
	await _run_tweens_out()
	assert_eq(get_errors().size(), errors_before, "the fade's callback ran on no freed panel")
	assert_eq(toasts.get_child_count(), 0)


func test_a_toast_evicted_by_the_sixth_raises_nothing_when_its_fade_ends():
	var errors_before := get_errors().size()
	for i in HFToastType.MAX_TOASTS + 1:
		toasts.show_toast("Toast %d" % i, 0)
	assert_eq(toasts.get_child_count(), HFToastType.MAX_TOASTS, "the first was evicted")
	await _run_tweens_out()
	assert_eq(get_errors().size(), errors_before, "its fade's callback ran on no freed panel")
	assert_eq(toasts.get_child_count(), 0, "and the rest faded out")


func test_a_toast_left_alone_fades_out_and_goes():
	toasts.show_toast("Bake complete", 0)
	assert_eq(toasts.get_child_count(), 1)
	await _run_tweens_out()
	assert_eq(toasts.get_child_count(), 0, "the fade freed it")
