extends GutTest
## Every dock action that waits for a bake, with the plugin disabled while it
## bakes and the level left open.
##
## A bake runs over frames, and the editor stays live meanwhile, so the plugin can
## be switched off under Project Settings before it ends. The dock goes with it,
## and the action came back to a freed dock: Quick Play stopped on a script error
## reading `dock.level_root`. Each action must now stop quietly instead.
##
## Play from Camera is not here: it needs the plugin's editor camera, which the
## dock is not handed headless, so it stops before it bakes.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

const ACTIONS := [
	"bake",
	"bake_selected",
	"quick_play",
	"quick_play_selected_area",
	"export_playtest",
	"export_game_scene",
	"spawn_validate",
	"spawn_preview",
	"bake_preview",
]

var rig


func after_each():
	if rig:
		await rig.take_down()
	rig = null


func test_each_action_stops_quietly_when_the_plugin_goes_mid_bake(action = use_parameters(ACTIONS)):
	rig = PluginRig.new()
	await rig.bring_up(self, true)
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3(0, 2, 0))
	var dock = rig.plugin.dock
	_start(action, level, box, dock)
	assert_true(level.is_bake_in_flight(), "%s started a bake" % action)
	var errors_before := get_errors().size()
	PluginRig.PluginStandIn.teardown(rig.plugin)
	rig.plugin = null
	for _i in 20:
		await get_tree().process_frame
	assert_false(level.is_bake_in_flight(), "the bake finished")
	var errors: Array = []
	for e in get_errors().slice(errors_before):
		errors.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	assert_eq(errors, [], "%s came back to no plugin and raised nothing" % action)


func _start(action: String, level: Node, box: Node, dock: Node) -> void:
	match action:
		"bake":
			dock._on_bake()
		"bake_selected":
			rig.select([box])
			dock._on_bake_selected()
		"quick_play":
			dock._on_quick_play()
		"quick_play_selected_area":
			rig.select([box])
			dock._on_quick_play_selected_area()
		"export_playtest":
			dock._on_export_playtest()
		"export_game_scene":
			dock._on_export_game_scene()
		"spawn_validate":
			level.spawn_system.create_default_spawn()
			dock._on_spawn_validate()
		"spawn_preview":
			level.spawn_system.create_default_spawn()
			dock._on_show_spawn_debug_toggled(true)
		"bake_preview":
			rig.plugin._toggle_bake_preview(level, true)
