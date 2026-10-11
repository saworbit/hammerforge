extends GutTest

## What every MCP dispatcher suite starts from: a real LevelRoot in a scene
## root, a host stand-in, and an undo stand-in over real `UndoRedo` histories,
## so an undo or a redo in a test actually runs.

const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const HFMcpProtocol = preload("res://addons/hammerforge/mcp/hf_mcp_protocol.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var host: HostStandIn
var undo
var dispatcher
var _request_count := 0


func before_each() -> void:
	_request_count = 0
	undo = UndoStandIn.new()
	host = HostStandIn.new()
	host.undo = undo
	host.tree = get_tree()
	dispatcher = HFMcpDispatcher.new(host)


func after_each() -> void:
	dispatcher.shutdown()
	undo.free_histories()


func make_scene(level: LevelRoot = null) -> Node3D:
	var scene := Node3D.new()
	scene.name = "Scene"
	if level != null:
		level.name = "LevelRoot"
		level.auto_spawn_player = false
		level.hflevel_autosave_enabled = false
		level.grid_snap = 1.0
		scene.add_child(level)
	add_child_autoqfree(scene)
	host.scene = scene
	return scene


func make_level() -> LevelRoot:
	var level := LevelRoot.new()
	make_scene(level)
	return level


## A level with the prototype palette. The editor fills an empty palette with
## these; a test is not the editor, so it has to ask.
func make_level_with_palette() -> LevelRoot:
	var level := make_level()
	level.add_prototype_materials()
	return level


func call_tool(method: String, params := {}, extra := {}) -> Dictionary:
	_request_count += 1
	var request := {
		"type": "request", "id": "r%d" % _request_count, "method": method, "params": params
	}
	request.merge(extra, true)
	return await dispatcher.handle(request)


## Place a box through the bridge and give back its brush_id.
func place_box(position := [0, 1, 0], size := [2, 2, 2]) -> String:
	var r := await call_tool("hf_place_brush", {"size": size, "position": position})
	assert_true(r.get("ok", false), "place: %s" % str(r))
	return str(r["result"]["brush"]["brush_id"]) if r.get("ok", false) else ""


func brushes(level: LevelRoot) -> Array:
	return level._iter_managed_brush_nodes()


func brush_node(level: LevelRoot, brush_id: String) -> DraftBrush:
	return level.find_brush_by_id(brush_id) as DraftBrush


func assert_refused(response: Dictionary, code: String, note := "") -> void:
	assert_false(response.get("ok", true), "%s refused: %s" % [note, str(response)])
	if response.get("ok", true):
		return
	assert_eq(response["error"]["code"], code, "%s: %s" % [note, str(response["error"])])


## The whole level and the undo history, for "a refusal changed nothing".
func snapshot(level: LevelRoot) -> Dictionary:
	return {"state": level.capture_state(false), "steps": undo.scene_history.get_history_count()}
