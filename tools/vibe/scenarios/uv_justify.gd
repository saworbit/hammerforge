@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The six Justify buttons, measured against where the texture ends up.
##
## Justify is the texturing pass of every real map: select the faces of a wall,
## press Fit, press Left, and the texture sits where it should. The dock offers
## Fit, Center, Left, Right, Top and Bottom, each of them a one-line mode string
## into `justify_selected_faces()`.
##
## Nothing here takes the operation's word for it. Each mode is run and then the
## face's UVs are read back -- the hand layout in `custom_uvs` when there is one,
## otherwise recomputed from its own vertices through the same projection the
## renderer uses -- and the resulting UV rectangle is what gets reported. A mode
## whose name says "left" and whose result does not start at u=0 has not done
## what the button says.

const FaceData = preload("res://addons/hammerforge/face_data.gd")

const MODES := ["fit", "center", "left", "right", "top", "bottom"]


func id() -> String:
	return "uv-justify"


func summary() -> String:
	return "where each Justify mode puts a face's texture, measured off the face"


func run() -> void:
	await _each_mode_on_a_plain_wall()
	await _on_a_rotated_texture()
	await _on_hand_edited_uvs()
	await _treat_as_one()
	await _modes_the_dock_cannot_reach()


## The rectangle the face actually textures with.
##
## `custom_uvs` wins when it is there, because that is what a hand layout is and
## what the renderer uses. Reading the projection regardless meant this reported
## the same numbers whatever Justify did to the layout (#654).
func _uv_rect(face) -> Rect2:
	var uvs: PackedVector2Array = face.custom_uvs
	if uvs.is_empty():
		uvs = face._project_uvs_for_vertices(face.local_verts)
	if uvs.is_empty():
		return Rect2()
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	return Rect2(lo, hi - lo)


func _select_face(root: Node3D, brush, face_idx: int) -> void:
	root.clear_face_selection()
	root.toggle_face_selection(brush, face_idx, false)


func _each_mode_on_a_plain_wall() -> void:
	note("-- each mode on one face of a 256x128x16 wall --")
	for mode in MODES:
		var root: Node3D = await fresh_root()
		var wall = box(root, Vector3(256, 128, 16), Vector3.ZERO)
		await frame()
		var face = wall.faces[0]
		var before := _uv_rect(face)
		_select_face(root, wall, 0)
		root.justify_selected_faces(mode, false)
		var after := _uv_rect(face)
		note("%s: %s -> %s" % [mode, _r(before), _r(after)])
		match mode:
			"fit":
				if not (
					is_equal_approx(after.position.x, 0.0)
					and is_equal_approx(after.position.y, 0.0)
					and is_equal_approx(after.size.x, 1.0)
					and is_equal_approx(after.size.y, 1.0)
				):
					flag("Fit does not put the face on the unit square", _r(after))
			"left":
				if not is_equal_approx(after.position.x, 0.0):
					flag("Left does not put the face's left edge at u=0", _r(after))
				if not is_equal_approx(after.position.y, before.position.y):
					flag("Left moved the face vertically", "%s -> %s" % [_r(before), _r(after)])
			"right":
				if not is_equal_approx(after.position.x + after.size.x, 1.0):
					flag("Right does not put the face's right edge at u=1", _r(after))
			"top":
				if not is_equal_approx(after.position.y, 0.0):
					flag("Top does not put the face's top edge at v=0", _r(after))
			"bottom":
				if not is_equal_approx(after.position.y + after.size.y, 1.0):
					flag("Bottom does not put the face's bottom edge at v=1", _r(after))
			"center":
				var mid := after.position + after.size * 0.5
				if not (is_equal_approx(mid.x, 0.5) and is_equal_approx(mid.y, 0.5)):
					flag("Center does not centre the face on 0.5,0.5", "centre %s" % mid)


