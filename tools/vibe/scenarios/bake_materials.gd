@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the bake does with the materials a mapper put on faces.
##
## The Materials panel assigns a palette slot per face, the face carries
## `material_idx`, and the editor preview shows it. The bake has two paths: the
## face-material path, which triangulates each face and resolves its own
## material, and the CSG path, which does not. Which one runs is decided by
## `bake_use_face_materials`, a check box in the Advanced fold of the Test tab,
## and `LevelRoot.bake_use_face_materials` defaults to `false`.

const FaceData = preload("res://addons/hammerforge/face_data.gd")


func id() -> String:
	return "bake-materials"


func summary() -> String:
	return "whether per-face materials reach the baked mesh with the settings a level starts with"


func run() -> void:
	await _two_materials_on_one_brush()


## Every material on every surface under the baked container.
func _baked_materials(root: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [root.baked_container]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node == null:
			continue
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mesh: Mesh = node.mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var m = node.get_surface_override_material(s)
				if m == null:
					m = mesh.surface_get_material(s)
				out.append(m)
	return out


func _distinct(materials: Array) -> int:
	var seen: Array = []
	for m in materials:
		if m != null and not seen.has(m):
			seen.append(m)
	return seen.size()


func _coloured(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	return mat


func _two_materials_on_one_brush() -> void:
	var root: Node3D = await fresh_root("BakeMaterialLevel")
	var b = box(root, Vector3(128, 64, 32))
	await frame()
	var red: int = root.add_material_to_palette(_coloured(Color.RED))
	var blue: int = root.add_material_to_palette(_coloured(Color.BLUE))
	for i in range(b.faces.size()):
		b.faces[i].material_idx = red if i < 3 else blue
	b.rebuild_preview()
	await frame()
	note("palette slots", [red, blue])
	note("bake_use_face_materials on a fresh level", root.get("bake_use_face_materials"))

	root.tag_full_reconcile()
	var ok: bool = await root.bake(true, false, 0)
	await frame()
	var as_shipped: Array = _baked_materials(root)
	note("bake succeeded", ok)
	note("surfaces in the baked mesh, as shipped", as_shipped.size())
	note("distinct materials on them", _distinct(as_shipped))

	root.set("bake_use_face_materials", true)
	root.tag_full_reconcile()
	var ok2: bool = await root.bake(true, false, 0)
	await frame()
	var with_flag: Array = _baked_materials(root)
	note("bake succeeded with the flag on", ok2)
	note("surfaces in the baked mesh with the flag on", with_flag.size())
	note("distinct materials on them", _distinct(with_flag))

	if _distinct(as_shipped) < 2 and _distinct(with_flag) >= 2:
		flag(
			"per-face materials do not reach the bake a level starts with",
			(
				(
					"two palette materials on one brush's faces come out as %d material(s) on the"
					+ " baked mesh with the settings a new level has, and %d once"
					+ " bake_use_face_materials is turned on. The flag defaults to false on"
					+ " LevelRoot and the check box that mirrors it is unticked inside the Test"
					+ " tab's Advanced fold, so the Materials panel, the face selection filters and"
					+ " the UV controls all work on the preview and stop at the bake. Nothing on"
					+ " the bake path says the face materials were dropped -- the log line that"
					+ " does exist fires the other way round, when the flag is on and a cut forces"
					+ " the CSG path."
				)
				% [_distinct(as_shipped), _distinct(with_flag)]
			)
		)
