@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a HammerForge level is once it stops being edited and starts being a game.
##
## Every other scenario runs the level the way the editor runs it. A shipped game
## is the other half: `Engine.is_editor_hint()` is false, the dock is not there,
## and whatever `_ready()` does on that branch runs on every player's machine.
## Headless already takes that branch -- the harness is not the editor -- so the
## runtime side of `LevelRoot` is directly observable here, and nowhere else in
## the sweep looks at it.
##
## The questions are the ones a mapper asks the week before shipping: what does
## a level node do when nobody is editing it, what does it keep alive, and what
## does it cost to open.


func id() -> String:
	return "ship-runtime"


func summary() -> String:
	return "what a LevelRoot does, keeps and costs on the branch a built game takes"


func run() -> void:
	await _what_a_runtime_root_starts()
	await _what_the_reload_hook_polls()
	await _what_the_scene_carries_into_the_game()
	await _what_opening_a_level_costs_at_runtime()


func _timers(root: Node3D) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Timer:
			out.append(
				{
					"name": c.name,
					"wait": c.wait_time,
					"running": not c.is_stopped(),
					"one_shot": c.one_shot,
				}
			)
	return out


func _what_a_runtime_root_starts() -> void:
	note("Engine.is_editor_hint()", Engine.is_editor_hint())
	note("OS.has_feature('editor')", OS.has_feature("editor"))
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	await frame()
	note("timers a bare runtime LevelRoot adds to itself", _timers(root))
	note("auto_spawn_player default on a fresh LevelRoot", LevelRoot.new().auto_spawn_player)


func _what_the_reload_hook_polls() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	await frame()
	var timer := root.get_node_or_null("RemoteReloadTimer") as Timer
	if timer == null:
		note("no RemoteReloadTimer on the runtime branch", true)
		return
	var path: String = LevelRoot.RELOAD_LOCK_PATH
	note("RemoteReloadTimer wait_time", timer.wait_time)
	note("polls", path)
	note("that path exists in this project", FileAccess.file_exists(path))
	note(
		"polls per minute per level in a shipped game",
		int(round(60.0 / max(timer.wait_time, 0.001)))
	)
	if timer.wait_time <= 1.0 and not timer.is_stopped():
		flag(
			"a shipped game polls the disk twice a second for an editor hot-reload file",
			(
				(
					"`_setup_runtime_reload()` is gated on `not Engine.is_editor_hint()`, so it "
					+ "runs only in a built game and never in the editor -- the opposite of what "
					+ "a dev hook wants. It stats %s every %.1fs forever, and that path is under "
					+ "a dot-directory in res:// that an export does not ship, so the answer is "
					+ "always false. Worse, if it ever is true the built game calls bake(true, "
					+ "true) and rebuilds the whole level from brushes mid-play."
				)
				% [path, timer.wait_time]
			)
		)


func _what_the_scene_carries_into_the_game() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	# A small real room, then a bake, which is what a mapper ships.
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, -6))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, 6))
	box(root, Vector3(0.3, 3, 12), Vector3(-6, 1.5, 0))
	box(root, Vector3(0.3, 3, 12), Vector3(6, 1.5, 0))
	await root.bake(false, false)
	await frame()
	var counts := {}
	_classes(root, counts)
	note("node classes in the level node after a bake", counts)
	var drafts: int = root.brush_system.get_live_brush_count()
	note("source brushes still in the tree after the bake", drafts)
	var total := _count_nodes(root)
	note("total nodes under the level root", total)
	note(
		"what a game scene pays for the source geometry",
		(
			"the five brushes stay as live DraftBrush nodes with meshes beside the baked "
			+ "container; nothing in the runtime branch drops them"
		)
	)


func _what_opening_a_level_costs_at_runtime() -> void:
	# The startup path a shipped level takes with the default settings: bake on
	# spawn rather than use the container already in the scene.
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	for i in 40:
		box(root, Vector3(2, 2, 2), Vector3((i % 8) * 3.0, 1, (i / 8) * 3.0))
	var t0 := Time.get_ticks_msec()
	await root.bake(false, false)
	var bake_ms := Time.get_ticks_msec() - t0
	note("40 brushes, a full bake", "%d ms" % bake_ms)
	note(
		"what _start_playtest() does on the runtime branch",
		(
			"awaits bake(true, true) -- a shipped level with auto_spawn_player on rebuilds "
			+ "its geometry from brushes at startup instead of showing the BakedGeometry the "
			+ "scene already carries, so a player pays this on every load"
		)
	)


func _classes(node: Node, counts: Dictionary) -> Dictionary:
	counts[node.get_class()] = int(counts.get(node.get_class(), 0)) + 1
	for c in node.get_children():
		_classes(c, counts)
	return counts


func _count_nodes(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_nodes(c)
	return n
