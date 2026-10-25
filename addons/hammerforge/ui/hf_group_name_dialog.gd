@tool
extends RefCounted
## The question Group Selection and Rename Group ask: a name, with one ready to
## take (#1723). Enter takes it.


## A dialog asking for a name, `text` filled in and selected, that calls
## `on_name` with what was typed, or `text` when the field was left empty. Not
## added to the tree: the caller does that, so it goes where its dialogs go.
static func make(title: String, text: String, on_name: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.min_size = Vector2i(320, 90)
	var line := LineEdit.new()
	line.name = "GroupName"
	line.text = text
	line.accessibility_name = "Group name"
	line.select_all_on_focus = true
	dialog.add_child(line)
	dialog.register_text_enter(line)
	dialog.confirmed.connect(
		func():
			var typed := line.text.strip_edges()
			on_name.call(typed if typed != "" else text)
	)
	dialog.visibility_changed.connect(
		func():
			if dialog.visible and is_instance_valid(line):
				line.grab_focus.call_deferred()
	)
	return dialog
