extends "res://tests/mcp/mcp_dispatcher_case.gd"

## An agent places, updates and lists notes over the bridge with the entity
## tools it already has (#1700).


func test_an_agent_places_updates_and_lists_notes():
	make_level()
	var placed := await call_tool(
		"hf_place_entity",
		{
			"entity_class": "note",
			"position": [0, 1, 0],
			"properties":
			{"title": "Check the stair rise", "body": "Built from your brief", "kind": "To Do"},
		}
	)
	assert_true(placed.get("ok", false), str(placed).left(300))
	if not placed.get("ok", false):
		return
	var path := str(placed["result"]["entity"]["entity"])
	var updated := await call_tool(
		"hf_set_entity_properties", {"entity": path, "properties": {"done": true}}
	)
	assert_true(updated.get("ok", false), str(updated).left(300))
	var listed := await call_tool("hf_get_entities", {"filter": {"class": "note"}})
	assert_true(listed.get("ok", false), str(listed).left(300))
	var entities: Array = listed.get("result", {}).get("entities", [])
	assert_eq(entities.size(), 1, "one note")
	if entities.size() == 1:
		var props: Dictionary = entities[0].get("properties", {})
		assert_eq(props.get("title"), "Check the stair rise")
		assert_eq(props.get("kind"), "To Do")
		assert_eq(props.get("done"), true)
