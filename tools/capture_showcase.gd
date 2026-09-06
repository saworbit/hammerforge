extends SceneTree
## Render still screenshots of the showcase level for README and docs.
##
## Renders into a fixed-size SubViewport so output resolution is identical on
## every machine regardless of window size or DPI. Must run WITHOUT --headless:
## the headless dummy renderer produces blank images.
##
## Usage:
##   godot --path . -s res://tools/capture_showcase.gd
##   godot --path . -s res://tools/capture_showcase.gd -- --width=2560 --height=1440

const SHOWCASE := "res://samples/hf_demo_showcase.tscn"
const OUT_DIR := "res://docs/images/"

# name, camera position, look-at target, fov
const SHOTS := [
	# Level spans x +/-27, y 0..32, z +/-36. Framing has to clear the towers.
	# The hero is the interior: the colonnade is what makes this read as a level
	# rather than a walled box. An aerial from a corner puts a tower in front of
	# everything worth seeing.
	["showcase_hero", Vector3(0, 7, 28), Vector3(0, 8, -30), 72.0],
	["showcase_overview", Vector3(-7, 56, 64), Vector3(0, 3, -6), 48.0],
	["showcase_gallery", Vector3(14, 5, 13), Vector3(-7, 17, -12), 72.0],
]

var _width := 1920
var _height := 1080


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--help" or arg == "-h":
			_print_usage()
			quit(0)
			return
		if arg.begins_with("--width="):
			_width = maxi(320, int(arg.trim_prefix("--width=")))
		elif arg.begins_with("--height="):
			_height = maxi(240, int(arg.trim_prefix("--height=")))
	_run()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Refusing to run headless: the dummy renderer writes blank images.")
		printerr("Re-run without --headless.")
		quit(1)
		return

	var scene: PackedScene = load(SHOWCASE)
	if scene == null:
		printerr("Could not load ", SHOWCASE, " -- run build_showcase_scene.gd first.")
		quit(1)
		return

	var sub := SubViewport.new()
	sub.size = Vector2i(_width, _height)
	sub.own_world_3d = true
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_4X
	root.add_child(sub)

	sub.add_child(_make_environment())
	sub.add_child(_make_key_light())
	sub.add_child(_make_fill_light())

	var level: Node = scene.instantiate()
	sub.add_child(level)

	var camera := Camera3D.new()
	sub.add_child(camera)

	# Let the brush preview meshes build before baking.
	await process_frame
	await process_frame

	# LevelRoot spawns its own runtime MainCamera during these frames. Drop every
	# camera except ours or it reclaims `current` mid-capture.
	for stray in level.find_children("*", "Camera3D", true, false):
		stray.queue_free()
	await process_frame

	# LevelRoot starts its own bake when the level loads. Calling bake() while
	# that is still running is rejected by _try_begin_bake(), which reports the
	# refusal through the user_message signal -- silent outside the editor. Wait
	# for it to settle, then bake explicitly so the shot shows baked output with
	# the draft brushes hidden.
	var settled := false
	for _i in range(600):
		await process_frame
		if not level.is_bake_in_flight():
			settled = true
			break
	if not settled:
		printerr("Bake still in flight after 600 frames; capturing draft geometry.")
	else:
		var baked: bool = await level.bake(true, true)
		if not baked:
			printerr("Bake failed; capturing draft geometry instead.")
		for _i in range(4):
			await process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var written := 0
	for shot in SHOTS:
		camera.position = shot[1]
		camera.look_at(shot[2], Vector3.UP)
		camera.fov = shot[3]

		# Several frames so shadows, sky and mipmaps settle before the grab.
		for _i in range(4):
			await process_frame
		# Bind last: LevelRoot respawns its runtime MainCamera on a later frame
		# and it reclaims `current` from anything bound earlier.
		camera.make_current()
		await process_frame
		RenderingServer.force_draw()

		var image: Image = sub.get_texture().get_image()
		if image == null:
			printerr("Failed to capture ", shot[0])
			continue
		var path: String = OUT_DIR + shot[0] + ".png"
		var err: Error = image.save_png(path)
		if err != OK:
			printerr("Failed to save ", path, ": error ", err)
			continue
		print("wrote ", path, " (", image.get_width(), "x", image.get_height(), ")")
		written += 1

	print("HammerForge showcase capture complete: ", written, "/", SHOTS.size(), " shots")
	quit(0 if written == SHOTS.size() else 1)


func _make_environment() -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.30, 0.42, 0.60)
	sky_material.sky_horizon_color = Color(0.62, 0.68, 0.76)
	sky_material.ground_bottom_color = Color(0.34, 0.35, 0.38)
	sky_material.ground_horizon_color = Color(0.56, 0.58, 0.62)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true

	var holder := WorldEnvironment.new()
	holder.environment = env
	return holder


func _make_key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -125, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	return light


func _make_fill_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-28, 55, 0)
	light.light_energy = 0.35
	light.shadow_enabled = false
	return light


func _print_usage() -> void:
	print("HammerForge showcase capture")
	print("  --width=N    Output width (default 1920)")
	print("  --height=N   Output height (default 1080)")
	print("Example:")
	print("  godot --path . -s res://tools/capture_showcase.gd")
