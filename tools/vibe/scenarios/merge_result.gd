@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Merge makes of two boxes that share a face.
##
## Two 2 m boxes side by side are one 4 x 2 x 2 box. Merge is the tool for
## making them one brush, and a brush in this lineage is the intersection of its
## planes, so the merged brush should have the six faces of the box it is. This
## counts the faces it gets, asks Validate, and follows it through a `.map`
## export and import, where a face that is inside the solid becomes a plane that
## cuts it.


func id() -> String:
	return "merge-result"


func summary() -> String:
	return "the faces Merge gives two boxes that share a face, and what Validate and .map make of them"


func run() -> void:
	var root: Node3D = await fresh_root()
	var a = box(root, Vector3(2, 2, 2), Vector3(-1, 1, 0))
	var b = box(root, Vector3(2, 2, 2), Vector3(1, 1, 0))
	var result = root.merge_brushes_by_ids(
		[str(a.get_meta("brush_id", "")), str(b.get_meta("brush_id", ""))]
	)
	await frame()
	var merged: Array = []
	for n in root._iter_managed_brush_nodes():
		merged.append(n)
	note("merge", "%s %s" % [result.ok, result.message])
	if merged.size() != 1:
		flag("merge left %d brushes" % merged.size())
		return
	var m = merged[0]
	var faces: Array = m.faces
	var interior := 0
	for f in faces:
		# A face of the merged solid lies on its outside, which for a 4 x 2 x 2
		# box centred at (0, 1, 0) means |x| = 2, y = 0 or 2, or |z| = 1.
		var c := Vector3.ZERO
		for v in f.local_verts:
			c += m.global_transform * v
		c /= maxf(1.0, f.local_verts.size())
		var on_hull := (
			absf(absf(c.x) - 2.0) < 0.01
			or absf(c.y) < 0.01
			or absf(c.y - 2.0) < 0.01
			or absf(absf(c.z) - 1.0) < 0.01
		)
		if not on_hull:
			interior += 1
	note(
		"faces on the merged brush",
		"%d, of which %d lie inside the solid" % [faces.size(), interior]
	)
	var issues: Array = root.validate_level(false).get("issues", [])
	note("validate", issues)

	var path := "user://merge_result.map"
	root.export_map(path, "valve220")
	var text := FileAccess.get_file_as_string(path)
	var planes := 0
	for line in text.split("\n"):
		if line.strip_edges().begins_with("("):
			planes += 1
			print("          plane ", line.strip_edges().substr(0, 100))
	var back: Node3D = await fresh_root("Imported")
	back.import_map(path)
	await frame()
	var imported: Array = []
	for n in back._iter_managed_brush_nodes():
		imported.append(n)
	var sizes: Array = []
	for n in imported:
		sizes.append(HFVibe.local_extent(n))
	note(
		".map export",
		"%d plane lines; import gives %d brush(es), extents %s" % [planes, imported.size(), sizes]
	)
	if interior > 0:
		known(
			1200,
			"Merge keeps the %d faces where two boxes touched, inside the merged brush" % interior,
			(
				(
					"two 2 m boxes sharing a face merged into one brush of %d faces. Validate: %s. "
					+ "The .map export writes %d planes; imported back it is %d brush(es) of extent %s"
				)
				% [faces.size(), issues, planes, imported.size(), sizes]
			)
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await drop_root(back)
	await drop_root(root)
