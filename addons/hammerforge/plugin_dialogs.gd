@tool
class_name HFDialogManager
extends RefCounted
## Tracks confirmation dialogs spawned by the plugin so they can be torn down
## cleanly on plugin reload. Extracted from plugin.gd.
##
## Use:
##   var dlg = ConfirmationDialog.new()
##   dialog_manager.add(dlg, base_control)
##   ...
##   dlg.popup_centered()
##
## On plugin _exit_tree, call `cleanup()` to free any open dialogs.

var _pending: Array = []  # Array[ConfirmationDialog]


## Parent a dialog to the editor base control and track it for cleanup.
## Auto-removes from the tracking list when the dialog leaves the tree.
func add(dlg: AcceptDialog, base_control: Control) -> void:
	if not dlg or not base_control:
		return
	base_control.add_child(dlg)
	_pending.append(dlg)
	dlg.tree_exiting.connect(func(): _pending.erase(dlg))


## Free all tracked dialogs. Idempotent — safe to call repeatedly.
func cleanup() -> void:
	for dlg in _pending.duplicate():
		if is_instance_valid(dlg):
			dlg.queue_free()
	_pending.clear()


func count() -> int:
	return _pending.size()