## A mapper rotates a texture 30 degrees, then justifies it. The rotation is
## applied before the scale and offset, so a shift computed in final UV space
## is the right space for it -- this checks that it is.
func _on_a_rotated_texture() -> void:
	note("-- with uv_rotation set, which is applied before the offset --")
	for mode in ["left", "fit", "center"]:
		var root: Node3D = await fresh_root()
		var wall = box(root, Vector3(256, 128, 16), Vector3.ZERO)
		await frame()
		var face = wall.faces[0]
		face.uv_rotation = deg_to_rad(30.0)
		face.custom_uvs = PackedVector2Array()
		var before := _uv_rect(face)
		_select_face(root, wall, 0)
		root.justify_selected_faces(mode, false)
		var after := _uv_rect(face)
		note("rotated 30deg, %s: %s -> %s" % [mode, _r(before), _r(after)])
		if mode == "left" and not is_equal_approx(after.position.x, 0.0):
			flag("Left on a rotated face does not reach u=0", _r(after))
		if (
			mode == "fit"
			and not (is_equal_approx(after.size.x, 1.0) and is_equal_approx(after.size.y, 1.0))
		):
			flag("Fit on a rotated face does not fill the unit square", _r(after))
		if mode == "center":
			var mid := after.position + after.size * 0.5
			if not (is_equal_approx(mid.x, 0.5) and is_equal_approx(mid.y, 0.5)):
				flag("Center on a rotated face does not centre it", "centre %s" % mid)


## The UV editor writes `custom_uvs`: a per-vertex layout a mapper dragged by
## hand. Justify reads those to work out where the face currently sits, and then
## every branch of `_justify_face()` clears them. This asks what a hand-aligned
## face looks like after one Justify press.
func _on_hand_edited_uvs() -> void:
	note("-- a face whose UVs were dragged by hand in the UV editor --")
	var root: Node3D = await fresh_root()
	var wall = box(root, Vector3(256, 128, 16), Vector3.ZERO)
	await frame()
	var face = wall.faces[0]
	face.ensure_custom_uvs()
	var hand := PackedVector2Array()
	for i in face.custom_uvs.size():
		# A deliberate, non-projective layout: the trapezoid a mapper makes when
		# they drag one corner of a decal to line it up with a doorframe.
		var uv: Vector2 = face.custom_uvs[i]
		hand.append(Vector2(uv.x * 0.5 + 0.25, uv.y * 0.5 + 0.1 * float(i)))
	face.custom_uvs = hand
	note("hand-edited UVs", "%s verts, rect %s" % [hand.size(), _r(_rect_of(hand))])
	_select_face(root, wall, 0)
	root.justify_selected_faces("left", false)
	note("custom_uvs after Justify Left", face.custom_uvs.size())
	if face.custom_uvs.size() == 0:
		known(
			654,
			"Justify discards a hand-edited UV layout instead of moving it",
			(
				"the UV editor writes custom_uvs; every _justify_face() branch sets "
				+ "custom_uvs = PackedVector2Array(), so the face falls back to its "
				+ "projection and the mapper's alignment is gone with no warning and "
				+ "no separate undo step"
			)
		)
	var after := _uv_rect(face)
	note("resulting rect", _r(after))


## The face of a brush that looks at the camera, which is the one a mapper
## textures. Face 0 is the +X face of a box, and a planar projection on it reads
## (z, y): three brushes in a row along X share it whatever the projection does,
## so measuring that one says nothing about a run of wall.
func _front_face(brush) -> int:
	var best := 0
	var best_dot := -INF
	for i in brush.faces.size():
		var d: float = brush.faces[i].normal.normalized().dot(Vector3.BACK)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## Treat as one: several faces of a wall justified as a single sheet, which is
