@tool
class_name HFCommandLineView
extends VBoxContainer
## The line at the bottom of the Console, where a command is typed with its
## values (#1696): `hollow 0.125`, `hollow thickness=0.125`, `move to floor`.
##
## It reads the line and asks for what it leaves out; running it is the
## plugin's, through `run_requested`. Suggestions show under the line as it is
## typed, and a hint names what the command takes. Up and Down step through the
## lines run this session, and Enter on an empty line runs the last one again.

const HFCommandLine = preload("../hf_command_line.gd")

## A command read whole: run it. `line` is how the Log shows it.
signal run_requested(id: String, params: Dictionary, line: String)
## Run Script was pressed.
signal script_requested
## Escape with nothing typed and nothing asked: the overlay closes.
signal close_requested

## What the line shows while nothing is asked.
const PROMPT := ">"

var _suggestions: ItemList = null
var _hint: Label = null
var _prompt: Label = null
var _line: LineEdit = null
var _script_button: Button = null

## The lines run this session, oldest first. The plugin hands every line the
## same array, so the overlay and the Console share it.
var _history: Array = []
## Where Up and Down are in the history: its size when at the fresh line.
var _recall := 0
## A command waiting on values: `{id, params, line, asking: Array}`, or {}.
var _pending: Dictionary = {}


func _init() -> void:
	name = "CommandLine"
	add_theme_constant_override("separation", 2)
	_suggestions = ItemList.new()
	_suggestions.name = "Suggestions"
	_suggestions.visible = false
	_suggestions.auto_height = true
	_suggestions.focus_mode = Control.FOCUS_NONE
	_suggestions.item_clicked.connect(_on_suggestion_clicked)
	add_child(_suggestions)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.modulate = Color(1, 1, 1, 0.7)
	add_child(_hint)
	var row := HBoxContainer.new()
	add_child(row)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = PROMPT
	row.add_child(_prompt)
	_line = LineEdit.new()
	_line.name = "Line"
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "Type a command and its values, such as hollow 0.125"
	_line.keep_editing_on_text_submit = true
	_line.text_changed.connect(_on_text_changed)
	_line.text_submitted.connect(submit)
	_line.gui_input.connect(_on_line_input)
	row.add_child(_line)
	_script_button = Button.new()
	_script_button.name = "RunScript"
	_script_button.text = "Run Script..."
	_script_button.tooltip_text = "Run a text file of commands, one a line, each its own undo step."
	_script_button.pressed.connect(func(): script_requested.emit())
	row.add_child(_script_button)


## Put the keyboard on the line.
func focus_line() -> void:
	if _line.is_inside_tree():
		_line.grab_focus()


## The lines run this session, oldest first.
func history() -> Array:
	return _history


## Share `lines` as the history, kept by reference.
func set_history(lines: Array) -> void:
	_history = lines
	_recall = _history.size()


## Say `message` under the line.
func say(message: String) -> void:
	_hint.text = message


## What a value the line is waiting on: the prompt, or "" when it waits on none.
func asking() -> String:
	return _prompt.text if not _pending.is_empty() else ""


## Enter: read the line and run it, or take the value it asked for.
func submit(text: String) -> void:
	if not _pending.is_empty():
		_answer(text.strip_edges())
		return
	var line := text.strip_edges()
	if line == "":
		if _history.is_empty():
			return
		line = _history[_history.size() - 1]
	var read := HFCommandLine.read(line)
	if not read["ok"]:
		say(read["message"])
		return
	_line.clear()
	_suggestions.visible = false
	var wanted := HFCommandLine.to_ask(read["id"], read["params"])
	if wanted.is_empty():
		_finish(read["id"], read["params"], line)
		return
	_pending = {"id": read["id"], "params": read["params"], "line": line, "asking": wanted}
	_ask()


## Escape: let go of a value being asked for, or of what is typed.
func cancel() -> void:
	if _pending.is_empty() and _line.text.strip_edges() == "":
		close_requested.emit()
		return
	if not _pending.is_empty():
		say("Cancelled %s." % _pending["id"])
	_pending = {}
	_prompt.text = PROMPT
	_line.clear()
	_suggestions.visible = false


func _ask() -> void:
	var field_def: Dictionary = _pending["asking"][0]
	_prompt.text = HFCommandLine.prompt(field_def)
	say(HFCommandLine.hint(_pending["id"]))


func _answer(typed: String) -> void:
	var field_def: Dictionary = _pending["asking"][0]
	var key := str(field_def["key"])
	if typed == "":
		# Enter takes the default, or leaves out a value the command does
		# without; only a required one with no default has to be typed.
		if field_def.has("default"):
			_pending["params"][key] = field_def["default"]
		elif bool(field_def.get("required", false)):
			say("%s needs a value. Escape cancels." % key)
			return
	else:
		var read := HFCommandLine.value_of(field_def, typed)
		if not read["ok"]:
			say(read["message"])
			return
		_pending["params"][key] = read["value"]
	_line.clear()
	(_pending["asking"] as Array).pop_front()
	if not (_pending["asking"] as Array).is_empty():
		_ask()
		return
	var pending := _pending
	_pending = {}
	_prompt.text = PROMPT
	_finish(
		pending["id"], pending["params"], HFCommandLine.line_for(pending["id"], pending["params"])
	)


func _finish(id: String, params: Dictionary, line: String) -> void:
	if _history.is_empty() or _history[_history.size() - 1] != line:
		_history.append(line)
	_recall = _history.size()
	say("")
	run_requested.emit(id, params, line)


func _on_text_changed(text: String) -> void:
	if not _pending.is_empty():
		return
	var typed := HFCommandLine.words(text)
	var found := HFCommandLine.command_of(typed)
	if not found.is_empty() and (int(found["used"]) < typed.size() or text.ends_with(" ")):
		_suggestions.visible = false
		say(HFCommandLine.hint(found["id"]))
		return
	_suggestions.clear()
	for id in HFCommandLine.suggestions(text):
		_suggestions.add_item(id)
	_suggestions.visible = _suggestions.item_count > 0
	say("" if found.is_empty() else HFCommandLine.hint(found["id"]))


func _on_suggestion_clicked(index: int, _at: Vector2, _button: int) -> void:
	_take_suggestion(index)


func _take_suggestion(index: int) -> void:
	if index < 0 or index >= _suggestions.item_count:
		return
	var id := _suggestions.get_item_text(index)
	_line.text = id + " "
	_line.caret_column = _line.text.length()
	_on_text_changed(_line.text)
	focus_line()


func _on_line_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_UP:
			_step_history(-1)
		KEY_DOWN:
			_step_history(1)
		KEY_TAB:
			if _suggestions.visible:
				_take_suggestion(0)
		KEY_ESCAPE:
			cancel()
		_:
			return
	_line.accept_event()


func _step_history(step: int) -> void:
	if _history.is_empty() or not _pending.is_empty():
		return
	_recall = clampi(_recall + step, 0, _history.size())
	_line.text = _history[_recall] if _recall < _history.size() else ""
	_line.caret_column = _line.text.length()
