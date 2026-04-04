@tool
extends PopupPanel
## Selection filter popover — provides bulk selection tools:
## Select by normal (walls/floors/ceilings), by material, by visgroup,
## and "Select Similar" based on the current face or brush.

signal filter_applied(nodes: Array, faces: Dictionary)

var _root: Node = null  # LevelRoot reference
var _hf_selection: Array = []  # Current plugin selection
var _vbox: VBoxContainer


func _ready() -> void:
	size = Vector2(240, 0)
	_build_ui()


func _build_ui() -> void:
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	add_child(_vbox)

	var title = Label.new()
	title.text = "Selection Filters"
	title.add_theme_font_size_override("font_size", 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)
	_vbox.add_child(HSeparator.new())

	# --- By Normal ---
	var normal_label = Label.new()
	normal_label.text = "By Normal"
	normal_label.add_theme_font_size_override("font_size", 11)
	normal_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(normal_label)

	var normal_row1 = HBoxContainer.new()
	normal_row1.add_theme_constant_override("separation", 4)
	_vbox.add_child(normal_row1)
	_add_filter_btn(normal_row1, "Walls", "Select all vertical faces (walls)", "_filter_walls")
	_add_filter_btn(normal_row1, "Floors", "Select all upward-facing faces", "_filter_floors")
	_add_filter_btn(normal_row1, "Ceilings", "Select all downward-facing faces", "_filter_ceilings")

	_vbox.add_child(HSeparator.new())

	# --- By Material ---
	var mat_label = Label.new()
	mat_label.text = "By Material"
	mat_label.add_theme_font_size_override("font_size", 11)
	mat_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(mat_label)

	var mat_row = HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(mat_row)
	_add_filter_btn(
		mat_row,
		"Same Material",
		"Select all faces with the same material as current",
		"_filter_same_material"
	)

	_vbox.add_child(HSeparator.new())

	# --- Select Similar ---
	var sim_label = Label.new()
	sim_label.text = "Select Similar"
	sim_label.add_theme_font_size_override("font_size", 11)
	sim_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(sim_label)

	var sim_row = HBoxContainer.new()
	sim_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(sim_row)
	_add_filter_btn(
		sim_row,
		"Similar Faces",
		"Select faces with matching material + normal",
		"_filter_similar_faces"
	)
	_add_filter_btn(
		sim_row, "Similar Brushes", "Select brushes with similar size", "_filter_similar_brushes"
	)

	_vbox.add_child(HSeparator.new())

	# --- By Visgroup ---
	var vg_label = Label.new()
	vg_label.text = "By Visgroup"
	vg_label.add_theme_font_size_override("font_size", 11)
	vg_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_vbox.add_child(vg_label)

	var vg_row = HBoxContainer.new()
	vg_row.name = "VisgroupRow"
	vg_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(vg_row)
	# Visgroup buttons are rebuilt dynamically in show_for()

	# --- Detail filter ---
	_vbox.add_child(HSeparator.new())
	var detail_row = HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(detail_row)
	_add_filter_btn(
		detail_row, "Detail Brushes", "Select only func_detail / detail brushes", "_filter_detail"
	)
	_add_filter_btn(
		detail_row,
		"Structural",
		"Select only structural (non-detail) brushes",
		"_filter_structural"
	)


func _add_filter_btn(parent: Control, text: String, tooltip: String, method: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", 11)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(Callable(self, method))
	parent.add_child(btn)
	return btn


## Call before popup() to inject current state.
func show_for(root: Node, hf_selection: Array) -> void:
	_root = root
	_hf_selection = hf_selection
	_rebuild_visgroup_buttons()


func _rebuild_visgroup_buttons() -> void:
	var row = _vbox.get_node_or_null("VisgroupRow")
	if not row:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if not _root or not _root.visgroup_system:
		var none_lbl = Label.new()
		none_lbl.text = "(no visgroups)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		var _muted = HFThemeUtils.muted_text()
		_muted.a = 0.45
		none_lbl.add_theme_color_override("font_color", _muted)
		row.add_child(none_lbl)
		return
	var names: PackedStringArray = _root.get_visgroup_names()
	if names.is_empty():
		var none_lbl = Label.new()
		none_lbl.text = "(no visgroups)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		var _muted = HFThemeUtils.muted_text()
		_muted.a = 0.45
		none_lbl.add_theme_color_override("font_color", _muted)
		row.add_child(none_lbl)
		return
	for vg_name in names:
		var btn = Button.new()
		btn.text = vg_name
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "Select all brushes in visgroup '%s'" % vg_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_filter_visgroup.bind(vg_name))
		row.add_child(btn)


# ---------------------------------------------------------------------------
# Filter implementations
# ---------------------------------------------------------------------------


func _get_all_brushes() -> Array:
	if not _root:
		return []
	var out: Array = []
	for node in _root._iter_pick_nodes():
		if _root.is_brush_node(node):
			out.append(node)
	return out


func _filter_walls() -> void:
	_select_faces_by_normal(func(n: Vector3) -> bool: return absf(n.y) < 0.3)


func _filter_floors() -> void:
	_select_faces_by_normal(func(n: Vector3) -> bool: return n.y > 0.7)


func _filter_ceilings() -> void:
	_select_faces_by_normal(func(n: Vector3) -> bool: return n.y < -0.7)