## how a mapper textures a run of wall so the texture does not restart at each
## brush.
func _treat_as_one() -> void:
	note("-- treat-as-one across three brushes in a row --")
	var root: Node3D = await fresh_root()
	var brushes := []
	for i in 3:
		brushes.append(box(root, Vector3(128, 128, 16), Vector3(i * 128, 0, 0)))
		await frame()
	root.clear_face_selection()
	for b in brushes:
		root.toggle_face_selection(b, _front_face(b), true)
	note("faces selected", root.get_face_selection())
	root.justify_selected_faces("fit", true)
	var rects: Array[Rect2] = []
	for b in brushes:
		rects.append(_uv_rect(b.faces[_front_face(b)]))
	note("three faces after Fit (treat as one)", ", ".join(rects.map(func(r): return _r(r))))
	var union := rects[0]
	for r in rects:
		union = union.merge(r)
	note("their union", _r(union))
	if not (is_equal_approx(union.size.x, 1.0) and is_equal_approx(union.size.y, 1.0)):
		flag("treat-as-one Fit does not put the three faces on one unit square", _r(union))
	var identical := true
	for r in rects:
		if not r.is_equal_approx(rects[0]):
			identical = false
	if identical:
		flag(
			"treat-as-one gives every face the same UV rectangle",
			(
				(
					"three faces of three brushes side by side all land on %s, so the "
					+ "texture restarts at each brush -- which is the thing the "
					+ "checkbox exists to stop"
				)
				% _r(rects[0])
			)
		)
	# Each face should hold its own third of the sheet, in the order the brushes
	# sit in the level.
	for i in range(1, rects.size()):
		if rects[i].position.x <= rects[i - 1].position.x:
			flag(
				"treat-as-one does not lay the faces out in the order they sit",
				"%s then %s" % [_r(rects[i - 1]), _r(rects[i])]
			)


## `_justify_face()` handles a seventh mode, "stretch", that no surface passes.
func _modes_the_dock_cannot_reach() -> void:
	note("-- modes in the code against modes on a button --")
	var body := FileAccess.get_file_as_string("res://addons/hammerforge/systems/hf_brush_system.gd")
	var implemented: Array[String] = []
	for mode in ["fit", "center", "left", "right", "top", "bottom", "stretch", "scale"]:
		if body.find('"%s":' % mode) >= 0:
			implemented.append(mode)
	note("modes _justify_face implements", implemented)
	var dock := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var cmds := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_commands.gd")
	var reachable: Array[String] = []
	for mode in implemented:
		if dock.find('_on_justify("%s")' % mode) >= 0 or cmds.find('"justify_%s"' % mode) >= 0:
			reachable.append(mode)
	note("modes a surface can ask for", reachable)
	for mode in implemented:
		if mode in reachable:
			continue
		# An unreachable mode is only worth saying when it is also a different
		# answer from the ones that are reachable.
		var root: Node3D = await fresh_root()
		var wall = box(root, Vector3(256, 128, 16), Vector3.ZERO)
		await frame()
		_select_face(root, wall, 0)
		root.justify_selected_faces(mode, false)
		var got := _uv_rect(wall.faces[0])
		var root2: Node3D = await fresh_root()
		var wall2 = box(root2, Vector3(256, 128, 16), Vector3.ZERO)
		await frame()
		_select_face(root2, wall2, 0)
		root2.justify_selected_faces("fit", false)
		var fit := _uv_rect(wall2.faces[0])
		if got.is_equal_approx(fit):
			note("'%s' is unreachable and identical to 'fit'" % mode, _r(got))
		else:
			flag(
				"'%s' is implemented, different from every reachable mode, and unreachable" % mode,
				"%s against fit's %s" % [_r(got), _r(fit)]
			)


func _rect_of(uvs: PackedVector2Array) -> Rect2:
	if uvs.is_empty():
		return Rect2()
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	return Rect2(lo, hi - lo)


func _r(rect: Rect2) -> String:
	return (
		"u[%.3f..%.3f] v[%.3f..%.3f]"
		% [
			rect.position.x,
			rect.position.x + rect.size.x,
			rect.position.y,
			rect.position.y + rect.size.y,
		]
	)
