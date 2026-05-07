extends GutTest

const HFDialogManager = preload("res://addons/hammerforge/plugin_dialogs.gd")

var base: Control


func before_each():
	base = Control.new()
	add_child_autoqfree(base)


func test_initial_count_zero():
	var mgr = HFDialogManager.new()
	assert_eq(mgr.count(), 0)


func test_add_parents_dialog_and_tracks_it():
	var mgr = HFDialogManager.new()
	var dlg = ConfirmationDialog.new()
	mgr.add(dlg, base)
	assert_eq(mgr.count(), 1)
	assert_eq(dlg.get_parent(), base)
	mgr.cleanup()


func test_add_with_null_dialog_is_noop():
	var mgr = HFDialogManager.new()
	mgr.add(null, base)
	assert_eq(mgr.count(), 0)


func test_add_with_null_base_is_noop():
	var mgr = HFDialogManager.new()
	var dlg = ConfirmationDialog.new()
	mgr.add(dlg, null)
	assert_eq(mgr.count(), 0)
	dlg.free()


func test_cleanup_frees_dialogs():
	var mgr = HFDialogManager.new()
	var dlg1 = ConfirmationDialog.new()
	var dlg2 = ConfirmationDialog.new()
	mgr.add(dlg1, base)
	mgr.add(dlg2, base)
	assert_eq(mgr.count(), 2)
	mgr.cleanup()
	assert_eq(mgr.count(), 0)


func test_dialog_removed_from_tracking_when_freed():
	var mgr = HFDialogManager.new()
	var dlg = ConfirmationDialog.new()
	mgr.add(dlg, base)
	# Simulating tree_exiting via remove_child triggers the tracker callback
	base.remove_child(dlg)
	# The tree_exiting signal may fire async; force resolution
	await get_tree().process_frame
	dlg.free()
	await get_tree().process_frame
	assert_eq(mgr.count(), 0, "tracker should have erased the freed dialog")


func test_cleanup_idempotent():
	var mgr = HFDialogManager.new()
	mgr.cleanup()
	mgr.cleanup()  # must not error
	assert_eq(mgr.count(), 0)
