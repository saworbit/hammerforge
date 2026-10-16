@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Merge makes of two boxes that share a face.
##
## Two 2 m boxes side by side are one 4 x 2 x 2 box. Merge is the tool for
## making them one brush, and a brush in this lineage is the intersection of its
## planes, so the merged brush should have the six faces of the box it is. This
## counts the faces it gets, asks Validate, and follows it through a `.map`
## export and import, where a face that is inside the solid becomes a plane that
## cuts it. Then it asks Merge for an L of three boxes, whose hull would fill the
## corner the mapper left empty.


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
	# Fixed by #1251: the merged brush is centred on what it holds, so its size
	# and origin are the 4 x 2 x 2 box's. It kept the first box's origin and the
	# default drag size, which is what Check Issues and the dock read.
	var size: Vector3 = m.size
	var at: Vector3 = m.global_position
	if not size.is_equal_approx(Vector3(4, 2, 2)) or not at.is_equal_approx(Vector3(0, 1, 0)):
		flag(
			"A merged brush no longer gives the size and centre of what it holds",
			"size %s at %s, for a 4 x 2 x 2 box centred at (0, 1, 0)" % [size, at]
		)
	else:
		note("merged size", "%s at %s" % [size, at])
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
	# Fixed by #1200: the merged brush is the box the two make, six faces, none
	# of them inside it.
	if interior > 0 or faces.size() != 6 or planes != 6 or not issues.is_empty():
		flag(
			"Merge no longer makes two boxes sharing a face into the box they are",
			(
				(
					"%d faces, %d inside the solid. Validate: %s. The .map export writes %d "
					+ "planes; imported back it is %d brush(es) of extent %s"
				)
				% [faces.size(), interior, issues, planes, imported.size(), sizes]
			)
		)
	else:
		note("merged box", "6 faces, none inside, nothing from Validate, 6 planes in the .map")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await drop_root(back)
	await drop_root(root)

	var l_root: Node3D = await fresh_root("L")
	var ids: Array = []
	for centre in [Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(-1, 3, 0)]:
		ids.append(str(box(l_root, Vector3(2, 2, 2), centre).get_meta("brush_id", "")))
	var refused = l_root.merge_brushes_by_ids(ids)
	await frame()
	var left: int = l_root._iter_managed_brush_nodes().size()
	note("an L of three boxes", "%s %s; %d brushes left" % [refused.ok, refused.user_text(), left])
	if refused.ok or left != 3 or not str(refused.user_text()).contains("convex"):
		flag(
			"Merge made an L of three boxes into one brush, filling the corner",
			"%s %s; %d brushes left" % [refused.ok, refused.user_text(), left]
		)
	await drop_root(l_root)
