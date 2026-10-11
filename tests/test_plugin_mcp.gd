extends GutTest

## The plugin side of the MCP bridge: the Test tab panel, and turning the
## listener on and off from it. A stand-in plugin carries the fields and the two
## delegates the real one has, and a test host stands in for the editor.

const HFPluginMcp = preload("res://addons/hammerforge/plugin_mcp.gd")
const HFMcpPanel = preload("res://addons/hammerforge/ui/hf_mcp_panel.gd")
const HFMcpListener = preload("res://addons/hammerforge/mcp/hf_mcp_listener.gd")
const HFStatusBoard = preload("res://addons/hammerforge/hf_status_board.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")

const DISCOVERY := "user://mcp_plugin_test/hammerforge_mcp.json"


class FakeDock:
	extends Node

	var mcp_panel = null


class FakePlugin:
	extends Node

	var dock = null
	var mcp_dispatcher = null
	var mcp_listener: Node = null
	# Test seams the real plugin does not declare; plugin_mcp reads them with
	# get(), which gives null on the real one.
	var mcp_allow_outside_editor := true
	var mcp_discovery_path := DISCOVERY

	func _on_mcp_enable_toggled(enabled: bool) -> void:
		HFPluginMcp.set_enabled(self, enabled)

	func _on_mcp_state_changed(state: int, detail: String) -> void:
		HFPluginMcp.show_state(self, state, detail)

	func _on_mcp_command_finished(method: String, ok: bool, code: String, ms: int) -> void:
		HFPluginMcp.show_last(self, method, ok, code, ms)


var plugin: FakePlugin
var panel
var undo
var host


func before_each() -> void:
	undo = UndoStandIn.new()
	host = HostStandIn.new()
	host.undo = undo
	host.tree = get_tree()
	plugin = FakePlugin.new()
	plugin.dock = FakeDock.new()
	panel = HFMcpPanel.new()
	plugin.dock.mcp_panel = panel
	plugin.dock.add_child(panel)
	plugin.add_child(plugin.dock)
	add_child_autoqfree(plugin)


func after_each() -> void:
	HFPluginMcp.teardown(plugin)
	undo.free_histories()


# --- Panel -----------------------------------------------------------------


func test_panel_starts_off_and_unticked():
	assert_false(panel.is_enabled())
	assert_eq(panel.status_label.text, "Off")
	assert_eq(panel.lamp.severity, HFStatusBoard.Severity.UNKNOWN)
	assert_string_contains(panel.enable_check.text, "MCP")


func test_ticking_the_box_asks_to_enable():
	watch_signals(panel)
	panel.enable_check.button_pressed = true
	assert_signal_emitted_with_parameters(panel, "enable_toggled", [true])


func test_panel_states():
	panel.enable_check.set_pressed_no_signal(true)
	panel.set_state(HFMcpListener.State.LISTENING, "Listening on 127.0.0.1:5")
	assert_eq(panel.status_label.text, "Listening on 127.0.0.1:5")
	assert_eq(panel.lamp.severity, HFStatusBoard.Severity.WARN)
	assert_true(panel.is_enabled())
	panel.set_state(HFMcpListener.State.CONNECTED, "Agent connected")
	assert_eq(panel.lamp.severity, HFStatusBoard.Severity.OK)
	panel.set_state(HFMcpListener.State.RUNNING, "Running: place brush")
	assert_eq(panel.lamp.severity, HFStatusBoard.Severity.OK)
	assert_eq(panel.status_label.text, "Running: place brush")
	panel.set_state(HFMcpListener.State.FAILED, "Could not open a port")
	assert_eq(panel.lamp.severity, HFStatusBoard.Severity.PROBLEM)
	assert_false(panel.is_enabled(), "a failure unticks the box")
	panel.enable_check.set_pressed_no_signal(true)
	panel.set_state(HFMcpListener.State.OFF, "Off")
	assert_false(panel.is_enabled())


func test_setting_a_state_does_not_ask_to_enable_again():
	watch_signals(panel)
	panel.set_state(HFMcpListener.State.FAILED, "x")
	assert_signal_not_emitted(panel, "enable_toggled")


# --- Turning it on and off -------------------------------------------------


func test_setup_makes_the_dispatcher_and_leaves_the_listener_off():
	HFPluginMcp.setup(plugin, host)
	assert_not_null(plugin.mcp_dispatcher)
	assert_null(plugin.mcp_listener)
	assert_false(FileAccess.file_exists(DISCOVERY))


func test_ticking_the_box_starts_the_listener():
	HFPluginMcp.setup(plugin, host)
	panel.enable_check.button_pressed = true
	assert_not_null(plugin.mcp_listener)
	assert_eq(plugin.mcp_listener.get_parent(), plugin)
	assert_gt(plugin.mcp_listener.port(), 0)
	assert_true(FileAccess.file_exists(DISCOVERY))
	assert_string_contains(panel.status_label.text, "Listening on 127.0.0.1:")
	panel.enable_check.button_pressed = false
	assert_false(FileAccess.file_exists(DISCOVERY))
	assert_eq(panel.status_label.text, "Off")


func test_a_listener_that_cannot_start_unticks_the_box_and_says_why():
	plugin.mcp_allow_outside_editor = false
	HFPluginMcp.setup(plugin, host)
	panel.enable_check.button_pressed = true
	assert_false(panel.is_enabled())
	assert_eq(panel.lamp.severity, HFStatusBoard.Severity.PROBLEM)
	assert_string_contains(panel.status_label.text, "editor")
	assert_false(FileAccess.file_exists(DISCOVERY))


func test_teardown_stops_and_frees_everything():
	HFPluginMcp.setup(plugin, host)
	panel.enable_check.button_pressed = true
	var listener: Node = plugin.mcp_listener
	HFPluginMcp.teardown(plugin)
	assert_false(FileAccess.file_exists(DISCOVERY))
	assert_null(plugin.mcp_listener)
	assert_null(plugin.mcp_dispatcher)
	assert_null(listener.get_parent(), "taken out of the tree before it is freed")
	assert_false(panel.enable_toggled.is_connected(Callable(plugin, "_on_mcp_enable_toggled")))


func test_teardown_twice_is_harmless():
	HFPluginMcp.setup(plugin, host)
	HFPluginMcp.teardown(plugin)
	HFPluginMcp.teardown(plugin)
	assert_null(plugin.mcp_dispatcher)


func test_the_panel_says_what_the_agent_last_did():
	HFPluginMcp.setup(plugin, host)
	assert_false(panel.last_label.visible, "nothing yet")
	panel.enable_check.button_pressed = true
	var listener = plugin.mcp_listener
	listener.command_finished.emit("hf_place_brush", true, "", 14)
	assert_eq(panel.last_label.text, "Last: place brush, 14 ms")
	assert_true(panel.last_label.visible)
	listener.command_finished.emit("hf_undo", false, "undo_conflict", 3)
	assert_eq(panel.last_label.text, "Last: undo refused: undo_conflict")
	listener.command_finished.emit("hf_get_status", true, "", 1)
	assert_eq(panel.last_label.text, "Last: undo refused: undo_conflict", "status is left out")
	listener.command_finished.emit("hf_bake", false, "internal_error", 9)
	assert_string_contains(panel.last_label.text, "script error")
	panel.enable_check.button_pressed = false
	assert_false(panel.last_label.visible, "off clears it")
	assert_false(
		listener.command_finished.is_connected(Callable(plugin, "_on_mcp_command_finished")),
		"let go when the listener stops"
	)
