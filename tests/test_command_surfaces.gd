extends GutTest
## Every command id a surface can send is one the command table knows.
##
## `HFPluginCommands.execute()` runs only ids `HFCommandRegistry` lists, and logs
## and ignores anything else, so an id missing from the table is a button that
## does nothing. This presses every button of the context toolbar and every item
## of the viewport menu and listens for what they send, and reads the radial
## menu's segments and the keymap's actions, rather than reading their sources.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFContextToolbar = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")
const HFViewportContextMenu = preload("res://addons/hammerforge/ui/hf_viewport_context_menu.gd")
const HFRadialMenu = preload("res://addons/hammerforge/ui/hf_radial_menu.gd")

var _sent: Array = []


func _record(action: String, _args: Array = []) -> void:
	if not _sent.has(action):
		_sent.append(action)


func _unknown(actions: Array) -> Array:
	var out: Array = []
	for action in actions:
		if not HFCommandRegistry.dispatches(str(action)):
			out.append(action)
	return out


func test_every_context_toolbar_button_sends_a_known_command():
	_sent.clear()
	var toolbar := HFContextToolbar.new()
	add_child_autoqfree(toolbar)
	toolbar.action_requested.connect(_record)
	for button in toolbar.find_children("*", "BaseButton", true, false):
		if (button as BaseButton).toggle_mode:
			button.toggled.emit(true)
		else:
			button.pressed.emit()
	assert_gt(_sent.size(), 20, "the toolbar's buttons were pressed")
	assert_eq(_unknown(_sent), [], "every toolbar button names a command")


func test_every_viewport_menu_item_sends_a_known_command():
	_sent.clear()
	var menu := HFViewportContextMenu.new()
	add_child_autoqfree(menu)
	menu.action_requested.connect(_record)
	var constants: Dictionary = menu.get_script().get_script_constant_map()
	for key in constants:
		if str(key).begins_with("_ID_") and key != "_ID_GRID_BASE":
			menu._on_id_pressed(int(constants[key]))
	menu._on_grid_id_pressed(int(constants["_ID_GRID_BASE"]))
	assert_gt(_sent.size(), 40, "the menu's items were pressed")
	assert_eq(_unknown(_sent), [], "every menu item names a command")


func test_every_radial_segment_names_a_known_command():
	var actions: Array = []
	for segment in HFRadialMenu.SEGMENTS:
		actions.append(segment["action"])
	assert_gt(actions.size(), 0)
	assert_eq(_unknown(actions), [], "every segment names a command")


func test_every_key_binding_names_a_known_command():
	var actions := Array(HFKeymap.load_or_default("").get_actions())
	assert_gt(actions.size(), 50)
	assert_eq(_unknown(actions), [], "every binding names a command")