func _select_faces_by_normal(predicate: Callable) -> void:
	if not _root:
		return
	var face_sel: Dictionary = {}
	var brushes := _get_all_brushes()
	for brush in brushes:
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = _face_key(brush)
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if face:
				var world_normal: Vector3 = (basis * face.normal).normalized()
				if predicate.call(world_normal):
					indices.append(i)
		if not indices.is_empty():
			face_sel[key] = indices
	filter_applied.emit([], face_sel)
	visible = false


func _filter_same_material() -> void:
	if not _root:
		return
	# Get material indices from currently selected faces
	var mat_indices: Array = _get_selected_material_indices()
	if mat_indices.is_empty():
		return
	var face_sel: Dictionary = {}
	var brushes := _get_all_brushes()
	for brush in brushes:
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = _face_key(brush)
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if face and mat_indices.has(face.material_idx):
				indices.append(i)
		if not indices.is_empty():
			face_sel[key] = indices
	filter_applied.emit([], face_sel)
	visible = false


func _filter_similar_faces() -> void:
	if not _root:
		return
	# Match by material AND world-space normal direction (within 15 degrees)
	var ref_normals: Array = _get_selected_face_world_normals()
	var ref_faces: Array = _get_selected_face_refs()
	if ref_faces.is_empty():
		return
	var face_sel: Dictionary = {}
	var brushes := _get_all_brushes()
	for brush in brushes:
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = _face_key(brush)
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if not face:
				continue
			var world_normal: Vector3 = (basis * face.normal).normalized()
			for ri in range(ref_faces.size()):
				var ref = ref_faces[ri]
				var ref_wn: Vector3 = ref_normals[ri] if ri < ref_normals.size() else ref.normal
				if face.material_idx == ref.material_idx and world_normal.dot(ref_wn) > 0.966:
					indices.append(i)
					break
		if not indices.is_empty():
			face_sel[key] = indices
	filter_applied.emit([], face_sel)
	visible = false


func _filter_similar_brushes() -> void:
	if not _root:
		return
	# Match brushes by approximate size (within 20%)
	var ref_sizes: Array = []
	for node in _hf_selection:
		if node is DraftBrush and is_instance_valid(node):
			ref_sizes.append((node as DraftBrush).size)
	if ref_sizes.is_empty():
		return
	var tolerance := 0.2
	var picked: Array = []
	var brushes := _get_all_brushes()
	for brush in brushes:
		if not (brush is DraftBrush):
			continue
		var sz: Vector3 = (brush as DraftBrush).size
		for ref_sz in ref_sizes:
			if _size_similar(sz, ref_sz, tolerance):
				picked.append(brush)
				break
	filter_applied.emit(picked, {})
	visible = false


func _filter_visgroup(vg_name: String) -> void:
	if not _root or not _root.visgroup_system:
		return
	var members: Array = _root.visgroup_system.get_members_of(vg_name)
	filter_applied.emit(members, {})
	visible = false


func _filter_detail() -> void:
	var picked: Array = []
	var brushes := _get_all_brushes()
	for brush in brushes:
		if brush.has_meta("brush_entity_class"):
			var cls: String = str(brush.get_meta("brush_entity_class", ""))
			if cls == "func_detail" or cls.contains("detail"):
				picked.append(brush)
	filter_applied.emit(picked, {})
	visible = false


func _filter_structural() -> void:
	var picked: Array = []
	var brushes := _get_all_brushes()
	for brush in brushes:
		var cls: String = str(brush.get_meta("brush_entity_class", ""))
		if cls == "" or cls == "worldspawn":
			picked.append(brush)
	filter_applied.emit(picked, {})
	visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _face_key(brush: Node) -> String:
	if brush == null:
		return ""
	if brush is DraftBrush:
		var b := brush as DraftBrush
		if b.brush_id != "":
			return b.brush_id
	return str(brush.get_instance_id())


func _get_selected_material_indices() -> Array:
	if not _root:
		return []
	var indices: Array = []
	for key in _root.face_selection.keys():
		var brush = _root._find_brush_by_key(str(key))
		if not brush:
			continue
		var face_indices: Array = _root.face_selection.get(key, [])
		for fi in face_indices:
			var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
			if int(fi) >= 0 and int(fi) < faces.size():
				var mat_idx: int = faces[int(fi)].material_idx
				if not indices.has(mat_idx):
					indices.append(mat_idx)
	return indices


func _get_selected_face_refs() -> Array:
	if not _root:
		return []
	var refs: Array = []
	for key in _root.face_selection.keys():
		var brush = _root._find_brush_by_key(str(key))
		if not brush:
			continue
		var face_indices: Array = _root.face_selection.get(key, [])
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		for fi in face_indices:
			if int(fi) >= 0 and int(fi) < faces.size():
				refs.append(faces[int(fi)])
	return refs


func _get_selected_face_world_normals() -> Array:
	if not _root:
		return []
	var normals: Array = []
	for key in _root.face_selection.keys():
		var brush = _root._find_brush_by_key(str(key))
		if not brush:
			continue
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var face_indices: Array = _root.face_selection.get(key, [])
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		for fi in face_indices:
			if int(fi) >= 0 and int(fi) < faces.size():
				normals.append((basis * faces[int(fi)].normal).normalized())
	return normals


func _size_similar(a: Vector3, b: Vector3, tolerance: float) -> bool:
	# Sort components so orientation doesn't matter
	var sa := _sorted_vec(a)
	var sb := _sorted_vec(b)
	for i in range(3):
		var ref_val: float = maxf(sb[i], 0.01)
		if absf(sa[i] - sb[i]) / ref_val > tolerance:
			return false
	return true


func _sorted_vec(v: Vector3) -> Array:
	var a := [v.x, v.y, v.z]
	a.sort()
	return a
