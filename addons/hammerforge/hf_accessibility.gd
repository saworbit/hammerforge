@tool
extends RefCounted
## What the system asks of HammerForge's interface, and what the user says (#1703).
##
## Godot reports the system's own accessibility settings: less motion, more
## contrast, less transparency, and whether a screen reader is running. A user
## who had asked the system for less motion still got sliding and fading UI, one
## who asked for more contrast had to find the High Contrast button, and a screen
## reader met the radial menu and the status lamp as nameless shapes. This is the
## one place those answers are read, and where a control is given a name and a
## place in the Tab order.

## How the interface moves: as the system asks, always, or never.
enum Motion { SYSTEM, ANIMATE, REDUCE }

## The preference the Motion setting is kept in.
const MOTION_PREF := "ui_motion"
## The Motion setting's labels, in `Motion`'s order.
const MOTION_LABELS := ["Follow system", "Animate", "Reduce"]

## The Motion setting now. The plugin sets it from the preferences.
static var motion := Motion.SYSTEM
## What a test says the system asks, in place of asking it: `{motion, contrast,
## transparency}`, each a bool. Empty asks the system.
static var system_stand_in: Dictionary = {}


## Whether the interface should appear and go at once rather than slide or fade.
## Nothing that carries meaning is lost, only the movement.
static func reduce_motion() -> bool:
	match motion:
		Motion.ANIMATE:
			return false
		Motion.REDUCE:
			return true
	return _system_asks("motion", "accessibility_should_reduce_animation")


## Whether the system asks for more contrast.
static func wants_more_contrast() -> bool:
	return _system_asks("contrast", "accessibility_should_increase_contrast")


## Whether the system asks for less transparency.
static func wants_less_transparency() -> bool:
	return _system_asks("transparency", "accessibility_should_reduce_transparency")


## Godot answers 1 for yes, 0 for no and -1 where the system cannot say.
static func _system_asks(key: String, method: String) -> bool:
	if system_stand_in.has(key):
		return bool(system_stand_in[key])
	if not DisplayServer.has_method(method):
		return false
	return int(DisplayServer.call(method)) > 0


## How a toast is read out: a refusal at once, anything else when the reader is
## free. `level` is the toast's, 0 information.
static func live_mode(level: int) -> int:
	return DisplayServer.LIVE_ASSERTIVE if level > 0 else DisplayServer.LIVE_POLITE


## Let Tab reach `button` without a click leaving the keys on it. It was kept out
## of focus so a click did not take the keys away from the viewport; now a click
## gives the focus back as soon as the button has it, and the keyboard can still
## come to it with Tab.
static func reachable(button: BaseButton) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_ALL
	if not button.gui_input.is_connected(_on_reachable_input.bind(button)):
		button.gui_input.connect(_on_reachable_input.bind(button))


static func _on_reachable_input(event: InputEvent, button: BaseButton) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		if is_instance_valid(button):
			button.release_focus.call_deferred()


## Keep `root`'s buttons in reach of Tab and its controls named, now and as
## controls are added under it later: a dock rebuilds rows as the selection
## changes. Undone when `root` leaves the tree.
static func attach(root: Control) -> void:
	for control in _interactive(root):
		_settle(control)
	var tree := root.get_tree()
	if tree == null:
		return
	_roots.append(weakref(root))
	# One connection for every root: two `bind()`s of one static function are one
	# callable to a signal, so a second root's would be refused.
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	root.tree_exiting.connect(_detach.bind(root, tree), CONNECT_ONE_SHOT)


## The roots `attach()` keeps up to date.
static var _roots: Array[WeakRef] = []


static func _detach(root: Node, tree: SceneTree) -> void:
	_roots = _roots.filter(func(ref): return ref.get_ref() != null and ref.get_ref() != root)
	if _roots.is_empty() and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


static func _on_node_added(node: Node) -> void:
	if not (node is Control):
		return
	for ref in _roots:
		var root = ref.get_ref()
		if root != null and (root as Node).is_ancestor_of(node) and _ours(node, root):
			# Its text and tooltip are often set after it is added.
			_settle.call_deferred(node)
			return


## Whether `node` is one of ours under `root`, rather than inside the internal
## children Godot builds for its own controls.
static func _ours(node: Node, root: Node) -> bool:
	var at := node
	while at != null and at != root:
		var parent := at.get_parent()
		if parent == null or not parent.get_children().has(at):
			return false
		at = parent
	return at == root


## Untyped, since a deferred call can arrive after the node was freed.
static func _settle(node) -> void:
	if not is_instance_valid(node) or not (node is Control) or _inside_spin(node):
		return
	var control := node as Control
	if control is BaseButton and control.focus_mode == Control.FOCUS_NONE:
		reachable(control)
	if _is_interactive(control) and _name_of(control) == "":
		var found := _found_name(control)
		if found != "":
			control.accessibility_name = found


## Name every interactive control under `root` that a screen reader would meet
## nameless: a button with no text takes the first line of its tooltip, and a
## field with no text of its own takes the label beside it, or its tooltip.
static func name_controls(root: Node) -> void:
	for control in _interactive(root):
		if _name_of(control) == "":
			var found := _found_name(control)
			if found != "":
				control.accessibility_name = found


## The interactive controls under `root` that have no name to give, for the test
## that keeps the list complete.
static func unnamed(root: Node) -> Array:
	var out: Array = []
	for control in _interactive(root):
		# A hidden control is never read, and the ones here take their text
		# when they show.
		if control.visible and _name_of(control) == "":
			out.append(control)
	return out


## What a screen reader reads for `control`: its accessibility name, or the text
## a button shows.
static func _name_of(control: Control) -> String:
	if control.accessibility_name.strip_edges() != "":
		return control.accessibility_name
	if control is Button and (control as Button).text.strip_edges() != "":
		return (control as Button).text
	return ""


static func _found_name(control: Control) -> String:
	var parent := control.get_parent()
	if parent != null and (not (control is Button) or control is OptionButton):
		var at := control.get_index()
		if at > 0 and parent.get_child(at - 1) is Label:
			var beside := (parent.get_child(at - 1) as Label).text.strip_edges()
			if beside != "":
				return beside.trim_suffix(":")
	var tip := control.tooltip_text.strip_edges()
	if tip != "":
		return tip.split("\n")[0]
	if control is LineEdit and (control as LineEdit).placeholder_text.strip_edges() != "":
		return (control as LineEdit).placeholder_text
	if control is CheckBox or control is CheckButton:
		return (control as Button).text
	return ""


static func _interactive(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if _is_interactive(node) and not _inside_spin(node):
			out.append(node)
		# Not into Godot's own insides, a dialog's or a tree's: Godot names those.
		for child in node.get_children():
			stack.append(child)
	return out


static func _is_interactive(node: Node) -> bool:
	if node is BaseButton or node is LineEdit:
		return true
	return node is Range and not (node is ProgressBar) and not (node is ScrollBar)


## A SpinBox's own LineEdit is read as the SpinBox.
static func _inside_spin(node: Node) -> bool:
	var parent := node.get_parent()
	return parent is SpinBox
