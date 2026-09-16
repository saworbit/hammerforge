@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The material browser's three views, its filters, and what it calls a
## favourite.
##
## The browser is the surface a mapper picks a texture from, and the only thing
## it knows a material by is its `resource_path`. A palette can hold materials
## that have no path — anything built in the editor and not saved to disk — and
## the browser has to say something sensible about those rather than treating
## them as one material.

const BrowserType = preload("res://addons/hammerforge/ui/hf_material_browser.gd")
const ManagerType = preload("res://addons/hammerforge/material_manager.gd")


func id() -> String:
	return "material-browser"


func summary() -> String:
	return "what the material browser calls a favourite, and what its filters reach"


func run() -> void:
	await _favourites_key_on_path()
	await _filters()


func _browser(manager) -> Control:
	var browser = BrowserType.new()
	_tree.get_root().add_child(browser)
	await frame()
	browser.set_material_manager(manager)
	await frame()
	return browser


func _manager_with(paths: Array) -> Object:
	var manager = ManagerType.new()
	_tree.get_root().add_child(manager)
	for path in paths:
		var mat := StandardMaterial3D.new()
		if str(path) != "":
			mat.resource_path = str(path)
			mat.resource_name = str(path).get_file().get_basename()
		manager.materials.append(mat)
	return manager


func _favourites_key_on_path() -> void:
	# Two saved materials and two built in the editor and never saved. The
	# unsaved pair both have resource_path "".
	var manager = _manager_with(
		[
			"res://textures/brick.tres",
			"res://textures/metal.tres",
			"",
			"",
		]
	)
	var browser = await _browser(manager)
	note("palette slots", manager.materials.size())
	note("slots with no resource_path", 2)

	browser.add_favorite("res://textures/brick.tres")
	note("after favouriting brick, favourites", browser.get_favorite_infos(10))

	# Favouriting one unsaved material keys on "".
	browser.add_favorite("")
	var infos: Array = browser.get_favorite_infos(10)
	note("after favouriting one unsaved material, favourites", infos)
	var unsaved_favourites := 0
	for info in infos:
		if str(manager.materials[int(info["index"])].resource_path) == "":
			unsaved_favourites += 1
	note("unsaved materials now reported as favourites", unsaved_favourites)
	if unsaved_favourites > 1:
		known(
			544,
			"favouriting one unsaved material favourites all of them",
			(
				(
					"the browser keys favourites on `resource_path`, and every material built"
					+ " in the editor and not written to disk has the same empty path, so one"
					+ " star marks %d slots and un-starring any of them clears the lot"
				)
				% unsaved_favourites
			)
		)

	browser.remove_favorite("")
	note("after un-favouriting, favourites", browser.get_favorite_infos(10))

	# Favourites live in a plain Dictionary on the control. Nothing writes them
	# anywhere, so a second browser starts empty.
	var second = await _browser(manager)
	note("a freshly built browser's favourites", second.get_favorite_infos(10))
	if second.get_favorite_infos(10).is_empty() and not browser.get_favorite_infos(10).is_empty():
		known(
			545,
			"favourites do not survive the browser being rebuilt",
			(
				"`_favorites` is an in-memory Dictionary on the control with nothing reading"
				+ " or writing it to prefs, so every star a mapper sets is gone the next time"
				+ " the dock is built, and the shortcut HUD's favourites row empties with it"
			)
		)
	browser.queue_free()
	second.queue_free()
	await frame()


func _filters() -> void:
	var manager = _manager_with(
		[
			"res://addons/hammerforge/textures/materials/grid_blue.tres",
			"res://addons/hammerforge/textures/materials/grid_red.tres",
			"res://project/walls/brick.tres",
		]
	)
	var browser = await _browser(manager)
	note("view modes", BrowserType.ViewMode.keys())
	for mode in [0, 1, 2]:
		browser._view_mode = mode
		browser.rebuild()
		await frame()
		note("view %d cells" % mode, browser._cell_to_palette_index.size())
	browser._view_mode = 1
	browser._search_text = "brick"
	browser.rebuild()
	await frame()
	note("palette view searching 'brick'", browser._cell_to_palette_index.size())
	browser._search_text = ""
	browser._active_color_filter = "blue"
	browser.rebuild()
	await frame()
	var shown: Array = []
	for idx in browser._cell_to_palette_index:
		shown.append(manager.materials[int(idx)].resource_path.get_file())
	note("palette view with the colour filter 'blue'", shown)
	if shown.has("brick.tres"):
		note(
			"a non-prototype material ignores the colour filter",
			"documented in _passes_filters -- recorded so the behaviour is on the record"
		)
	browser.queue_free()
	await frame()
