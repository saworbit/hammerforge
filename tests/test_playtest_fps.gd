extends GutTest

const PlaytestFPS = preload("res://addons/hammerforge/playtest_fps.gd")


func test_gravity_uses_project_setting_with_fallback():
	var player := CharacterBody3D.new()
	player.set_script(PlaytestFPS)
	add_child_autoqfree(player)
	assert_gt(player.gravity, 0.0, "Playtest gravity must not be zero in a default project")


func test_ensure_hud_creates_reticle_and_pause_overlay():
	var player := CharacterBody3D.new()
	player.set_script(PlaytestFPS)
	add_child_autoqfree(player)
	player._ensure_hud()
	var hud := player.get_node_or_null("PlaytestHUD")
	assert_not_null(hud, "Playtest HUD canvas should exist")
	assert_not_null(hud.get_node_or_null("Reticle"), "Crosshair reticle should exist")
	var pause := hud.get_node_or_null("PauseOverlay")
	assert_not_null(pause, "Pause/controls overlay should exist")
	assert_false(pause.visible, "Pause overlay starts hidden while mouse is captured")
	player._set_cursor_captured(false)
	assert_true(pause.visible, "Pause overlay shows when the cursor is released")
