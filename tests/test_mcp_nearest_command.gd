extends "res://tests/mcp/mcp_dispatcher_case.gd"

## An agent that guesses a command id or a setting gets the nearest ones back,
## in the refusal's text and in `details.suggestions`, rather than every command
## there is to fix a one word slip (#1651).

const HFMcpCommands = preload("res://addons/hammerforge/mcp/hf_mcp_commands.gd")
const HFNameMatch = preload("res://addons/hammerforge/hf_name_match.gd")


func _run(command: String, args = null) -> Dictionary:
	var params := {"command": command}
	if args != null:
		params["params"] = args
	return await call_tool("hf_run_command", params)


func test_a_guessed_id_suggests_the_right_one_first():
	var cases := {
		"hollow_brush": "hollow",
		"make_arch": "create_arch",
		"move_floor": "move_to_floor",
		"hollw": "hollow",
	}
	for guess in cases:
		var near := HFMcpCommands.nearest_commands(guess)
		assert_false(near.is_empty(), "%s suggests something" % guess)
		if not near.is_empty():
			assert_eq(near[0], cases[guess], "%s suggests %s first" % [guess, cases[guess]])


func test_a_name_unlike_any_id_suggests_nothing():
	for guess in ["zzqqx", "photograph", "q", "launch_rocket"]:
		assert_eq(HFMcpCommands.nearest_commands(guess), PackedStringArray(), guess)


func test_the_refusal_names_the_suggestion_and_carries_it():
	make_level()
	var r := await _run("hollow_brush")
	assert_refused(r, HFMcpProtocol.E_UNKNOWN_COMMAND)
	if r.get("ok", true):
		return
	assert_eq(
		r["error"]["message"],
		"There is no command 'hollow_brush'. Did you mean 'hollow'? hf_list_commands lists them all."
	)
	assert_eq(r["error"]["details"]["suggestions"], ["hollow"])


func test_nothing_near_says_no_guess():
	make_level()
	var r := await _run("zzqqx")
	assert_refused(r, HFMcpProtocol.E_UNKNOWN_COMMAND)
	if r.get("ok", true):
		return
	assert_eq(
		r["error"]["message"], "There is no command 'zzqqx'. hf_list_commands lists them all."
	)
	assert_eq(r["error"]["details"]["suggestions"], [])


func test_a_misspelt_setting_names_the_nearest_key_first():
	make_level()
	var r := await _run(
		"create_arch", {"type": "stairs", "position": [0, 0, 0], "settings": {"widht": 3.0}}
	)
	assert_refused(r, HFMcpProtocol.E_INVALID_ARGUMENT)
	if r.get("ok", true):
		return
	var message: String = r["error"]["message"]
	assert_true(
		message.begins_with("A stairs has no setting widht. Did you mean 'width'? It has "), message
	)
	assert_string_contains(message, "steps", "and the full list after it")
	assert_eq(r["error"]["details"]["suggestions"], ["width"])
	assert_eq(r["error"]["details"]["param"], "params.settings.widht")


func test_edit_distance_counts_a_swap_as_one():
	assert_eq(HFNameMatch.edit_distance("widht", "width"), 1)
	assert_eq(HFNameMatch.edit_distance("kitten", "sitting"), 3)
	assert_eq(HFNameMatch.edit_distance("", "abc"), 3)
	assert_eq(HFNameMatch.edit_distance("same", "same"), 0)


func test_did_you_mean_lists_one_two_and_three():
	assert_eq(HFMcpCommands.did_you_mean(PackedStringArray()), "")
	assert_eq(HFMcpCommands.did_you_mean(PackedStringArray(["a"])), " Did you mean 'a'?")
	assert_eq(
		HFMcpCommands.did_you_mean(PackedStringArray(["a", "b"])), " Did you mean 'a' or 'b'?"
	)
	assert_eq(
		HFMcpCommands.did_you_mean(PackedStringArray(["a", "b", "c"])),
		" Did you mean 'a', 'b' or 'c'?"
	)
